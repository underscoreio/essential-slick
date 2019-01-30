# Basics {#Basics}

## Orientation

Slick is a Scala library for accessing relational databases using an interface similar to the Scala collections library. You can treat queries like collections, transforming and combining them with methods like `map`, `flatMap`, and `filter` before sending them to the database to fetch results. This is how we'll be working with Slick for the majority of this text.

Standard Slick queries are written in plain Scala. These are *type safe* expressions that benefit from compile time error checking. They also *compose*, allowing us to build complex queries from simple fragments before running them against the database. If writing queries in Scala isn't your style, you'll be pleased to know that Slick also allows you to write plain SQL queries.

In addition to querying, Slick helps you with all the usual trappings of relational database, including connecting to a database, creating a schema, setting up transactions, and so on. You can even drop down below Slick to deal with JDBC (Java Database Connectivity) directly, if that's something you're familiar with and find you need.

This book provides a compact, no-nonsense guide to everything you need to know to use Slick in a commercial setting:

 - Chapter 1 provides an abbreviated overview of the library as a whole, demonstrating the fundamentals of data modelling, connecting to the database, and running queries.
 - Chapter 2 covers basic select queries, introducing Slick's query language and delving into some of the details of type inference and type checking.
 - Chapter 3 covers queries for inserting, updating, and deleting data.
 - Chapter 4 discusses data modelling, including defining custom column and table types.
 - Chapter 5 looks at actions and how you combine multiple actions together.
 - Chapter 6 explores advanced select queries, including joins and aggregates.
 - Chapter 7 provides a brief overview of _Plain SQL_ queries---a useful tool when you need fine control over the SQL sent to your database.

<div class="callout callout-info">
**Slick isn't an ORM**

If you're familiar with other database libraries such as [Hibernate][link-hibernate] or [Active Record][link-active-record], you might expect Slick to be an *Object-Relational Mapping (ORM)* tool. It is not, and it's best not to think of Slick in this way.

ORMs attempt to map object oriented data models onto relational database backends. By contrast, Slick provides a more database-like set of tools such as queries, rows and columns. We're not going to argue the pros and cons of ORMs here, but if this is an area that interests you, take a look at the [Coming from ORM to Slick][link-ref-orm] article in the Slick manual.

If you aren't familiar with ORMs, congratulations. You already have one less thing to worry about!
</div>

## Running the Examples and Exercises

The aim of this first chapter is to provide a high-level overview of the core concepts involved in Slick, and get you up and running with a simple end-to-end example. You can grab this example now by cloning the Git repo of exercises for this book:

~~~ bash
bash$ git clone git@github.com:underscoreio/essential-slick-code.git
Cloning into 'essential-slick-code'...

bash$ cd essential-slick-code

bash$ ls -1
README.md
chapter-01
chapter-02
chapter-03
chapter-04
chapter-05
chapter-06
chapter-07
~~~

Each chapter of the book is associated with a separate sbt project that provides a combination of examples and exercises. We've bundled everything you need to run sbt in the directory for each chapter.

We'll be using a running example of a chat application similar to *Slack*, *Gitter*, or *IRC*. The app will grow and evolve as we proceed through the book. By the end it will have users, messages, and rooms, all modelled using tables, relationships, and queries.

For now, we will start with a simple conversation between two famous celebrities. Change to the `chapter-01` directory now, use the `sbt` command to start sbt, and compile and run the example to see what happens:

~~~ bash
bash$ cd chapter-01

bash$ sbt
# sbt log messages...

> compile
# More sbt log messages...

> run
Creating database table

Inserting test data

Selecting all messages:
Message("Dave","Hello, HAL. Do you read me, HAL?",1)
Message("HAL","Affirmative, Dave. I read you.",2)
Message("Dave","Open the pod bay doors, HAL.",3)
Message("HAL","I'm sorry, Dave. I'm afraid I can't do that.",4)

Selecting only messages from HAL:
Message("HAL","Affirmative, Dave. I read you.",2)
Message("HAL","I'm sorry, Dave. I'm afraid I can't do that.",4)
~~~

If you get output similar to the above, congratulations! You're all set up and ready to run with the examples and exercises throughout the rest of this book. If you encounter any errors, let us know on our [Gitter channel][link-underscore-gitter] and we'll do what we can to help out.

<div class="callout callout-info">
**New to sbt?**

The first time you run sbt, it will download a lot of library dependencies from the Internet and cache them on your hard drive. This means two things:

 - you need a working Internet connection to get started; and
 - the first `compile` command you issue could take a while to complete.

If you haven't used sbt before, you may find the [sbt Getting Started Guide][link-sbt-tutorial] useful.
</div>

## Working Interactively in the sbt Console

Slick queries run asynchronously as `Future` values.
These are fiddly to work with in the Scala REPL, but we do want you to be able to explore Slick via the REPL.
So to get you up to speed quickly,
the example projects define an `exec` method and import the base requirements to run examples from the console.

You can see this by starting `sbt` and then running the `console` command.
Which will give output similar to:

~~~ scala
> console
[info] Starting scala interpreter...
[info]
Welcome to Scala 2.12.1 (Java HotSpot(TM) 64-Bit Server VM, Java 1.8.0_112).
Type in expressions for evaluation. Or try :help.

scala> import slick.jdbc.H2Profile.api._
import Example._
import scala.concurrent.duration._
import scala.concurrent.Await
import scala.concurrent.ExecutionContext.Implicits.global
db: slick.jdbc.H2Profile.backend.Database = slick.jdbc.JdbcBackend$DatabaseDef@ac9a820
exec: [T](program: slick.jdbc.H2Profile.api.DBIO[T])T
res0: Option[Int] = Some(4)
scala>
~~~

Our `exec` helper runs a query and waits for the output.
There is a complete explanation of `exec` and these imports later in the chapter.
For now, here's a small example which fetches all the `message` rows:

```scala
exec(messages.result)
// res1: Seq[Example.MessageTable#TableElementType] =
// Vector(Message(Dave,Hello, HAL. Do you read me, HAL?,1),
//       Message(HAL,Affirmative, Dave. I read you.,2),
//       Message(Dave,Open the pod bay doors, HAL.,3),
//       Message(HAL,I'm sorry, Dave. I'm afraid I can't do that.,4))
```

But we're getting ahead of ourselves.
We'll work though building up queries and running them, and using `exec`, as we work through this chapter.
If the above works for you, great---you have a development environment set up and ready to go.


## Example: A Sequel Odyssey

The test application we saw above creates an in-memory database using [H2][link-h2-home], creates a single table, populates it with test data, and then runs some example queries. The rest of this section will walk you through the code and provide an overview of things to come. We'll reproduce the essential parts of the code in the text, but you can follow along in the codebase for the exercises as well.

<div class="callout callout-warning">
**Choice of Database**

All of the examples in this book use the [H2][link-h2-home] database. H2 is written in Java and runs in-process beside our application code. We've picked H2 because it allows us to forego any system administration and skip to writing Scala.

You might prefer to use *MySQL*, *PostgreSQL*, or some other database---and you can. In [Appendix A](#altdbs) we point you at the changes you'll need to make to work with other databases. However, we recommend sticking with H2 for at least this first chapter so you can build confidence using Slick without running into database-specific complications.
</div>

### Library Dependencies

Before diving into Scala code, let's look at the sbt configuration. You'll find this in `build.sbt` in the example:

~~~ scala
name := "essential-slick-chapter-01"

version := "1.0.0"

scalaVersion := "2.12.8"

libraryDependencies ++= Seq(
  "com.typesafe.slick" %% "slick"           % "3.3.0",
  "com.h2database"      % "h2"              % "1.4.185",
  "ch.qos.logback"      % "logback-classic" % "1.1.2"
)
~~~

This file declares the minimum library dependencies for a Slick project:

- Slick itself;

- the H2 database; and

- a logging library.

If we were using a separate database like MySQL or PostgreSQL, we would substitute the H2 dependency for the JDBC driver for that database.

### Importing Library Code

Database management systems are not created equal. Different systems support different data types, different dialects of SQL, and different querying capabilities. To model these capabilities in a way that can be checked at compile time, Slick provides most of its API via a database-specific *profile*. For example, we access most of the Slick API for H2 via the following `import`:

```tut:silent
import slick.jdbc.H2Profile.api._
```

Slick makes heavy use of implicit conversions and extension methods, so we generally need to include this import anywhere where we're working with queries or the database. [Chapter 5](#Modelling) looks how you can keep a specific database profile out of your code until necessary.

### Defining our Schema

Our first job is to tell Slick what tables we have in our database and how to map them onto Scala values and types. The most common representation of data in Scala is a case class, so we start by defining a `Message` class representing a row in our single example table:

```tut:book
final case class Message(
  sender:  String,
  content: String,
  id:      Long = 0L)
```


Next we define a `Table` object, which corresponds to our database table and tells Slick how to map back and forth between database data and instances of our case class:

```tut:book
final class MessageTable(tag: Tag) extends Table[Message](tag, "message") {

  def id      = column[Long]("id", O.PrimaryKey, O.AutoInc)
  def sender  = column[String]("sender")
  def content = column[String]("content")

  def * = (sender, content, id).mapTo[Message]
}
```

`MessageTable` defines three `column`s: `id`, `sender`, and `content`. It defines the names and types of these columns, and any constraints on them at the database level. For example, `id` is a column of `Long` values, which is also an auto-incrementing primary key.

The `*` method provides a *default projection* that maps between columns in the table and instances of our case class. 
Slick's `mapTo` macro creates a two-way mapping between the three columns and the three fields in `Message`.

We'll cover projections and default projections in detail in [Chapter 5](#Modelling).
For now, all we need to know is that this line allows us to query the database and get back `Messages` instead of tuples of `(String, String, Long)`.

The `tag` on the first line is an implementation detail that allows Slick to manage multiple uses of the table in a single query.
Think of it like a table alias in SQL. We don't need to provide tags in our user code---Slick takes case of them automatically.

### Example Queries

Slick allows us to define and compose queries in advance of running them against the database. We start by defining a `TableQuery` object that represents a simple `SELECT *` style query on our message table:

```tut:book
val messages = TableQuery[MessageTable]
```

Note that we're not *running* this query at the moment---we're simply defining it as a means to build other queries. For example, we can create a `SELECT * WHERE` style query using a combinator called `filter`:

```tut:book
val halSays = messages.filter(_.sender === "HAL")
```

Again, we haven't run this query yet---we've defined it as a building block for yet more queries. This demonstrates an important part of Slick's query language---it is made from *composable* elements that permit a lot of valuable code re-use.

<div class="callout callout-info">
**Lifted Embedding**

If you're a fan of terminology, know that what we have discussed so far is called the *lifted embedding* approach in Slick:

 - define data types to store row data (case classes, tuples, or other types);
 - define `Table` objects representing mappings between our data types and the database;
 - define `TableQueries` and combinators to build useful queries before we run them against the database.

Lifted embedding is the standard way to work with Slick. We will discuss the other approach, called *Plain SQL querying*, in [Chapter 7](#PlainSQL).
 </div>



### Configuring the Database

We've written all of the code so far without connecting to the database. Now it's time to open a connection and run some SQL. We start by defining a `Database` object which acts as a factory for managing connections and transactions:

```tut:book
val db = Database.forConfig("chapter01")
```

The parameter to `Database.forConfig` determines which configuration to use from the `application.conf` file.
This file is found in `src/main/resources`. It looks like this:

```scala
chapter01 {
  driver = "org.h2.Driver"
  url    = "jdbc:h2:mem:chapter01"
  keepAliveConnection = true
  connectionPool = disabled
}
```

This syntax comes from the [Typesafe Config][link-config] library, which is also used by Akka and the Play framework.

The parameters we're providing are intended to configure the underlying JDBC layer.
The `driver` parameter is the fully qualified class name of the JDBC driver for our chosen DBMS.

The `url` parameter is the standard [JDBC connection URL][link-jdbc-connection-url],
and in this case we're creating an in-memory database called `"chapter01"`.

By default the H2 in-memory database is deleted when the last connection is closed.
As we will be running multiple connections in our examples,
we enable `keepAliveConnection` to keep the data around until our program completes.

Slick manages database connections and transactions using auto-commit.
We'll look at transactions in [Chapter 4](#combining).

<div class="callout callout-info">
**JDBC**

If you don't have a background working with Java, you may not have heard of Java Database Connectivity (JDBC).  It's a specification for accessing databases in a vendor
neutral way. That is, it aims to be independent of the specific database you are connecting to.

The specification is mirrored by a library implemented for each database you want to connect to. This library is called  the *JDBC driver*.

JDBC works with *connection strings*, which are URLs like the one above that tell the driver where your database is and how to connect to it (e.g. by providing login credentials).
</div>

### Creating the Schema

Now that we have a database configured as `db`, we can use it.

Let's start with a `CREATE` statement for `MessageTable`, which we build using methods of our `TableQuery` object, `messages`. The Slick method `schema` gets the schema description. We can see what that would be via the `createStatements` method:

```tut:book
messages.schema.createStatements.mkString
```

But we've not sent this to the database yet. We've just printed the statement, to check it is what we think it should be.

In Slick, what we run against the database is an _action_. This is how we create an action for the `messages` schema:

```tut:book
val action: DBIO[Unit] = messages.schema.create
```

The result of this `messages.schema.create` expression is a `DBIO[Unit]`. This is an object representing a DB action that, when run, completes with a result of type `Unit`. Anything we run against a database is a `DBIO[T]` (or a `DBIOAction`, more generally). This includes queries, updates, schema alterations, and so on.

<div class="callout callout-info">
**DBIO and DBIOAction**

In this book we will talk about actions as having the type `DBIO[T]`.

This is a simplification. The more general type is `DBIOAction`, and specifically for this example, it is a `DBIOAction[Unit, NoStream, Effect.Schema]`. The details of all of this we will get to later in the book.

But `DBIO[T]` is a type alias supplied by Slick, and is perfectly fine to use.
</div>

Let's run this action:

```tut:silent
import scala.concurrent.Future
```
```tut:book
val future: Future[Unit] = db.run(action)
```

The result of `run` is a `Future[T]`, where `T` is the type of result returned by the database. Creating a schema is a side-effecting operation so the result type is `Future[Unit]`. This matches the type `DBIO[Unit]` of the action we started with.

`Future`s are asynchronous. That's to say, they are placeholders for values that will eventually appear. We say that a future _completes_ at some point. In production code,  futures allow us to chain together computations without blocking to wait for a result. However, in simple examples like this we can block until our action completes:

```tut:silent
import scala.concurrent.Await
import scala.concurrent.duration._
```
```tut:book
val result = Await.result(future, 2.seconds)
```


### Inserting Data

Once our table is set up, we need to insert some test data. We'll define a helper method to create a few test `Messages` for demonstration purposes:

```tut:book
def freshTestData = Seq(
  Message("Dave", "Hello, HAL. Do you read me, HAL?"),
  Message("HAL",  "Affirmative, Dave. I read you."),
  Message("Dave", "Open the pod bay doors, HAL."),
  Message("HAL",  "I'm sorry, Dave. I'm afraid I can't do that.")
)
```

The insert of this test data is an action:

```tut:book
val insert: DBIO[Option[Int]] = messages ++= freshTestData
```

The `++=` method of `message` accepts a sequence of `Message` objects and translates them to a bulk `INSERT` query (`freshTestData` is a regular Scala `Seq[Message]`).
We run the `insert` via `db.run`, and when the future completes our table is populated with data:

```tut:book
val result: Future[Option[Int]] = db.run(insert)
```

The result of an insert operation is the number of rows inserted.
The `freshTestData` contains four messages, so in this case the result is `Some(4)` when the future completes:

```tut:book
val rowCount = Await.result(result, 2.seconds)
```

The result is optional because the underlying Java APIs do not guarantee a count of rows for batch inserts---some databases simply return `None`.
We discuss single and batch inserts and updates further in [Chapter 3](#Modifying).

### Selecting Data

Now our database has a few rows in it, we can start selecting data. We do this by taking a query, such as `messages` or `halSays`, and turning it into an action via the `result` method:

```tut:book
val messagesAction: DBIO[Seq[Message]] = messages.result

val messagesFuture: Future[Seq[Message]] = db.run(messagesAction)

val messagesResults = Await.result(messagesFuture, 2.seconds)
```

```tut:invisible
assert(messagesResults.length == 4, "Expected 4 results")
```

We can see the SQL issued to H2 using the `statements` method on the action:

```tut:book
val sql = messages.result.statements.mkString
```

```tut:invisible
assert(sql == """select "sender", "content", "id" from "message"""", s"Expected: $sql")
```

<div class="callout callout-info">
**The `exec` Helper Method**

In our applications we should avoid blocking on `Future`s whenever possible.
However, in the examples in this book we'll be making heavy use of `Await.result`.
We will introduce a helper method called `exec` to make the examples easier to read:

```tut:book
def exec[T](action: DBIO[T]): T =
  Await.result(db.run(action), 2.seconds)
```

All `exec` does is run the supplied action and wait for the result.
For example, to run a select query we can write:

~~~ scala
exec(messages.result)
~~~

Use of `Await.result` is strongly discouraged in production code.
Many web frameworks provide direct means of working with `Future`s without blocking.
In these cases, the best approach is simply to transform the `Future` query result
to a `Future` of an HTTP response and send that to the client.
</div>

If we want to retrieve a subset of the messages in our table,
we can run a modified version of our query.
For example, calling `filter` on `messages` creates a modified query with
a `WHERE` expression that retrieves the expected rows:

```tut:book
messages.filter(_.sender === "HAL").result.statements.mkString
```

To run this query, we convert it to an action using `result`,
run it against the database with `db.run`, and await the final result with `exec`:

```tut:book
exec(messages.filter(_.sender === "HAL").result)
```

We actually generated this query earlier and stored it in the variable `halSays`.
We can get exactly the same results from the database by running this variable instead:

```tut:book
exec(halSays.result)
```

Notice that we created our original `halSays` before connecting to the database.
This demonstrates perfectly the notion of composing a query from small parts and running it later on.

We can even stack modifiers to create queries with multiple additional clauses.
For example, we can `map` over the query to retrieve a subset of the columns.
This modifies the `SELECT` clause in the SQL and the return type of the `result`:

```tut:book
halSays.map(_.id).result.statements.mkString

exec(halSays.map(_.id).result)
```

### Combining Queries with For Comprehensions

`Query` is a *monad*. It implements the methods `map`, `flatMap`, `filter`, and `withFilter`, making it compatible with Scala for comprehensions.
For example, you will often see Slick queries written in this style:

```tut:book
val halSays2 = for {
  message <- messages if message.sender === "HAL"
} yield message
```

Remember that for comprehensions are aliases for chains of method calls.
All we are doing here is building a query with a `WHERE` clause on it.
We don't touch the database until we execute the query:

```tut:book
exec(halSays2.result)
```

### Actions Combine

Like `Query`, `DBIOAction` is also a monad. It implements the same methods described above, and shares the same compatibility with for comprehensions.

We can combine the actions to create the schema, insert the data, and query results into one action. We can do this before we have a database connection, and we run the action like any other.
To do this, Slick provides a number of useful action combinators. We can use `andThen`, for example:

```tut:book
val actions: DBIO[Seq[Message]] = (
  messages.schema.create       andThen
  (messages ++= freshTestData) andThen
  halSays.result
)
```

What `andThen` does is combine two actions so that the result of the first action is thrown away.
The end result of the above `actions` is the last action in the `andThen` chain.

If you want to get funky, `>>` is another name for `andThen`:

```tut:book
val sameActions: DBIO[Seq[Message]] = (
  messages.schema.create       >>
  (messages ++= freshTestData) >>
  halSays.result
)
```

Combining actions is an important feature of Slick.
For example, one reason for combining actions is to wrap them inside a transaction.
In [Chapter 4](#combining) we'll see this, and also that actions can be composed with for comprehensions, just like queries.


<div class="callout callout-danger">
*Queries, Actions, Futures... Oh My!*

The difference between queries, actions, and futures is a big point of confusion for newcomers to Slick 3. The three types share many properties: they all have methods like `map`, `flatMap`, and `filter`, they are all compatible with for comprehensions, and they all flow seamlessly into one another through methods in the Slick API. However, their semantics are quite different:

 - `Query` is used to build SQL for a single query. Calls to `map` and `filter` modify clauses to the SQL, but only one query is created.

 - `DBIOAction` is used to build sequences of SQL queries. Calls to `map` and `filter` chain queries together and transform their results once they are retrieved in the database. `DBIOAction` is also used to delineate transactions.

 - `Future` is used to transform the asynchronous result of running a `DBIOAction`. Transformations on `Future`s happen after we have finished speaking to the database.

In many cases (for example select queries) we create a `Query` first and convert it to a `DBIOAction` using the `result` method. In other cases (for example insert queries), the Slick API gives us a `DBIOAction` immediately, bypassing `Query`. In all cases, we *run* a `DBIOAction` using `db.run(...)`, turning it into a `Future` of the result.

We recommend taking the time to thoroughly understand `Query`, `DBIOAction`, and `Future`. Learn how they are used, how they are similar, how they differ, what their type parameters represent, and how they flow into one another. This is perhaps the single biggest step you can take towards demystifying Slick 3.
</div>

## Take Home Points

In this chapter we've seen a broad overview of the main aspects of Slick, including defining a schema, connecting to the database, and issuing queries to retrieve data.

We typically model data from the database as case classes and tuples that map to rows from a table. We define the mappings between these types and the database using `Table` classes such as `MessageTable`.

We define queries by creating `TableQuery` objects such as `messages` and transforming them with combinators such as `map` and `filter`.
These transformations look like transformations on collections, but they are used to build SQL code rather than manipulate the results returned.

We execute a query by creating an action object via its `result` method. Actions are used to build sequences of related queries and wrap them in transactions.

Finally, we run the action against the database by passing it to the `run` method of the database object. We are given back a `Future` of the result. When the future completes, the result is available.

The query language is the one of the richest and most significant parts of Slick. We will spend the entire next chapter discussing the various queries and transformations available.

## Exercise: Bring Your Own Data

Let's get some experience with Slick by running queries against the example database.
Start sbt using the `sbt` command and type `console` to enter the interactive Scala console.
We've configured sbt to run the example application before giving you control,
so you should start off with the test database set up and ready to go:

~~~ bash
bash$ sbt
# sbt logging...

> console
# More sbt logging...
# Application runs...

scala>
~~~

Start by inserting an extra line of dialog into the database.
This line hit the cutting room floor late in the development of the film 2001,
but we're happy to reinstate it here:

```tut:book
Message("Dave","What if I say 'Pretty please'?")
```

You'll need to insert the row using the `+=` method on `messages`.
Alternatively you could put the message in a `Seq` and use `++=`.
We've included some common pitfalls in the solution in case you get stuck.

<div class="solution">
Here's the solution:

```tut:book
exec(messages += Message("Dave","What if I say 'Pretty please'?"))
```

The return value indicates that `1` row was inserted.
Because we're using an auto-incrementing primary key, Slick ignores the `id` field for our `Message` and asks the database to allocate an `id` for the new row.
It is possible to get the insert query to return the new `id` instead of the row count, as we shall see next chapter.

Here are some things that might go wrong:

If you don't pass the action created by `+=` to `db` to be run, you'll get back the `Action` object instead.

```tut:book
messages += Message("Dave","What if I say 'Pretty please'?")
```

If you don't wait for the future to complete, you'll see just the future itself:

```tut:book
val f = db.run(messages += Message("Dave","What if I say 'Pretty please'?"))
```


```tut:invisible

  // Post-exercise clean up
  // We inserted a new message for Dave twice in the last solution.
  // We need to fix this so the next exercise doesn't contain confusing duplicates

  // NB: this block is not inside {}s because doing that triggered:
  // Could not initialize class $line41.$read$$iw$$iw$$iw$$iw$$iw$$iw$

  import scala.concurrent.ExecutionContext.Implicits.global
  val ex1cleanup: DBIO[Int] = for {
    _ <- messages.filter(_.content === "What if I say 'Pretty please'?").delete
    m = Message("Dave","What if I say 'Pretty please'?", 5L)
    _ <- messages.forceInsert(m)
    count <- messages.filter(_.content === "What if I say 'Pretty please'?").length.result
  } yield count
  val rowCount = exec(ex1cleanup)
  assert(rowCount == 1, s"Wrong number of rows after cleaning up ex1: $rowCount")
```
</div>

Now retrieve the new dialog by selecting all messages sent by Dave.
You'll need to build the appropriate query using `messages.filter`, and create the action to be run by using its `result` method.
Don't forget to run the query by using the `exec` helper method we provided.

Again, we've included some common pitfalls in the solution.

<div class="solution">
Here's the code:


```tut:book
exec(messages.filter(_.sender === "Dave").result)
```

If that's hard to read, we can print each message in turn.
As the `Future` will evaluate to a collection of `Message`, we can `foreach` over that with a function of `Message => Unit`, such as `println`:

```tut:book
val result: Seq[Message] = exec(messages.filter(_.sender === "Dave").result)
result.foreach(println)
```


Here are some things that might go wrong:

Note that the parameter to `filter` is built using a triple-equals operator, `===`, not a regular `==`.
If you use `==` you'll get an interesting compile error:

```tut:book:fail
exec(messages.filter(_.sender == "Dave").result)
```

The trick here is to notice that we're not actually trying to compare `_.sender` and `"Dave"`.
A regular equality expression evaluates to a `Boolean`, whereas `===` builds an SQL expression of type `Rep[Boolean]`
(Slick uses the `Rep` type to represent expressions over `Column`s as well as `Column`s themselves).
The error message is baffling when you first see it but makes sense once you understand what's going on.

Finally, if you forget to call `result`,
you'll end up with a compilation error as `exec` and the call it is wrapping `db.run` both expect actions:

```tut:book:fail
exec(messages.filter(_.sender === "Dave"))
```

`Query` types tend to be verbose, which can be distracting from the actual cause of the problem
(which is that we're not expecting a `Query` object at all).
We will discuss `Query` types in more detail next chapter.
</div>
