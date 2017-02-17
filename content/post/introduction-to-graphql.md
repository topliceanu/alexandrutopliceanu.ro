+++
date = "2017-02-17T23:17:08Z"
title = "[talk] introduction to graphql"
draft = false

+++

# Introduction to GraphQL

- short introductory talk on GraphQL I gave at Pusher Ltd. (where I also work)
- here are my slide notes
  * Motivation
    - I built an API for a personal project => [wrote a blog post (Graphql + Golang + SQL)](/post/graphql-with-go-and-postgresql/) => internal brainstorming session => this presentation!
  * It's an IDL, Interface Description/Definition Language.
    - you define a schema containing data type and actions on those data types.
    - app level protocol (processes on different platforms talking to each other)
    - think Swagger, Thrift, Protobuf, etc.
    - optimizes on the number of network requests and the size of these requests
  * Why the name GraphQL?
    - it models data as a graph: types of vertices, edges are modeled as attributes.
      - flexible, few constraints, but more work for the API designer.
    - querying is equivalent to graph traversal
  * Example: a blog post page
    - why this and not a todo list? because it's common but not _that_ trivial.
    - vertex types: user, post, comments
    - disadvantages of using (pure) REST: lots of request, fetch data that is not needed, high latency
    - GraphQL querying is the same as traversal.
    - usually one POST endpoint (both query, mutation, subscription)
  * Disadvantages
    - moves complexity from the client to the server. I would argue that the client is not substantially simpler after all.
    - how do you translate to your storage device?
      - graph storage is an option but not efficient.
    - it's not seeing adoption.

{{<youtube id="CbxR6LC_o0M" autoplay="true">}}
