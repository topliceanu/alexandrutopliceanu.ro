+++
date = "2017-02-11T15:16:45Z"
title = "quality go code"
draft = true

+++

# Quality Golang Code
_The tools I use to help produce quality Golang code_

## Abstract

Go has excellent libraries for source-code parsing. These have enabled the creators of Go and the open source community to produce a variety of tools which help eliminate errors in advance.

The large number of tools and the lack of documentation on how to best use them presents a problem for engineers.
This blog post describes the process and the tools I use to improve code quality and catch bugs early in my Go code.
I will go through linting, testing, code coverage, benchmarking, race detection in concurrent code, memory, CPU and contention profiling.

## Documentation

An HTML version can be generated dynamically from a package's source code.
Running `godoc -http=:8080` will start a static HTTP server on `0.0.0.0:8080` which will generate on the fly and serve the documentation for all standard library packages as well as all the packages `$GOPATH`.
Go to `http://0.0.0.0:8080/pkg/github.com/your/package` to see the live docs of your package as you are developing it. Make sure you document all your exported members.

## Linting

Code linting is a static analysis technique meant to prevent programmers from doing mistakes commonly seen in a specific language.

A popular project in Go is [go-metalinter](https://github.com/alecthomas/gometalinter). I found it to be too broad. Instead, I use it as a comprehensive list of "best practice" tools from which I pick only what I need, depending on the project.
In particular, I use `go fmt` because it is the standard way to format source code.
I've given up on `goimport` (which also runs `go fmt`) because I found the rules to be simple enough to enforce: split standard libraries from everything else with an empty line in the `import` statement, then sort the two batches lexicographically.

I usually use [glide](https://github.com/Masterminds/glide) to manage the `/vendor` folder in a project. With _glide_, you can run `go fmt $(glide novendor)` to format all source files except for the ones in `/vendor`.

`go vet` is another helpful tool detect "common" Golang mistakes. It works by running a [set of heuristics](https://golang.org/cmd/vet/) against the source code and reporting the results. Note that it might return false positives, in the end, it's up to you to decide what is important or not.
`govet` expects Go package names as parameters so, to run it on all your project except for vendored dependencies, use `go vet $(go list ./... | grep -v /vendor/)`.

[golint](https://github.com/golang/lint) detects and reports coding style mistakes, it does not rewrite the code as `go fmt` does. It is used internally by Google and it is a good base for your company's internal Go style guide. Use `go list ./... | grep -v /vendor/ | xargs -L1 golint` to skip the vendored dependencies.

The Go compiler is very diligent to panic when you import a package you don't use or when you define a variable you don't use, but it doesn't complain when you forget to handle the error returned by a function. For that, I use [errcheck]((https://github.com/kisielk/errcheck) and I find it invaluable.

## Testing

Much ink has been spilled on how to test code and, in particular, Go code. I am not going to go into details here, but do check out the excellent [testing package docs](https://godoc.org/testing).

When developing a service from scratch, I usually start with acceptance tests. It's important to get them right because they help define the API and are going to be used for the whole lifetime of the project.
When the API protocol matures, I move down to integration and unit tests, often accompanied by redesigns and rewrites of the implementation.

To ensure that tests only run against the public API of a module, I group tests in a `<module>_test` package which has the added benefit of helping define a testable API, enforces dependency injection, component orthogonality, and single responsibility.

I find testing to be hard! It requires design and maintenance and should not be considered second-class citizen to production code. It usually takes more time to write tests and significantly more code, but I consider this to be the norm and a mark of craftsmanship.

To run a specific test in your suite, use `go test -run=<regexp/matching/test/func/name>`.

## Benchmarking

Go has inbuilt support for micro-benchmarks. These are similar to unit tests, that is benchmarks measure the performance (time and memory allocations) of individual functions.
The way this works is that the body of the benchmark is executed enough times to get a statistically relevant measurement of its duration. One word of warning, different runs of the same benchmark function might yield significantly different results if run inside VMs or containers, especially on laptops which perform various power saving and cooling functions. See this [blog post](http://thornydev.blogspot.co.uk/2015/07/an-exercise-in-profiling-go-program.html) on the performance gains attainable.

The Go benchmark framework is part of the [testing](https://godoc.org/testing) package. All benchmarks are executed sequentially, but you can run them in parallel with the `RunParallel` helper function. This will create multiple goroutines and equally distribute the benchmark iterations amongst them. It's also very effective at detecting race conditions and measuring lock contention.

For some reason, tests are executed by default when running benchmarks so, to ignore the tests, run `go test -run=^$ -bench=.`.

## Race Detection

[Race detection](https://golang.org/doc/articles/race_detector.html) is integrated into the Go compiler and is available for `go test -race`, `go run -race`, `go build -race` and `go install -race`.

It works by instrumenting every memory access such that when two goroutines read from/write to the same memory address, the program panics. Because of this design, data races can only be detected at runtime and only on code paths that are executed. This [document](https://github.com/google/sanitizers/wiki/ThreadSanitizerAlgorithm) describes how the instrumentation algorithm works in detail.

The best way to detect data races is under realistic production conditions but this approach has a significant performance penalty. Running one instrumented binary in parallel with other non-instrumented binaries in a load-balanced set is a useful approach, especially for alpha stage services.

Other ways to detect races are:
- running parallel benchmarks with the `-race` flag can catch races with the right test cases.
- running parallel tests. Go doesn't offer inbuilt support for parallel tests, so you will have to write the framework to do that yourself. In [this example](https://github.com/bradfitz/talk-yapc-asia-2015/blob/master/talk.md#race-detector) by Brad Fitzpatrick, multiple goroutines perform the same action under test and a data race is detected.
- another very good alternative is to run load tests: produce a high volume of requests against your race instrumented binary running in a staging or testing environment. For HTTP services I prefer to use  [vegeta](http://github.com/tsenart/vegeta) to perform load testing.

Typical race conditions are accidentally shared variables, global variables accessed from multiple goroutines, etc. See this documentation article on [tipical data race situations](https://golang.org/doc/articles/race_detector.html#Typical_Data_Races). Fixing these cases requires the use of synchronization primitives, such as those available in the `sync` packages or channels to pass control to memory spaces.

One thing to note is that because of Go's memory model, not even read/writes on primitive data types are *not* atomic. The `sync/atomic` package has operations to perform atomic reads, atomic writes and atomic “compare and swaps” on ints and pointers.

## Profiling

Profiling is also built-in with the Go tools. All types of profilers work in a similar way. An instrumented binary will spawn a separate thread which will send a signal to the main thread at a set interval. That signal will prompt the main thread to respond with data depending on the type of profiling done. The profile thread collects all this data and produces a profile report in binary format, essentially a collection of [protobuf objects](https://developers.google.com/protocol-buffers/), which you can save to disk for analysis using the `pprof` tool.

All profilers are based on sampling, that is they collect data every set period of time, then aggregate it:
- CPU profiling is useful for detecting slow running functions. It works by collecting stack traces of all currently running goroutines at a high frequency, then cumulating the times spent in each function on the stack. Very fast or infrequently called functions are discarded.
- Memory profiling is useful to detect functions which allocate relatively large chunks memory.  It works by collecting heap dumps from each running goroutine at high frequency and diffing sequential heap snapshots to count allocations. High memory consumption negatively affects performance because it means Go's "stop-the-world" garbage collector has more work to do.
- Block profiling is used to detect lock contention between multiple goroutines and is done by recording when and where each goroutine is blocking.

There are multiple ways to produce profiles.

### Compiling an instrumented binary

For CPU profiling, you need to use the [runtime/pprof](https://godoc.org/runtime/pprof) package. Here's an example of how you might instrument your `func main()`:

```go
fp = os.Create(profilePath)
defer fp.Close()
pprof.StartCPUProfile(fp) // start collecting data.
defer pprof.StopCPUProfile() // when the process stops, stop the profiler and store the data.
```

For memory profiling, you need the [runtime](https://godoc.org/runtime) and [runtime/pprof](https://godoc.org/runtime/pprof) packages.

```go
fp = os.Create(profilePath)
defer fp.Close()
runtime.GC() // trigger a run of the GC to get a clean heap snapshot.
defer pprof.WriteHeapProfile(fp) // when the process stops, stop the profiler and store the data.
```

For block profiling, you must use the [runtime](https://godoc.org/runtime) package. See [this GitHub issue](https://github.com/golang/go/issues/14689) on how to build a block profile.

```go
fp = os.Create(profilePath)
defer fp.Close()
runtime.SetBlockProfileRate(1) // catch every single block event.
profile = pprof.Lookup("block") // fetch the block profile singleton.
defer profile.WriteTo(fp) // write the profile data before stopping the process.
```

A couple of observations: first, errors are not being handled in the code above for simplicity reasons, you should definitely do so in your own code; second, the defer statements might not execute, depending on how your program stops, this will lead to the profile information not being transferred from memory to disk.

### Instrument tests and benchmarks

`go test` allows you to pass `-cpuprofile=<path/to/store/profile>`, `-memprofile=<path/to/store/profile>` or `-blockprofile=<path/to/store/profile>` params. These options will build a test or benchmark binary instrumented for the specific profiler, run it and store the profiler report in the specified path at the end of the tests.
This method has the disadvantage that the profile report will contain data on the testing infrastructure which might have significant overhead.

### Instrument HTTP servers

For HTTP services, the `net/http/pprof` package can be imported to produce profiles on demand. It works by registering a `/debug/pprof` path on the default `net/http` handler (you can also add it to custom HTTP handlers) which lists all the profiles it can produce.

You may want to protect this URL with an authentication mechanism, profiling will significantly decrease the performance of your service and could potentially be used in a DOS attack.
When a specific profile path is requested, say `/debug/pprof/profile`, the package starts profiling and writes the output on the HTTP stream to the client.
The `pprof` tool can be used to consume the profile stream from an URL directly, but you can also download the profile locally.

### How to read a profile

The main way to use the profile data is with the built-in `pprof` tool. This is based on the [google/pprof](https://github.com/google/pprof) project and is now bundled into the Go binary:

```bash
go tool pprof [<path/to/binary>] <path/to/profile>
pprof> ...
```

This command will start a `pprof` session, which loads up all the profile data and exposes several useful commands:
- `top <N> -cum` lists the top N functions, sorted such that the top listed function consumes the most CPU or memory or has the longest lock times, depending on profile under inspection.
- `list <function>` lists the source code of a function and the lines that are the biggest contributors to resource consumption. You can specify a package name as a prefix to further filter the results. This command needs the binary file to be passed to the `pprof` tool in order to produce source code listings.
- `web` opens a browser window containing an SVG image of the execution graph for the profiled program and the time spent or memory consumed in each call. Note that the graph is pruned, only the top offenders are displayed!
Usually, you start with `top` to find suspicious functions then dig deeper with `list`. [This](https://github.com/bradfitz/talk-yapc-asia-2015/blob/master/talk.md#cpu-profiling) is an example of how the output of these commands looks like.

When analyzing a memory profile with `pprof`, make sure to add the `-alloc_space` flag which displays allocated memory sizes, it will make `list` better.

For CPU profiles, a helpful tool I use is [go-torch](https://github.com/uber/go-torch). It works by generating a flame graph, using [brendangregg/FlameGraph](https://github.com/brendangregg/FlameGraph) from a profile binary. To produce a flame graph SVG run `go-torch <binary> <profile>`, then open it in a browser window.

## Conclusion

Discovering these tools, understanding how they work, how to configure and use them is hard work! Once you have them in place, you still don't get a free lunch, often times you need to understand the design decisions in the language implementation, the standard library, or in the third party libraries you are using. The standard library, in particular, has a lot of helper functions which boost productivity but are seldom efficient compared to their low-level counterparts.
That being said, the level of insight you can get into Go programs with just the built-in tools is impressive and the ecosystem around the language nicely complements its native capabilities.

## Resources
1. Brad Fitzpatrick's YAPC 2015 talk "Profiling and Optimizing Go" [youtube.com](https://www.youtube.com/watch?v=xxDZuPEgbBU), [slides](https://docs.google.com/presentation/d/1lL7Wlh9GBtTSieqHGJ5AUd1XVYR48UPhEloVem-79mA/view#slide=id.p) and [writeup](https://github.com/bradfitz/talk-yapc-asia-2015/blob/master/talk.md)
2. Francisc Campoy's "Go tooling in Action" [youtube.com](https://www.youtube.com/watch?v=uBjoTxosSys)
3. Michael Peterson's "An Exercise in Profiling a Go Program" [link](http://thornydev.blogspot.co.uk/2015/07/an-exercise-in-profiling-go-program.html)
4. Not updated but still good, Golang's blog post "Profiling Go Programs" [link](https://blog.golang.org/profiling-go-programs)
