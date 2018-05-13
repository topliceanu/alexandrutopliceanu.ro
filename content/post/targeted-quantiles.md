+++
title = "Targeted Quantiles in Prometheus"
date = "2018-03-11T19:25:53Z"
draft = false
+++

_The algorithm behind Prometheus' Summaries._

## Abstract

_TODO_

## Introduction

The hearthstone of understanding of how your distributed system works in production is monitoring.
In recent years, Prometheus has emerged as the most popular monitoring system for applications deployed on Kubernetes.
Apart from the more common counters and gauges, the prometheus client exposes the [summary](https://godoc.org/github.com/prometheus/client_golang/prometheus#Summary) metric type. In a go project, it might look like this:

```golang
// This is the definition of a metric which tracks the latency of an RPC request.
latency := prometheus.NewSummary(prometheus.SummaryOpts{
  Name:       "rpc_durations_seconds",
  Help:       "RPC latency distributions.",
  Objectives: map[float64]float64{0.5: 0.05, 0.9: 0.01, 0.99: 0.001},
})

// This is how you would use it.
reqDuration := rand.Float64()
latency.Observe(reqDuration)
```

This code was extracted from the [prometheus/client-golang example](https://github.com/prometheus/client_golang/blob/master/examples/random/main.go)

In the above case, the summary will give us the 99th, 90th and 50th percentile for the latency of that particular RPC request.

This is what it would look like in Graphana, a popular frontend for Prometheus:

![RPC Latency Chart in Graphana](rpc-latency.png)

Prometheus uses a data structure called Targeted Quantiles to calculate Summaries very efficiently. In this post I will describe how they are implemented and why they are so efficient.

## Quantiles and Percentiles

This section is a small detour to describe what quantiles and percentiles are.

A quantile `q` in a dataset of size n is the element with rank `math.Ceil(q * n)`, where `0 <= q <= 1` and the rank of an element is its index is the sorted dataset.

For example, let `a` be a list of 20 integers, between 1 and 20, with duplicates:

```golang
a := []int{11, 9, 13, 19, 13, 13, 5, 12, 7, 16, 6, 15, 17, 1, 19, 5, 11, 10, 18, 2}
```

Let's sort `a` into a variable called `b`:

```golang
b := []int{1, 2, 5, 5, 6, 7, 9, 10, 11, 11, 12, 13, 13, 13, 15, 16, 18, 17, 19, 19}
```

The 0.9 quantile of the dataset `a` of size 20 is the element with index `0.9 * 20 == 18` in the sorted version `b`, which is 17!

_Note_ that the quantile is defined as a function of all the values in the input dataset.

Percentiles are the same concept as quantiles, except percentiles are expressed as percentages. So the percentile `p` of a dataset of size n is the element with rank `math.Ceil(p * n / 100)`

In the above example, the 99th percentile is element with index `math.Ceil(99 * 20 / 100) == 20` in `b`, so the value `19`.

## How Does It Work

In the previous section we calculated the 0.9 quantile for an array of 20 numbers. We had the advantage of a small dataset. Tracking request latencies across an architecture with hundreds of microservices amounts to a very large volume of observations. The distribution of those observations typically has long tails which are of great interest: we want to know what is the worst latency a service produces. All this makes sampling not an option!

What is needed is a streaming approach with space complexity significantly sublinear to the size of the input. Some of the original conditions have to be relaxed: define the percentiles of interest from the start and introduce an acceptable error for each of them. That is the reason why, the `Objectives` of a Prometheus summary have the wanted quantiles as keys and the acceptable errors as values:

```golang
map[float64]float64{0.5: 0.05, 0.9: 0.01, 0.99: 0.001},
```

_Note_ that the error is not applied to the value returned but to the rank produced. Remember that a quantile coresponds to a rank in the sorted version of the input dataset, which in turn corresponds to a value from the original dataset. In the above example, the algorithm will produce percentiles in the range `[0.45, 0.55]` for the `0.5` target; `[0.89, 0.91]` for the `0.9` target and `[0.989, 0.991]` for the `0.99` target.

It is very important that the algorithm produces a value that was actually observed rather than an aggregate (like a mean or a max) by the definition of a quantile.

The abstract data structure employed by the algorithm is a sorted list, with the folling operations:

- `Insert(float64)` calculate the lowest and highest possible rank for the new value, then inserts it into the list, maintaining the list sorted. Each value in the list covers a range or ranks, bounded by the configured errors.
- `Query(float64) float64` traverses the list to find the value whose range or covered ranks includes the rank corresponding to the requested quantile. It then returns that value.
- `Compress()` walks through the list and removes all the values that are redundant; as more values are added, the rank intervals for the targeted quantiles shift and start overlaping. Compress finds these overlaping values and removes them.

The prometheus implementation uses a small slice (500 samples) as a concrete data structure and runs `Compress` imediately after each insert.

The following table shows the algorithm at work on a dataset of 30 samples: shuffled integeres from 1 to 30 inclusive.

![Targeted quantiles execution on a dataset of size 30](targeted-quantiles-execution.png)

You can find the script which generated this table [in this commit](https://github.com/topliceanu/perks/commit/cff191c15ce1991cf393d06813790a736867c61f). To make it work, the size of the internal list used in the implementation was reduced from 500 to 10, to better show how `Compress` works.

## Observations

Because quantile values will shift as more data is consumed, the algorithm has to keep value around to make sure it covers the error constraint. Consequently, the lower the error for a quantile, the more data the algorithm has to store.

For example, the 0.5 quantile with a 0.05 error is fine, because most values around the mean will be very similar so there's no point storing more of them. However, for 0.99 quantile the error has to be much smaller to catch the outliers. On the other had, the tail values are much less frequent so the algorithm will not have to store a lot of data.

The algorithm does not sample, that is to say it considers all the input values, but prunes the ones that are not relevant to the objective quantiles.

Space complexity is proportional to the number of quantiles of
interest, not the size of the input! To keep the data structure small, `Compress` has to be executed often to prune the values that are not needed. To get the best time complexity, a Red-Black Tree can be used for fast lookups, deletes and range queries.

Two separate data structure instances with the same target quantiles can be merged by simply inserting the values from one into the other and running `Compress`.

## Conclusion

Very interesting things occur in resource constrained environments. Tradeoffs have to be made and errors levels have to be accepted to do usefull work. There is a whole category of algorithms suitable for these situations and they prove useful outside of their original context. Targeted quantiles have been developed originally for networking hardware but we use them all the time to monitor our kuberentes deployments. I encourage you to always be curios about how the things you use every day work.

## References
1. The original paper cited in the Prometheus implementation is [Effective Computation of Biased Quantiles over Data Streams by Cormode et al.](https://www.cs.rutgers.edu/~muthu/bquant.pdf). It describes a generic algorithm called Biased Quantiles. It introduces High-Biased, Low-Biased and Targeted Quantiles as specializations. It contains a mathematical prof of correctness and an analysis of the performance characteristics.
2. A newer paper from the same research group: [Space- and Time-Efficieng Deterministic Algorithms for Biased Quantiles over Data Streams](http://dimacs.rutgers.edu/~graham/pubs/papers/bq-pods.pdf). It presents an even more generalised algorithm which extends to answering rank queries as well as biased and targeted quantiles.
2. The implementation used in the prometheus global client is [github.com/beorn7/perks/quantile](https://github.com/beorn7/perks/tree/master/quantile)
4. The [prometheus documentation](https://prometheus.io/docs/practices/histograms/#errors-of-quantile-estimation) for quantile estimation.
