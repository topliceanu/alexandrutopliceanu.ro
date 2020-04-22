+++
title = "Cache Data Structures"
date = "2020-04-22T11:11:00Z"
draft = true
+++

## Intro

Often in computing we make tradeoffs between time complexity and space complexity.
Since ephemeral and persistent storage are cheap and plentiful, a solution that
is faster at the expense of using more memory and more storage is usually preferred.
One way to trade space for faster execution times is by caching already computed results.

This article goes through several strategies for cache replacement.
It's accompanied by example implementations in golang with benchmarks for speed,
memory usage and cache miss rates.

## The caching problem

We're given two different memory types: a very fast but small memory and a large but much slower one.
A cache processes a sequences of _page requests_: the client requests data - _pages_ -
from the cache. Ideally the cache would serve these requests from the fast memory.
When the data is not already in the cache - what's called a _cache miss_ - the cache
needs to bring it in from the slow memory. The problem then is which page from
the fast memory do you evict in order to make room for the newly promoted page?

*IMAGE WITH HOW CACHE MISSES WORK?!?!*

One thing to note is that the data is guaranteed to be in the large slow memory,
this is somewhat outside the cache context.

The cache replacement problem is the problem of optimally choosing which values
to cache and how to discard values from the cache that are not used anymore to
make room for new values.

## LRU - Least recently used

The observation at the base of LRU is that whatever piece of data was requested
recently has the highest chance to be requested again in the near future. We say that the data exibits
_locallity of reference_. Conversely, the data in the cache that hasn't been
requested for the longest time, has the least chance of being requested again the near future.
This is the data that LRU evicts to make room for new pages.

Obviously this depends on the use-case, but, in practice, LRU works well enough
in many situations.

It is implemented with a linked list and a hash map. The hash map give constant lookup
times for data keys, whereas the linked list maintains the invariant that the nodes
are sorted by how recent they were last used. Discarding the last used node as well
as promoting recently accessed keys is as easy as updating a few pointer in constanst time.

*IMAGE WITH HOW LRU DOES EVICTION WORKS*

## MRU - Most recently used

While LRU is intuitive why it would work in most cases, when repeatedy scanning
large pieces of data or accessing random pages in a large memory access patterns happen,
evicting the most recent accessed key first, has been proven to work better than LRU.

The implementation is similar to LRU, except that the double linked list is sorted descendingly,
with the least recenly used page as the head and the most recently used page as the last node.

*IMAGE WITH HOW MRU DOES EVICTION WORKS*

## LFU - Least frequently used

The intuition for LFU is to evict the page that has been requested the fewest
times out of all the pages in the cache.

In order to implement this, we will keep the hash map for constant time access to a key,
but we can't use the double-linked list anymore. We would have to keep the list sorted
by the number of access requests to each node. For a linked list, that is O(n), where
n is the lenght of the list. This is too slow for a cache.

Other options to maintain the sorted list of pages are to use a sorted array,
a binary ballanced search tree or a heap. The heap is an interesting option: it
is implemented with an array, unlike the ballanced search tree, the extra data needed to
support the structure is 0, unlike the sorted array, we don't actually need to keep
all the pages in their right place, we are only interested in the least frequently used page,
that page has to be fast to remove. Not much else is required from our choice of data structure.

In general when picking a data structure, you want something that implements the
least amount of extra functionality that you don't need, ideally 0, because you
are going to pay the price for that in the functionality you do need.

The heap is sorted by the access frequency of the data page. When a page is read from
the hashmap, the index in the heap is retrieved, the frequency is updated and the node is
bubble up in the heap data structure for a time complexity of O(logn).
That is similar to the sorted array or the tree, but in general it will be faster than them,
but not as fast as LRU.

Note that the price is high, all reads and writes are not O(logn) so the effectiveness
of this cache depends a lot on how slow the main memory is and

*IMAGE WITH HOW LFU DOES EVICTION WORKS*

## SLRU - Segmented LRU

This cache data is split into two segments: probation and protected.
Both the probation and protected segments are LRU caches.
When promoting a page to the cache, it is first stored in the probation section of the cache.
For subsequent read of a key in the cache, it is moved in from the probation segment into the protected segment.
When overflow occurs on the probation segment, the least recently used key
is removed completely from the cache. When overflow occurs on the protected
segment, the least recently used key is moved to the probation segment.

*IMAGE WITH HOW LFU DOES EVICTION WORKS*

A variation of this eviction strategy is called Least Frequent Recently Used
which combines a LRU cache for the priviledged section and a LFU for the
unpriviledged section. This strategy is used in CDNs.

## ARC - Adaptive replacement cache

The idea is to optimize between a LRU and a LFU depending on the
distribution of input data. Ie. when clients require frequent access to the
same data, the LFU cache is favored because it is more efficient (in terms
of higher cache hit rates), otherwise LRU is prefered bacause it offers
optimal performance in average case.

Schema:
    . . . [   b1  <-[     t1    <-!->      t2   ]->  b2   ] . . .
          [ . . . . [ . . . . . . ! . .^. . . . ] . . . . ]
                    [   fixed cache size (c)    ]

Data is split in tow lists: t1 (a LRU cache) and t2 (a LFU cache).
Originally t1 and t2 have equal size.
Evicted keys from t1 move into b1 (a LRU cache) with the same size.
Evicted keys from t2 move to b2 (a LFU cache) with the same size.
b1 and b2 are called ghosts of t1 and, respectively, t2 and only contain
keys, not the actual data.

*IMAGE WITH HOW LFU DOES EVICTION WORKS*

## Benchmarks

## Conclusion

The perfect cache solution was described by Belady in 1960 and states that the
best value to discard is the one that you know you are going to need futhest
in the future. While intuitive, Belady's contribution is to produce a formal prof
that this indeed the optimal caching algorithm.
Obviously, it is not possible to implement it. In general, we cannot know when a
piece of data will be requested. All we have is the historical access patterns.

It's purpose is to act as the ideal benchmark for comparison for other implementations.
When designing your cache implementation, you want to take into consideration the
historical data access patterns for your specific use-case, if the extra effort
to design and implement it is reasonable.

## End notes

Thank you for getting this far. I hope you learned something new.

Please leave comments on [Hacker News](), on [Lobste.rs]() or on [Reddit]().
The source for this blog is on [github.com/topliceanu/alexandrutopliceanu.ro](https://github.com/topliceanu/alexandrutopliceanu.ro),
I you open an issue or a PR to make improvements, I would very much appreciate it!

## Resources

- This Wikipedia page describes a large list of cache replacement strategies. It's beautiful! [link](https://en.wikipedia.org/wiki/Cache_replacement_policies)
- My Golang implementation for the cache data structures described above [link](https://github.com/topliceanu/cache)
- For production use, David Pennington made a benchmark to compare different golang cache implementations [link](https://github.com/Xeoncross/go-cache-benchmark)
- Professor Tim Roughgarden, in his popular MOOC "Introduction to Algorithms, Part 2", has a section where he introduces the caching problem and Belady's ideal cache algorithm. [youtube.com](https://youtu.be/Dh7vmvk9huM)
- ARC paper [link](https://www.ipvs.uni-stuttgart.de/export/sites/default/ipvs/abteilungen/as/lehre/lehrveranstaltungen/vorlesungen/WS1415/material/ARC.pdf)
