+++
date = "2017-01-05T21:25:28Z"
title = "graphql with go and postgresql"
draft = true

+++

# GraphQL In Use: Building a Blogging Engine API with Golang and PostgreSQL

## Abstract

GraphQL appears hard to use in production: the graph interface is flexible in it's modeling capabilities but is a poor match for relational storage, both in terms of implementation and performance.
In this document, we will design and write a simple blogging engine api, with three types of resources (users, posts and comments) and a varied set of functionality (create a user, create a post, add a comment to a post, follow posts and comments from another user, etc.), use PostgreSQL as the backing datastore (chosen because it's a popular relational DB) and write the API implementation in golang (a popular language for writing APIs).
We will compare a simple GraphQL implementation with a pure REST alternative in terms of implementation complexity, efficiency for rendering a common scenario page of the blog.

## Introduction

GraphQL is an IDL (Interface Definition Language), designers define types and model data as a graph, each node is an instance of a data type, while edges represent relationships between nodes. This approach if flexible and can accomodate any business domain. However, the problem is the design process is more involved and traditional software tools (like data stores) don't map well to the graph model.

GraphQL has been first proposed in 2014 by the Facebook Engineering Team. Although interesting and compelling in it's advantages and features, it hasn't seen mass adoption. Developers have to trade simplicity of design, familiarity and tooling of REST for the flexibility of not being limited to just CRUD and efficiency of GraphQL (it optimizes for round-trips to the server).

Most walkthroughs and tutorials on GraphQL avoid the problem of resolving queries. That is, how to design a database, using general-purpose storage solutions (like relational databases) to support efficient data retrieval to resolve the GraphQL query.

This document goes through building a blog engine GraphQL API. It is moderately complex in it's functionality. It is scoped to a familiar business domain to facilitate comparisons with a REST based approach.

The structure of this document is the following:
* in the first part we will design a GraphQL schema and explain some of features of the language that are used.
* next is the design the postgresql database in section two.
* part three covers the golang implementation of the GraphQL schema designed in part one.
* in part four we compare the task of rendering a blog post page from the perspective of fetching the needed data from the backend.

## Related
- The excellent [GraphQL introduction document](http://graphql.org/learn/).
- The complete and working code for this project is on [github.com/graphql-go-example](https://github.com/topliceanu/graphql-go-example).

## Modeling a blog engine in GraphQL

_Listing 1_ contains the entire schema for the blog engine api. It shows the data types of the vertices composing the graph. The relationships between vertices, ie. the edges, are modeled as attributes of a given type.

```graphql
type User {
  id: ID
  email: String!
  post(id: ID!): Post
  posts: [Post!]!
  follower(id: ID!): User
  followers: [User!]!
  followee(id: ID!): User
  followees: [User!]!
}

type Post {
  id: ID
  user: User!
  title: String!
  body: String!
  comment(id: ID!): Comment
  comments: [Comment!]!
}

type Comment {
  id: ID
  user: User!
  post: Post!
  title: String
  body: String!
}

type Query {
  user(id: ID!): User
}

type Mutation {
  createUser(email: String!): User
  removeUser(id: ID!): Boolean
  follow(follower: ID!, followee: ID!): Boolean
  unfollow(follower: ID!, followee: ID!): Boolean
  createPost(user: ID!, title: String!, body: String!): Post
  removePost(id: ID!): Boolean
  createComment(user: ID!, post: ID!, title: String!, body: String!): Comment
  removeComment(id: ID!): Boolean
}
```
_Listing 1_

The schema is written in the GraphQL DSL. It's used for defining custom data types, such as `User`, `Post` and `Comment`. A set of primitive data types is also provided, such as `String`, `Boolean` and `ID` (which is an alias of `String` with the additional semantics of being the unique identifier of a vertex).

`Query` and `Mutation` are optional types recognized by the parser and used in querying the graph. Reading from a GraphQL API is equivalent to traversing the graph. As such a starting vertex needs to be provided, this role is fulfilled by the `Query` type. In this case, all queries to the graph must start with a user specified by id `user(id:ID!)`. For writing data, the `Mutation` vertex is defined. This exposes a set of operations, modeled as parametrized attributes which traverse to (and return) the newly created vertex types. See _Listing 2_ for examples of how these queries might look.

Vertex attributes can be parametrized, ie. accept arguments. In the context of graph traversal, if a post vertex has multiple comment vertices, you can traverse to just one of them by specifying `comment(id: ID)`. All this is by design, the designer can choose not to provide direct paths to individual vertices.

The `!` character is a type post-fix, works for both primitive or user-defined types and has two semantics:
 * when used as the type of a parameter of an attribute, it means that parameter is required.
 * when used as a the return type of an attribute it means that attribute will not be null.
 * combinations are possible, for instance `[Comment!]!` represents a list of non-null Comment vertices, where `[]`, `[Comment]` are valid, but `null, [null], [Comment, null]` are not.

_Listing 2_ contains a list of curl commands against the blogging api which will populate the graph using mutations then query it to retrieve data.

```bash
# Mutations
curl -XPOST http://vm:8080/graphql -d 'mutation {createUser(email:"user1@x.co"){id, email}}'
curl -XPOST http://vm:8080/graphql -d 'mutation {createUser(email:"user2@x.co"){id, email}}'
curl -XPOST http://vm:8080/graphql -d 'mutation {createUser(email:"user3@x.co"){id, email}}'
curl -XPOST http://vm:8080/graphql -d 'mutation {createPost(user:1,title:"post1",body:"body1"){id}}'
curl -XPOST http://vm:8080/graphql -d 'mutation {createPost(user:1,title:"post2",body:"body2"){id}}'
curl -XPOST http://vm:8080/graphql -d 'mutation {createPost(user:2,title:"post3",body:"body3"){id}}'
curl -XPOST http://vm:8080/graphql -d 'mutation {createComment(user:2,post:1,title:"comment1",body:"comment1"){id}}'
curl -XPOST http://vm:8080/graphql -d 'mutation {createComment(user:1,post:3,title:"comment2",body:"comment2"){id}}'
curl -XPOST http://vm:8080/graphql -d 'mutation {createComment(user:3,post:3,title:"comment3",body:"comment3"){id}}'
curl -XPOST http://vm:8080/graphql -d 'mutation {follow(follower:3, followee:1)}'
curl -XPOST http://vm:8080/graphql -d 'mutation {follow(follower:3, followee:2)}'

# Queries
curl -XPOST http://vm:8080/graphql -d '{user(id:1)}'
curl -XPOST http://vm:8080/graphql -d '{user(id:2){followers{id, email}}}'
curl -XPOST http://vm:8080/graphql -d '{user(id:1){followers{id, email}}}'
curl -XPOST http://vm:8080/graphql -d '{user(id:2){follower(id:1){email}}}'
curl -XPOST http://vm:8080/graphql -d '{user(id:3){followees{id, email}}}'
curl -XPOST http://vm:8080/graphql -d '{user(id:1){followee(id:3){email}}}'
curl -XPOST http://vm:8080/graphql -d '{user(id:1){post(id:2){title,body}}}'
curl -XPOST http://vm:8080/graphql -d '{user(id:1){posts{id,title,body}}}'
curl -XPOST http://vm:8080/graphql -d '{user(id:1){post(id:2){user{id,email}}}}'
```
_Listing 2_

## Designing the PostgreSQL database

The relational database design is, as usual, driven by the need to avoid data duplication.This approach was chosen for two reasons:
 1. to show that there is no need for a specialized database technology or to learn and use new design techniques to accomodate a GraphQL API.
 2. to show that a GraphQL API can stil be created on top of existing databases, more specifically databases designed to back REST endpoints or even traditional server-side rendered html websites.

See _Appendix 1_ for a discussion on differences between relational and graph databases with respect to building a GraphQL API. _Listing 3_ shows the SQL commands to create the new database. The database schema generally matches the GraphQL schema. The `followers` relation needed to be added to support the `follow/unfollow` mutations.

```sql
CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  email VARCHAR(100) NOT NULL
);
CREATE TABLE IF NOT EXISTS posts (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title VARCHAR(200) NOT NULL,
  body TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS comments (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  post_id INTEGER NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  title VARCHAR(200) NOT NULL,
  body TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS followers (
  follower_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  followee_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  PRIMARY KEY(follower_id, followee_id)
);
```
_Listing 3_

## Golang API Implementation

The graphql parser implemented in go and used in this project is `github.com/graphql-go/graphql`. It contains a query parser, but no schema parser. This requires the programer to build the GraphQL schme in go using the constructs offered by the library. This is unlike the reference nodejs implementation, which also offers a schema parser and exposes hooks for data fetching. As such the schema in `Listing 1` is only useful as a guideline and has to be translated into golang code. However, this _"limitation"_ offers the opportunity to peer behind the levels of abstraction and see how the schema relates to the graph traversal model and to retrieving the data. _Listing 4_ shows the implementation of the `Comment` vertex type:

```go
var CommentType = graphql.NewObject(graphql.ObjectConfig{
	Name: "Comment",
	Fields: graphql.Fields{
		"id": &graphql.Field{
			Type: graphql.NewNonNull(graphql.ID),
			Resolve: func(p graphql.ResolveParams) (interface{}, error) {
				if comment, ok := p.Source.(*Comment); ok == true {
					return comment.ID, nil
				}
				return nil, nil
			},
		},
		"title": &graphql.Field{
			Type: graphql.NewNonNull(graphql.String),
			Resolve: func(p graphql.ResolveParams) (interface{}, error) {
				if comment, ok := p.Source.(*Comment); ok == true {
					return comment.Title, nil
				}
				return nil, nil
			},
		},
		"body": &graphql.Field{
			Type: graphql.NewNonNull(graphql.ID),
			Resolve: func(p graphql.ResolveParams) (interface{}, error) {
				if comment, ok := p.Source.(*Comment); ok == true {
					return comment.Body, nil
				}
				return nil, nil
			},
		},
	},
})
func init() {
	CommentType.AddFieldConfig("user", &graphql.Field{
		Type: UserType,
		Resolve: func(p graphql.ResolveParams) (interface{}, error) {
			if comment, ok := p.Source.(*Comment); ok == true {
				return GetUserByID(comment.UserID)
			}
			return nil, nil
		},
	})
	CommentType.AddFieldConfig("post", &graphql.Field{
		Type: PostType,
		Args: graphql.FieldConfigArgument{
			"id": &graphql.ArgumentConfig{
				Description: "Post ID",
				Type:        graphql.NewNonNull(graphql.ID),
			},
		},
		Resolve: func(p graphql.ResolveParams) (interface{}, error) {
			i := p.Args["id"].(string)
			id, err := strconv.Atoi(i)
			if err != nil {
				return nil, err
			}
			return GetPostByID(id)
		},
	})
}
```
_Listing 4_

The `Comment` type is a structure with three attributes defined statically; `id`, `title` and `body`. Two other attributes `user` and `comment` are defined dynamically to avoid circular dependencies.

Go does not lend itself well to this kind of dynamic modelling, there is little type checking support, most of the variables in the code are of type `interface{}` and need to be type asserted. `CommentType` itself is a varible of type `graphql.Object` and it's attributes are of type `graphql.Field`. So, there's not dirrect translation between the GraphQL DSL and the datastructures used in go.

The `resolve` function for each field exposes the `Source` parameter which is a data type vertex representing the previous node in the traversal. All the attributes of a `Comment` have, as source, the current `CommentType` vertex. Retrieving the `id`, `title` and `body` are straight forward attribute accessors, while retrieving the `user` and the `post` require graph traversal, and thus a database query. The SQL queries are left out of this document because of their simplicity, but they are available in github repository listed in the references section.

## Comparison with REST in common scenarios

In this section we will present a common blog page rendering scenario and compare the REST and the GraphQL implementations. The focus will be on the number of inbound/outbound requests, because these are the biggest contributors to the latency of rendering the page.

The scenario: render a blog post page, it should contain infomation about the author (email), about the blog post (title, body), all comments (title, body) and whether the user that made the comment follows the author of the blog post or not. _Figure 1_ and _Figure 2_ show the interaction between the client SPA, the API server and the database. _Figure 1_ shows this interaction for a REST API, whilst _Figure 2_ for a GraphQL API.

```
+------+                  +------+                  +--------+
|client|                  |server|                  |database|
+--+---+                  +--+---+                  +----+---+
   |      GET /blogs/:id     |                           |
1. +------------------------->  SELECT * FROM blogs...   |
   |                         +--------------------------->
   |                         <---------------------------+
   <-------------------------+                           |
   |                         |                           |
   |     GET /users/:id      |                           |
2. +------------------------->  SELECT * FROM users...   |
   |                         +--------------------------->
   |                         <---------------------------+
   <-------------------------+                           |
   |                         |                           |
   | GET /blogs/:id/comments |                           |
3. +-------------------------> SELECT * FROM comments... |
   |                         +--------------------------->
   |                         <---------------------------+
   <-------------------------+                           |
   |                         |                           |
   | GET /users/:id/followers|                           |
4. +-------------------------> SELECT * FROM followers.. |
   |                         +--------------------------->
   |                         <---------------------------+
   <-------------------------+                           |
   |                         |                           |
   +                         +                           +
```
_Figure 1_

```
+------+                  +------+                  +--------+
|client|                  |server|                  |database|
+--+---+                  +--+---+                  +----+---+
   |      GET /graphql       |                           |
1. +------------------------->  SELECT * FROM blogs...   |
   |                         +--------------------------->
   |                         <---------------------------+
   |                         |                           |
   |                         |                           |
   |                         |                           |
2. |                         |  SELECT * FROM users...   |
   |                         +--------------------------->
   |                         <---------------------------+
   |                         |                           |
   |                         |                           |
   |                         |                           |
3. |                         | SELECT * FROM comments... |
   |                         +--------------------------->
   |                         <---------------------------+
   |                         |                           |
   |                         |                           |
   |                         |                           |
4. |                         | SELECT * FROM followers.. |
   |                         +--------------------------->
   |                         <---------------------------+
   <-------------------------+                           |
   |                         |                           |
   +                         +                           +
```
_Figure 2_

_Listing 5_ contains the single GraphQL query which will fetch all the data needed to render the blog post.

```graphql
{
  user(id: 1) {
    email
    followers
    post(id: 1) {
      title
      body
      comments {
        id
        title
        user {
          id
          email
        }
      }
    }
  }
}
```
_Listing 5_

The number of queries to the database, for this scenario, is deliberately identical, but the number of http requests to the API server has been reduced to just one. We argue that the http requests over the Internet are the most costly in this type of application.

The backend doesn't have to be designed differently to start reaping the benefits of GraphQL, transitioning from REST to GraphQL can be done incrementally. This allows to measure performance improvements and optimize. From this point, the API developer can start to optimize (potentially merge) SQL queries to improve performance. Opportunity for caching is greatly increased, both on the database level and API level.

Abstractions on top of SQL (for instance ORM layers) usually have to contend with the `n+1` problem. In step `4.` of the REST example, a client could have had to request the follower status for the author of each comment in separate requests. This is because in REST there is no standard way of expressing relationships between more that two resources, whereas GraphQL was designed to prevent this problem. Here, we cheat by fetching all the followers of the user and defering to the client the logic of determinig who commented and also follows the author.
- Another problem is fetching more data than the client needs, in order to not break the REST resource abstractions. This is important for bandwith consumption and battery life on module spent on parsing and storing unneeded data.

## Conclusions
GraphQL is a viable alternative to REST because:
* while it is more difficult to design the whole API upfront, this process can be done incrementally. For this reason also, it's easy to transition from REST to GraphQL, the two paradigms can coexist without issues.
* it is more efficient in terms of network requests, even with naive implementations like the one in this document. It also offers more opportunities for query optimization and result caching.
* it is more efficing in terms of bandwith consumption and CPU cycles spent parsing results, because it only returns what is needed to render the page.

REST remains very useful if:
* your API is simple, either has a low number of resources or simple relationships between them.
* you already work with REST APIs inside your organization and you have the tooling all set up. Your clients are prone to expect REST APIs from your organization.
* you have complex ACL policies. In the blog example, a potential feature could allow users to choose which other users can see their email, or their comments on a particular post, or have following be annonymous etc. Optimizing data retrieval and checking complex business rules can be more difficult.

## Appendix 1: Graph Databases And Efficient Data Storage

While it is intuitive to think about application domain data as a graph, as this document demonstrates, the question of efficient data storage to support such an interface is still open.

In recent years graph databases have become more popular. Defering the complexity of resolving the request by translating the GraphQL query into a specific graph database query language, seems like a viable solution.

The problem is that graphs are not an efficient data structure compared to relational databases. A vertex can have links to any other vertex in the graph and access patterns are less predictable and thus offer less opportunity for optimization.

For instance, the problem of caching, ie. which vertices need to be kept in memory for fast access and which vertices do you not? Generic caching algorithms may not be very efficient in the context of graph traversal.

The problem of database sharding: splitting the database into smaller, non-interacting databases, living on separate hardware. In academia, the problem of splitting a graph on the minimal cut is well understood but it is sub-optimial and may potentially result in highly unballanced cuts due to pathological worst-case scenarios.

With relational database, data is modeled in records (or rows, or tuples) and columns, tables and database names are simply namespaces. Most databases are row-oriented, which means that each record is a contiguous chunk of memory, all records in a table are neatly packed one after the other on disk (usually sorted by some key column). This is efficient because it optimizes based on the way physical storage works. The most expesive operation for an HDD is to move the reader/write to another sector on the disk, so minimize these accesses is critical.

Also, there is a high probabily that, if the application is interested in a particular record, it will need the whole record, not just a single key from it. Also there is a high probabily that if the application is interested in a record, it will be interested in it's neighbours as well, for instance a table scan. These two observations make relational databases quite efficient. However, for this reason also, the worst use-case for a relational database is random access across all data all the time. This is exactly what graph databases do.

With the advent of SSD drives which have faster random access, cheap RAM memory so it's actually effective to cache large portions of a graph database, better techniques to optimize graph caching and partitioning, graph databases have become a viable storage solution. And most large companies use it: Facebook have the Social Graph, Google have the Knowledge Graph.
