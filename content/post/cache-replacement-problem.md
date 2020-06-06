+++
title = "The Cache Replacement Problem"
date = "2020-04-22T11:11:00Z"
draft = false
+++

## Intro

Tradeoffs between time and space complexity often need to be made in computing.
A solution that is faster at the expense of using more storage is usually preferred.
One way to make a solution faster is to save the results of expensive operations in a cache for later use.

Since cache capacity is limited and is usually much smaller than the amount of
data the algorithm requires, caching every result is not practical.
Once the allocated memory is at capacity, the caching system needs to decide which
piece of data to remove so it can make room for new pieces of data.
This is the cache replacement problem. [1][1]

This article goes through several strategies for cache replacement.
It's accompanied by an example implementation in Golang, as well as benchmarks for speed, memory usage and cache hit rates. [2][2]

## The cache replacement problem

Given two types of memory, a fast but small one and a slow but large one,
the aim is to design a system that exposes the performance of the first and the capacity of the second.
For both memory types, data is split into addressable chunks of data, called _pages_.
The system transparently maintains a cache in the fast memory with copies of pages from the slow memory.

When the client requests a page that is in the cache - a _cache hit_, the
system will read the page from the fast memory and return it. Otherwise, in case of
a _cache miss_, the system will fetch the page from the backend slow memory, write it in the
fast memory and return it to the client. See _Figure 1.a_.

```
`client       cache        backend          client       cache        backend
--+---       --+--        ---+---          --+---       --+--        ---+---
  |            |             |               |            |             |
  |  read key  | (miss)      |               |  read key  |             |
  H----------->H             |               H----------->H             |
  H            H  read key   |               H    miss    H             |
  H            H------------>H               H<-----------H             |
  H            H    val      H               H            |             |
  H            H<------------H               H         read key         |
  H            H             |               H------------------------->H
  H    val     H (store val) |               H            |             H
  H<-----------H             |               H           val            H
  |            |             |               H<-------------------------H
                                             H            |             |
              (a)                            H  write val |             |
                                             H------------H             |
                                             H    ok      H             |
                                             H<-----------H             |
                                             |            |             |

                                                         (b)
```
_Figure 1: a. cache miss in a storage system; b. cache miss in a general system_

The storage system approach couples the cache with the backend storage.
In a general-purpose cache, the pages can come from something other than a slow disk,
for instance, they can be results of expensive computations or network calls.
In this approach, the decision to write pages to the cache is left to the client.
See _Figure 1.b_.

```
Read(key int) (value int, isCacheMiss bool)
Write(key, value int)
```
_Listing 1: general purpose cache interface_

In the following sections, this document goes through several cache page replacement strategies.

## LRU - Least recently used

The observation at the base of LRU is that whatever page was requested
recently has the highest chance to be requested again soon - the data exhibits
_locality of reference_. Conversely, the data in the cache that hasn't been
requested for the longest time, has the least chance of being requested again shortly.
This is the data that LRU evicts to make room for new pages.

Cache performance depends on the use-case, but, in practice, LRU works well enough
in many situations as well as being very fast and easy to implement.

It is implemented with a double-linked list and a hash map.
The hash map gives constant lookup times for data keys, whereas the list maintains
the invariant that the nodes that were requested recently are at the head of the list.
Discarding old node as well as promoting recent nodes is as easy as updating a few
pointers in constant time.

```
+------+---------------+-----------+------------------------------------------------------+
| step | state (list)  | operation | effect                                               |
+------+---------------+-----------+------------------------------------------------------+
| 1    | ()->()->()    | write 3   | add 3 to the empty cache                             |
| 2    | (3)->()->()   | write 2   | add 2 before 3, capacity not reached                 |
| 3    | (2)->(3)->()  | write 1   | add 1 before 2, capacity not reached                 |
| 4    | (1)->(2)->(3) | write 4   | add 4 before 1 and evict 3 since the cache overflowed|
| 5    | (4)->(1)->(2) | write 5   | add 5 before 4, evict 2 since its the LRU node       |
| 6    | (5)->(4)->(1) | read 1    | read 1 bumps it to the front of the list, the MRU    |
| 7    | (1)->(5)->(4) |           |                                                      |
+------+---------------+-----------+------------------------------------------------------+
```
_Table 1: an example of operations and their effect of the LRU cache_

## MRU - Most recently used

In the case of repeatedly scanning large pieces of data or accessing random
pages from a very large memory, LRU does not perform very well.
It has been proven - see [8][8] - that evicting the most recently used page has better
cache hit rates in this case.

The implementation is very similar to LRU: the most recently used key is at the head of the list
and the least recently used key is at the end. The difference is that in MRU, the key that is
read last - the head of the linked list - is also the key that is evicted before the next write.

## LFU - Least frequently used

The intuition for LFU is to keep in the cache the keys that have been most frequently accessed.
The strategy will evict the page that has been requested the fewest times out of all the pages in the cache.

In practice, maintaining the complete history of key accesses is not possible, so
most implementations use an approximate LFU (ALFU) where the access history is
retained for a limited time window.

Much like LRU, this implementation also uses a hash map for fast access to a given key.
Unlike LRU, LFU needs to maintain a set of all the keys in the cache sorted by the frequency of access.
A double-linked list would not work because the list needs to be kept sorted,
resulting in O(n) complexity in every operation.

Since the algorithm only requires access to the least frequently read page and
doesn't need the rest of the pages to be sorted, a min-heap data structure is a good candidate.
Writing, reading and promoting keys in a heap are all done in O(logn) time with no
extra memory - heaps are implemented as arrays.

In general, when choosing a data structure for an algorithm, the goal is to find
the structure that exposes no more functionality than what is needed.
The more extra functionality a data structure has, the more
expensive its operations are going to be.

To keep things simple, the implementation in the accompanying repository [2][2] only
takes into account the number of hits, not their frequency, or the last time they were accessed. See [12][12].
This is not efficient, since a pathological worst case can easily be thought of: a
key that was requested many times in just one day more than a year ago is likely to be in the cache even if it hasn't been requested since.

```
+------+---------------------+-----------+--------------------------------------------------------------+
| step | state (key, freq)   | operation | effect                                                       |
+------+---------------------+-----------+--------------------------------------------------------------+
| 1    | ()->()->()          | write 3   | add 3 to the empty cache                                     |
| 2    | (3,1)->()->()       | write 2   | add 2 before 3, capacity not reached                         |
| 3    | (2,1)->(3,1)->()    | write 1   | add 1 before 2, capacity not reached                         |
| 4    | (1,1)->(2,1)->(3,1) | read 2    | read 2 bumps its access count to 2, move to back of the heap |
| 5    | (1,1)->(3,1)->(2,2) | read 1    | read 1 bumps its access count to 2, move to back of the heap |
| 6    | (3,1)->(2,2)->(1,2) | write 5   | write 5, evicts 3 because its lowest access count            |
| 7    | (1,2)->(2,2)->(5,1) |           |                                                              |
+------+---------------------+-----------+--------------------------------------------------------------+
```
_Table 2: an example of operations and their effect of the LFU cache_

## Scan resistance

One of the main disadvantages of LRU is that it is not scan-resistant.
To understand this property, consider an LRU cache with a capacity of n pages.
Over time, the data in the cache will implicitly capture the key access frequency:
more popular keys will be near the front of the linked list, the less popular
ones to the back.

Consider the case when a client writes a sequence of n all-new pages to the cache.
All the existing values in the cache will be removed and replaced with the recent writes.
The implicit key access frequency information is lost.

For a concrete example, in a relational database where table scans are common,
the database cache must be resistant to scans to perform well.
Reference [11][11] is a blog post about how MySQL uses a modified LRU cache to make it scan resistant.

## SLRU

This cache splits its allocated memory into two LRU segments: probation and protected.

- When a new piece of data is written to the cache, it is first stored in the probation section.
- When a key is read from the cache, it is moved to the head of the protected
segment, irrespective of whether it was previously located in the protected or the probation sections.
- When an overflow occurs on the probation segment, the evicted key
is dumped completely from the cache.
- When an overflow occurs on the protected segment, the evicted key is moved to the probation segment,
giving it another chance to be promoted back to the protected section with another read in the future.

```
      #     |    Protected LRU                  Probation LRU    |  Operations
------------+----------------------------------------------------+----------------------------------------
     1.     |     -----------                   -------------    | d is evicted from the Protected
  eviction  |      |a|b|c|d|                     | |x|y|z|t|     | section and it is added into the
  from      |     --------|--                   --^----------    | head of the Probation section.
  Probation |             |                       |              |
            |             +-----------------------+              |
------------+----------------------------------------------------+-----------------------------------------
     2.     |     -----------                   -------------    | z is read from the Probation section.
 hit in     |      | |a|b|c|                     | |x|y|z|t|     | It is moved to the head of Protected.
 Probation  |     --^-----|--                   --^-----|----    | section. This triggers c to be evicted
            |       |     +-----------------------+     |        | and moved to the head of Probation.
            |       +-----------------------------------+        |
------------+----------------------------------------------------+-----------------------------------------
     3.     |     -----------                   -------------    | c is read from the Protected section.
 hit in     |      | |a|b|c|                     | | | | | |     | It is moved to the head of the
 Protected  |     --^-----|--                   -------------    | Protected section.
            |       |     |                                      |
            |       +-----+                                      |
------------+----------------------------------------------------+-----------------------------------------
```
_Table 3: data movement in SLRU under various conditions_

SLRU is scan resistant. In the event of a scan, it's only the probation section that is flushed.
Keys need to be requested at least two times to be promoted in the protected section.
So the protected section can now maintain the implicit frequency information.

The ratio between the sizes of the protected and probation sections is also a tunable parameter.

## LFRU - Least Frequent Recently Used

Resistance to a single scan proves very useful in the general case, but for databases,
where table scans are the norm, if two table scans happen one after the other then
the same problem occurs.

A variation of SLRU is LFRU, or Least Frequent Recently Used.
It also splits the allocated memory into two sections, this time called privileged (LRU) and unprivileged (LFU).
The aim is to promote to the privileged section only the pages that have a high rate of requests, thus filtering out locally popular pages.

When a cache miss occurs, the client will write the data page in the cache. It will be
stored in the unprivileged section - a max heap sorted by frequency of access -
at the back of the heap. Popular items are promoted from
the unprivileged section into the LRU privileged section.

## ARC - Adaptive replacement cache

Much like SLRU in the previous section, the idea with ARC is to improve on LRU.
Arc outperforms LRU by automatically adapting to the changing input data.
If the input follows a normal distribution, ARC will increase the capacity of the
frequency-optimized LRU segment. If the input tends toward a uniform distribution,
ARC allocated more of the available memory to the recency optimizes LRU segment
which performs better under these circumstances.

```
    . . . [   b1  <-[     t1    <-!->      t2   ]->  b2   ] . . .
          [ . . .  l1 . . . . . . ! . .^. . . . l2  . . . ]
```
_Figure 2. ARC data structure_

ARC splits the memory into 2 sections L1 and L2, each further split into two sections T1, B1, T2 and B2:
- T1 holds items that have been requested only once
- T2 hold items that were requested at least twice, much like SLRU
- Whenever a page is evicted from T1 it is recorded in B1.
- Likewise, evictions from T2 are added to B2.

B1 and B2 are not part of the cache, they only hold metadata of the evicted pages.
The ratio of evictions into B1 and B2 determines the sizes of T1 and T2.
When more pages are evicted from T1 than T2, the cache will rebalance to give more memory to T1.

ARC and variants of it are widely used in the industry, most notably ZFS,
Postgresql and VMWare vSAN.

## Benchmarks

The performance indicators of the cache are the speed of reads and writes,
the extra memory used to store the data and the cache hit rate
(number of hits / total number of requests).

Inspired by [3][3], the accompanying implementation [2][2] contains read/write benchmarks
for all algorithms described above. _Listing 1_ contains a set of benchmark results.

```
$ ./script/benchmark
goos: linux
goarch: amd64
pkg: github.com/topliceanu/cache/benchmark
BenchmarkCache/cache-lru/Write()-4       3983329     293.0 ns/op     32 B/op     1 allocs/op
BenchmarkCache/cache-lru/Read()-4       38942666      30.9 ns/op      0 B/op     0 allocs/op
BenchmarkCache/cache-lfu/Write()-4       5492858     229.0 ns/op     31 B/op     0 allocs/op
BenchmarkCache/cache-lfu/Read()-4       36854689      30.5 ns/op      0 B/op     0 allocs/op
BenchmarkCache/cache-mru/Write()-4       5892952     217.0 ns/op     31 B/op     0 allocs/op
BenchmarkCache/cache-mru/Read()-4      174675004       6.9 ns/op      0 B/op     0 allocs/op
BenchmarkCache/cache-slru/Write()-4      3704128     339.0 ns/op     32 B/op     1 allocs/op
BenchmarkCache/cache-slru/Read()-4      16276162      69.6 ns/op      0 B/op     0 allocs/op
BenchmarkCache/cache-lfru/Write()-4      3918639     316.0 ns/op     32 B/op     1 allocs/op
BenchmarkCache/cache-lfru/Read()-4      16141981      65.3 ns/op      0 B/op     0 allocs/op
BenchmarkCache/cache-arc/Write()-4       1901154     634.0 ns/op     65 B/op     2 allocs/op
BenchmarkCache/cache-arc/Read()-4       12199518      88.9 ns/op      0 B/op     0 allocs/op
PASS
ok      github.com/topliceanu/cache/benchmark   19.684s
```
_Listing 1: Read/Write benchmarks for the cache implementations_

As expected the more complex caches take more time and more memory.

The cache hit rate is application-specific.
Picking the appropriate cache replacement strategy depends on the access distribution
of data in each application. The accompanying project to this blog post has a tool
that generates random data - 1M integers, 10k cardinality - and calculates hit
and miss rates for each cache algorithm described above where cache size is configured to 1000.

The results are not useful because the randomly generated data is not similar to
typical production workloads.

```
$ go run cmd/hit-rate/main.go
Cache type    Hit rate   Miss rate
 cache-lru    9.990      90.010
 cache-lfu    9.997      90.003
 cache-mru    9.993      90.007
cache-slru    9.934      90.066
cache-lfru    9.992      90.008
 cache-arc    9.941      90.059
```

## Conclusion

The perfect cache solution was described by Belady in 1960 and states that the
best value to discard is the one that you know you are going to need furthest
in the future. While intuitive, it is not possible to implement it. In general,
we cannot know when a piece of data will be requested in the future.
Belady's contribution, however, is to produce a formal proof that this indeed the
optimal caching algorithm. Its purpose is to act as the ideal benchmark for
comparison for other implementations.

When designing your cache implementation, you want to take into consideration the
historical data access patterns for your specific use-case, if the extra effort
to design and implement it is reasonable.

## Endnotes

Thank you for getting this far. I hope you learned something new.
I plan to explore ARC some more and come back with a comprehensive description.

Please leave comments on [Hacker News](), on [Lobste.rs]() or on [Reddit]().

The source for this post is on [github.com/topliceanu/alexandrutopliceanu.ro](https://github.com/topliceanu/alexandrutopliceanu.ro),
If you open an issue or a PR to make improvements, I would very much appreciate it!

## Resources

1. [link](https://en.wikipedia.org/wiki/Cache_replacement_policies) "This Wikipedia page describes a large list of cache replacement strategies. It's beautiful!"
2. [link](https://github.com/topliceanu/cache) "My Golang implementation for the cache data structures described above"
3. [link](https://github.com/Xeoncross/go-cache-benchmark) "For production use, David Pennington made a benchmark to compare different Golang cache implementations"
4. [link](https://youtu.be/Dh7vmvk9huM) "Professor Tim Roughgarden, in his popular MOOC 'Introduction to Algorithms, Part 2', has a section where he introduces the caching problem and Belady's ideal cache algorithm."
5. [link](https://arxiv.org/pdf/1702.04078.pdf) "LFRU paper"
6. [link](https://lrita.github.io/images/posts/datastructure/ARC.pdf) "Not the original ARC paper but a simplified version written by the same authors"
7. [link](https://en.wikipedia.org/wiki/Adaptive_replacement_cache) "ARC Wikipedia page is very good if you want a TL;DR"
8. [link](http://code.activestate.com/recipes/576532-adaptive-replacement-cache-in-python/) "ARC implementation in python"
9. [link](http://www.vldb.org/conf/1985/P127.PDF) "MRU paper with experimental data of when it performs better than LRU"
10. [link](https://pdfs.semanticscholar.org/eacf/df93e03d9dbbbaa2d01250939d9f94fb16a4.pdf) "Belady's MIN optimal cache paper"
11. [link](https://medium.com/@often_weird/what-makes-mysql-lru-cache-scan-resistant-a73364f286d7) "Blog post about the techniques used in MySQL to make the cache scan resistant"
12. [link](https://github.com/patrickmn/go-cache) "A popular in-memory cache implementation for Golang"

[1]: https://en.wikipedia.org/wiki/Cache_replacement_policies "This Wikipedia page describes a large list of cache replacement strategies. It's beautiful!"
[2]: https://github.com/topliceanu/cache "My Golang implementation for the cache data structures described above"
[3]: https://github.com/Xeoncross/go-cache-benchmark "For production use, David Pennington made a benchmark to compare different Golang cache implementations"
[4]: https://youtu.be/Dh7vmvk9huM "Professor Tim Roughgarden, in his popular MOOC 'Introduction to Algorithms, Part 2', has a section where he introduces the caching problem and Belady's ideal cache algorithm."
[5]: https://arxiv.org/pdf/1702.04078.pdf "LFRU paper"
[6]: https://lrita.github.io/images/posts/datastructure/ARC.pdf "Not the original ARC paper but a simplified version written by the same authors"
[7]: https://en.wikipedia.org/wiki/Adaptive_replacement_cache "ARC Wikipedia page is very good if you want a TL;DR"
[8]: http://code.activestate.com/recipes/576532-adaptive-replacement-cache-in-python/ "ARC implementation in python"
[9]: http://www.vldb.org/conf/1985/P127.PDF "MRU paper with experimental data of when it performs better than LRU"
[10]: https://pdfs.semanticscholar.org/eacf/df93e03d9dbbbaa2d01250939d9f94fb16a4.pdf "Belady's MIN optimal cache paper"
[11]: https://medium.com/@often_weird/what-makes-mysql-lru-cache-scan-resistant-a73364f286d7 "Blog post about the techniques used in MySQL to make the cache scan resistant"
[12]: https://github.com/patrickmn/go-cache "A popular in-memory cache implementation for Golang"
