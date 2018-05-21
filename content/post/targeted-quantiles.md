+++
title = "Targeted Quantiles in Prometheus"
date = "2018-03-11T19:25:53Z"
draft = false
+++

_The algorithm behind Prometheus' Summaries._

## Abstract

Prometheus uses a technique called Targeted Quantiles to implement the Summary metric type which is used to monitor distributions, such as latencies.
Here, we give an overview of how the algorithm works, we answer why it is so efficient and how to configure Summaries.

## Introduction

A very important way of understanding how your distributed system works in production is to monitor it.
In recent years, Prometheus has emerged as the most popular monitoring system for applications deployed on Kubernetes.

Apart from the more common counters and gauges, the Prometheus client exposes the [Summary](https://godoc.org/github.com/prometheus/client_golang/prometheus#Summary) metric type.
In a Go project, it might look like this:

```golang
// This is the definition of a metric which tracks the latency of an RPC.
latency := prometheus.NewSummary(prometheus.SummaryOpts{
  Name:       "rpc_durations_seconds",
  Help:       "RPC latency distributions.",
  Objectives: map[float64]float64{0.5: 0.05, 0.9: 0.01, 0.99: 0.001},
})

// This is how you would use it somewhere in your code.
reqDuration := rand.Float64()
latency.Observe(reqDuration)
```

This code was extracted from the [prometheus/client-golang example](https://github.com/prometheus/client_golang/blob/master/examples/random/main.go)

In the above case, the Summary will give us the 99th, 90th and 50th percentile for the latency of that particular RPC request.

This is what it would look like in Graphana, a popular GUI for Prometheus:

![RPC Latency Chart in Graphana](rpc-latency.png)

Prometheus uses a data structure called Targeted Quantiles to calculate Summaries very efficiently.
In this post I will describe how they are implemented and why they are so efficient.

## Quantiles and Percentiles

This section is a small detour to describe what quantiles and percentiles are.

A quantile `q` in a dataset of size n is the element with rank `math.Ceil(q * n)`, where `0 <= q <= 1`.
The rank of an element is its index in the sorted dataset.

For example, let `a` be a list of 20 integers, between 1 and 20, as well as duplicates:

```golang
a := []int{11, 9, 13, 19, 13, 13, 5, 12, 7, 16, 6, 15, 17, 1, 19, 5, 11, 10, 18, 2}
```

Let's sort `a` into a variable called `b`:

```golang
b := []int{1, 2, 5, 5, 6, 7, 9, 10, 11, 11, 12, 13, 13, 13, 15, 16, 17, 18, 19, 19}
```

The 0.9 quantile of the dataset `a` of size 20 is the element with index `0.9 * 20 == 18` from the sorted version `b`, which is 18!

Percentiles are the same concept as quantiles, except percentiles are expressed as percentages.
So the percentile `p` of a dataset of size n is the element with rank `math.Ceil(p * n / 100)`, where `0 <= p <= 100`.

In the above example, the 99th percentile is element with index `math.Ceil(99 * 20 / 100) == 20` in `b`, resulting in the value `19`.

## Approach

In the previous section we calculated the 0.9 quantile for an array of 20 numbers.
We had the advantage of a small dataset.
Remember that the quantile is defined as a function of all the values in the input dataset.
Tracking request latencies across an architecture with hundreds of microservices amounts to a very large volume of observations, even for a narrow sliding time window.

The distributions of latency observations typically have long tails which are of great interest:
we want to know what are the worst latencies our services produce.
Sampling is a popular method to reduce dataset sizes, but has a high probability to miss outliers, so in this case it's not an option!

What is needed is a streaming approach with space complexity _significantly_ sublinear to the size of the input.
Some of the original conditions need to be relaxed: the quantiles of interest and acceptable errors for each of them must be defined apriori,
the system will not be able to produce any other quantile.
In practice, this limitation is minor and the benefits are substantial: a space complexity linear with the number of targeted quantiles, not the size of dataset.
The `Objectives` field of a Prometheus `Summary` has the targeted quantiles as keys and the acceptable errors as values:

```golang
map[float64]float64{0.5: 0.05, 0.9: 0.01, 0.99: 0.001},
```

_Note_ that the error is not applied to the value returned but to the rank produced.
Remember that a quantile corresponds to a rank in the sorted version of the input dataset, which in turn corresponds to a value from the original dataset.
In the above example, the algorithm will produce quantiles in the ranges:

- `[0.45, 0.55]` for the `0.5` target
- `[0.89, 0.91]` for the `0.9` target
- `[0.989, 0.991]` for the `0.99` target.

It is important that the algorithm produces values from the original dataset, rather than aggregates (like a mean or a max), by the definition of a quantile.
While aggregates are useful, higher abstractions on top of quantiles may use the property that the values were actually observed.

## Intuition

To get an intuition of how the algorithm works, consider the following graph:

![Probability Density Function For Three Quantiles 0.5, 0.9 and 0.99](probability-density-function.png)

It shows three gaussian probability density functions, one for each of the three quantiles:

* 0.5 quantile >> blue with median 50 and variance 10
* 0.9 quantile >> red with median 90 and variance 5
* 0.99 quantile >> yellow with median 99 and variance 3

On Ox, there are the numbers 1 to 100 ingested by the algorithm in random order.
Each point on any of the bell curves represents the probability that the Ox value will be returned by the algorithm when queried for a target quantile.

Because quantile values will shift as more data is consumed, the algorithm has to keep neighbouring values around to make sure it covers the error constraint.
Consequently, the lower the allowed error for a quantile, the more data the algorithm has to store.

For example, the 0.5th quantile with a 0.05 error is acceptable, because most values around the mean will be very similar so there's no point storing more of them.
However, for the 0.99th quantile the error has to be much smaller to catch the outliers.
On the other hand, the tail values are much less frequent so the algorithm will store a lot less data.

## Algorithm

The abstract data structure employed by the algorithm is a sorted list, with the following operations:

- `Insert(float64)` calculates the lowest and highest possible rank for the new value, then inserts it into the list, maintaining the list sorted.
  Each value in the list covers a range of ranks, bounded by the configured errors.
- `Query(float64) float64` traverses the list to find the value whose range of covered ranks includes the rank corresponding to the requested quantile. It then returns that value.
- `Compress()` walks through the list and removes all the values that are redundant: as more values are added, the rank intervals for the targeted
  quantiles shift and start overlapping. Compress finds these overlapping values and removes them.

The Prometheus implementation uses a small slice (500 samples) as a concrete data structure and runs `Compress` immediately after each insert.

The following table shows the algorithm at work on a dataset of 30 samples: shuffled integers from 1 to 30 inclusive.

![Targeted quantiles execution on a dataset of size 30](targeted-quantiles-execution.png)

You can find the script which generated this table [in this commit](https://github.com/topliceanu/perks/commit/cff191c15ce1991cf393d06813790a736867c61f).
To make it work, the size of the internal list used in the implementation was reduced from 500 to 10, to force `Compress` to prune data.

Notice how, as values are ingested, other values are removed, potentially from other areas of the quantile spectrum, e.g. at `Insert 24`, `2` is removed.
Often times, the new value ingested does not add any new information so it is ignored, e.g. at `Insert 7`, `Insert 1`, etc.

## Observations

The algorithm does not sample, that is to say it considers all the input values, but prunes the ones that are not relevant to the objective quantiles.

Space complexity is proportional to the number of quantiles of interest, not the size of the input!
To keep the data structure small, `Compress` has to be executed often to prune the values that are not needed.
To get the best time complexity, a Red-Black Tree can be used for fast lookups and deletes.

Two separate instances of the targeted quantile data structure with the same targets can be merged by simply
inserting the values from one into the other and running `Compress`.

## Afterthought

Interesting solutions are employed in resource-constrained environments. Tradeoffs have to be made and error levels have to be accepted to do any useful work.
There is a vast category of algorithms suitable for these situations and they prove useful outside of their original context.
Targeted quantiles have been developed originally for networking hardware but we use them all the time to monitor our Kubernetes deployments.
I encourage you to try to understand how the tools you often use are designed.

## References
1. The original paper cited in the Prometheus implementation is [Effective Computation of Biased Quantiles over Data Streams by Cormode et al.](https://www.cs.rutgers.edu/~muthu/bquant.pdf).
  It describes a generic algorithm called Biased Quantiles. It introduces High-Biased, Low-Biased and Targeted Quantiles as specializations.
  It contains a mathematical proof of correctness and an analysis of the performance characteristics.
2. A newer paper from the same research group: [Space- and Time-Efficient Deterministic Algorithms for Biased Quantiles over Data Streams](http://dimacs.rutgers.edu/~graham/pubs/papers/bq-pods.pdf).
  This presents an even more generalised algorithm which extends to answering rank queries as well as biased and targeted quantiles.
2. The implementation used in the Prometheus global client is [github.com/beorn7/perks/quantile](https://github.com/beorn7/perks/tree/master/quantile)
4. The [Prometheus documentation](https://prometheus.io/docs/practices/histograms/#errors-of-quantile-estimation) for quantile estimation.
