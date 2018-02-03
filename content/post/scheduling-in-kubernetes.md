---
title: "Scheduling in Kubernetes"
date: 2018-02-01T22:08:22Z
draft: false
---

The importance of understanding the implementation of the tools we use in
production every day cannot be underestimated.

This process informs about the tradeoffs engineers made in the implementations.
Knowing a tool's strengths and weaknesses helps better design systems on top
of it; it exposes potential failure modes and helps debug critical errors when
they occur. It also reveals brilliant ideas, tricks, patterns and conventions used in
production systems.

In this post, I will go through the implementation of the default scheduler in
Kubernetes (k8s).
Although, k8s has a large set of features, tending towards a full-blown PaaS,
at it’s core, k8s is a cluster scheduler, that is to say, it schedules work
(pods) onto computing resources (nodes).

## The genericScheduler

K8s has different mechanisms to control pod scheduling: node and pod affinity and
anti-affinity taints and tolerations and it also has support for custom schedulers. I will look at how all these options factor into the default
scheduling process.

The core abstraction for the scheduler in k8s is called `genericScheduler`.
If you clone [github.com/kubernetes/kubernetes](github.com/kubernetes/kubernetes)
master, you can find it in [pkg/scheduler/core/generic_scheduler.go](https://github.com/kubernetes/kubernetes/blob/master/pkg/scheduler/core/generic_scheduler.go).
The main method of this structure is called `Schedule`, which
functions as a [template method pattern](https://en.wikipedia.org/wiki/Template_method_pattern),
ie. different implementations can modify specific steps, but the order in which
these steps are executed remains fixed.

Here is the `Schedule` method without logging and instrumentation:

```golang
// Schedule tries to schedule the given pod to one of node in the node list.
// If it succeeds, it will return the name of the node.
// If it fails, it will return a Fiterror error with reasons.
func (g *genericScheduler) Schedule(pod *v1.Pod, nodeLister algorithm.NodeLister) (string, error) {
    if err := podPassesBasicChecks(pod, g.pvcLister); err != nil {
        return "", err
    }

    nodes, err := nodeLister.List()
    if err != nil {
        return "", err
    }
    if len(nodes) == 0 {
        return "", ErrNoNodesAvailable
    }

    // Used for all fit and priority funcs.
    err = g.cache.UpdateNodeNameToInfoMap(g.cachedNodeInfoMap)
    if err != nil {
        return "", err
    }

    filteredNodes, failedPredicateMap, err := findNodesThatFit(pod, g.cachedNodeInfoMap, nodes, g.predicates, g.extenders, g.predicateMetaProducer, g.equivalenceCache, g.schedulingQueue)
    if err != nil {
        return "", err
    }

    if len(filteredNodes) == 0 {
        return "", &FitError{
            Pod:              pod,
            NumAllNodes:      len(nodes),
            FailedPredicates: failedPredicateMap,
        }
    }

    // When only one node after predicate, just use it.
    if len(filteredNodes) == 1 {
        return filteredNodes[0].Name, nil
    }

    metaPrioritiesInterface := g.priorityMetaProducer(pod, g.cachedNodeInfoMap)
    priorityList, err := PrioritizeNodes(pod, g.cachedNodeInfoMap, metaPrioritiesInterface, g.prioritizers, filteredNodes, g.extenders)
    if err != nil {
        return "", err
    }

    trace.Step("Selecting host")
    return g.selectHost(priorityList)
}
```

K8s schedules pods on a first come first served order. It formes a queue of all
the requests to schedule pods and processes them one by one. At this point, there
is no concurrency which makes the code simpler. I’ll show later how k8s makes
the process fast.

## Volumes

The first thing that happens is a call to `podPassesBasicChecks()`. Despite the
complicated sounding name, at the time of writing, this method makes sure that
all the PersistentVolumeClaims (PVCs) defined by the pod are ready to be used,
that is they have each been bound to a PersistentVolume (PV) and they are not
being deleted.

In k8s, nodes represent compute resources and pods consume those compute resources.
PVs are similar to nodes, but they represent disk resources available to the cluster.
Conceptually they map to physical disks, same way nodes maps to machine, of course,
in reality, there are layers of virtualization in between.
PVs are defined by the administrators of the cluster, while PVCs are
defined by the users of the cluster, the service developers.
Each PVC needs to bind to a PV in order for the containers to use the storage.

## Algorithm

Next up, the algorithm makes sure the list of available nodes is not empty!

I mentioned before that although pod scheduling requests are processed one by one,
k8s makes great effort to make this efficient, including caching and concurrent
execution. One of the pieces of data to be cached is the nodes' specs. It is reasonable
to assume that node information will not change often between successive runs of Schedule,
so it is cached and updated in `UpdateNodeNameToInfo()`.

K8s picks the most appropriate node out of the list of candidates in two steps: predicates and filters.

### Predicates

Predicates are pure functions which take a node and a pod and return a boolean
whether that pod fits onto the node or not. Predicates are meant to be fast and
should eliminate all the nodes that can’t fit the pod. Predicates are of type
[algorithm.FitPredicate](https://godoc.org/k8s.io/kubernetes/pkg/scheduler/algorithm#FitPredicate)
and model concepts like available resources, taints and tolerations, volume
availability, memory and disk pressure on the node, etc.

This is done in the call to `findNodesThatFit()`. This method executes all
predicates on all the available nodes. Because this step is CPU intensive,
but also, because the predicates are independent of each other, it runs
concurrently on 16 goroutines using the [workqueue.Parallelize](https://godoc.org/k8s.io/client-go/util/workqueue#Parallelize)
framework. This is the order in which they are executed by default ([source](https://github.com/kubernetes/kubernetes/blob/master/pkg/scheduler/algorithm/predicates/predicates.go#L102-L115)]):

``` golang
[]string{
  CheckNodeConditionPred,
  GeneralPred,
  HostNamePred,
  PodFitsHostPortsPred,
  MatchNodeSelectorPred,
  PodFitsResourcesPred,
  NoDiskConflictPred,
  PodToleratesNodeTaintsPred,
  PodToleratesNodeNoExecuteTaintsPred,
  CheckNodeLabelPresencePred,
  checkServiceAffinityPred,
  MaxEBSVolumeCountPred,
  MaxGCEPDVolumeCountPred,
  MaxAzureDiskVolumeCountPred,
  CheckVolumeBindingPred,
  NoVolumeZoneConflictPred,
  CheckNodeMemoryPressurePred,
  CheckNodeDiskPressurePred,
  MatchInterPodAffinityPred,
}
```

One question that comes to mind: Why is the PVCs check also done at the beginning
if it’s done here as a predicate? It might be for efficiency reasons.

### Priorities

Priorities, much like predicates, take a node and a pod but instead of a binary
value, return a _“score”_, an integer between 1 and 10. This step is called
filtering and is where the algorithm ranks all the nodes to find the best one
suited for the pod.
This is done in the `PrioritizeNodes()` method and is also runs concurrently on
16 goroutines and uses cached data. The scores are also weighted by the importance
of each priority function.

Finally, all the scores for a node are added to a final score per node. Then, nodes are
sorted by this final score in a priority queue (heap) which is returned by
`PrioritizeNodes()`.

The user of concurrency to compute the predicates and the final scores makes sense,
one question that I have is why is this hardcoded to 16 workers? I would expect
that tuning this value would be helpful, for instance in large clusters which run
the k8s master on powerful hardware. It may be that the yield is not significant.

## Node Selection

The final step is `selectHost()` which pops the top nodes from the priority queue.
If multiple nodes have the same score, this method picks one node in a round-robin manner and returns it. In turn, `Schedule()` will return the picked node

## Custom Scheduler

All pods in k8s are, by default, scheduled using this algorithm.
Pods objects have metadata, specs and state. In a scheduled pod’s resolved status,
there is the field: `"scheulderName": "defaultScheduler"`.

K8s supports the use of custom schedulers. A custom scheduler runs like a normal
deployment in k8s, where it is managed by the default scheduler. A custom scheduler,
let's say it is called `my-scheduler`, will pick up all the pods which have
`"schedulerName": "my-scheduler"` in their object spec.

You can learn more about this operation in these two blog posts:
[here](http://blog.kubernetes.io/2017/03/advanced-scheduling-in-kubernetes.html)
and [here](https://kubernetes.io/docs/tasks/administer-cluster/configure-multiple-schedulers/).

A question whose answer is not clear immediately from the code is how do multiple
schedulers coordinate. A scheduler needs to know which resources it has available
to assign pods to if there’s another scheduler competing for the same resources,
how does k8s prevent over-scheduling the nodes!?

## Conclusion

K8s' implementation of the generic scheduler, with it's FIFO logic, suggests that
it is optimized for long-running processes, such as services and microservice
architecture, which is where k8s is very popular at the moment. If the workloads
contained a lot of small and short jobs, for example, a serverless infrastructure,
the generic scheduler will probably not be fast enough.

In future blog posts, I will try to answer some of the questions from posed in
this post and continue my exploration of the k8s codebase.

