# Basics {#Basics}

## Orientation

Slick is a Scala library for accessing relational databases using an interface similar to the Scala collections library. You can treat queries like collections, transforming and combining them with methods like `map`, `flatMap`, and `filter` before sending them to the database to fetch results. This is how we'll be working with Slick for the majority of this text.

Standard Slick queries are written in plain Scala. These are *type safe* expressions that benefit from compile time error checking. They also *compose*, allowing us to build complex queries from simple fragments before running them against the database. If writing queries in Scala isn't your style, you'll be pleased to know that Slick also supports *plain SQL queries* that allow you to write SQL.

In addition to querying, Slick helps you with all the usual trappings of relational database, including connecting to a database, creating a schema, setting up transactions, and so on. You can even drop down below Slick to deal with JDBC (Java Database Connectivity) directly, if that's something you're familiar with and find you need.

This book provides a compact, no-nonsense guide to everything you need to know to use Slick in a commercial setting:

 - Chapter 1 provides an abbreviated overview of the library as a whole, demonstrating the fundamentals of data modelling, connecting to the database, and running queries.
 - Chapter 2 covers basic select queries, introducing Slick's query language and delving into some of the details of type inference and type checking.
 - Chapter 3 covers queries for inserting, updating, and deleting data.
 - Chapter 4 discusses data modelling, including defining custom column and table types.
 - Chapter 5 explores advanced select queries, including joins and aggregates.
 - Chapter 6 provides a brief overview of _Plain SQL_ queries---a useful tool when you need fine control over the SQL sent to your database.

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
~~~

Each chapter of the book is associated with a separate sbt project that provides a combination of examples and exercises. We've bundled everything you need to run sbt in the directory for each chapter.

We'll be using a running example of a chat application, *Slack*, *Flowdock*, or an *IRC* application. The app will grow and evolve as we proceed through the book. By the end it will have users, messages, and rooms, all modelled using tables, relationships, and queries.

For now, we will start with a simple conversation between two famous celebrities. Change to the `chapter-01` directory now, use the `sbt.sh` script to start sbt, and compile and run the example to see what happens:

~~~ bash
bash$ cd chapter-01

bash$ ./sbt.sh
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

If you haven't used sbt before, you may find the [sbt Tutorial](link-sbt-tutorial) useful.
</div>

## Example: A Sequel Odyssey

The test application we saw above creates an in-memory database using [H2][link-h2-home], creates a single table, populates it with test data, and then runs some example queries. The rest of this section will walk you through the code and provide an overview of things to come. We'll reproduce the essential parts of the code in the text, but you can follow along in the codebase for the exercises as well.

<div class="callout callout-warning">
**Choice of Database**

All of the examples in this book use the [H2][link-h2-home] database. H2 is written in Java and runs in-process along-side our application code. We've picked H2 because it allows us to forego any system administration and skip to writing Scala code.

You might prefer to use *MySQL*, *PostgreSQL*, or some other database---and you can. In [Appendix A](#altdbs) we point you at the changes you'll need to make to work with other databases. However, we recommend sticking with H2 for at least this first chapter so you can build confidence using Slick without running into database-specific complications.
</div>

### Library Dependencies

Before diving into Scala code, let's look at the sbt configuration. You'll find this in `build.sbt` in the example:

~~~ scala
name := "essential-slick-chapter-01"

version := "3.0"

scalaVersion := "2.11.6"

libraryDependencies ++= Seq(
  "com.typesafe.slick" %% "slick"           % "3.0.0",
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

Database management systems are not created equal. Different systems support different data types, different dialects of SQL, and different querying capabilities. To model these capabilities in a way that can be checked at compile time, Slick provides most of its API via a database-specific *driver*. For example, we access most of the Slick API for H2 via the following `import`:

~~~ scala
import slick.driver.H2Driver.api._
~~~

Slick makes heavy use of implicit conversions and extension methods, so we generally need to include this import anywhere where we're working with queries or the database. [Chapter 4](#Modelling) looks how you can keep a specific database driver out of your code until necessary.

### Defining our Schema

Our first job is to tell Slick what tables we have in our database and how to map them onto Scala values and types. The most common representation of data in Scala is a case class, so we start by defining a `Message` class representing a row in our single example table:

~~~ scala
final case class Message(
  sender: String,
  content: String,
  id: Long = 0L)
~~~

We also define a helper method to create a few test `Messages` for demonstration purposes:

~~~ scala
def freshTestData = Seq(
  Message("Dave", "Hello, HAL. Do you read me, HAL?"),
  Message("HAL",  "Affirmative, Dave. I read you."),
  Message("Dave", "Open the pod bay doors, HAL."),
  Message("HAL",  "I'm sorry, Dave. I'm afraid I can't do that.")
)
~~~

Next we define a `Table` object, which corresponds to our database table and tells Slick how to map back and forth between database data and instances of our case class:

~~~ scala
final class MessageTable(tag: Tag)
      extends Table[Message](tag, "message") {

  def id      = column[Long]("id", O.PrimaryKey, O.AutoInc)
  def sender  = column[String]("sender")
  def content = column[String]("content")

  def * = (sender, content, id) <>
          (Message.tupled, Message.unapply)
}
~~~

`MessageTable` defines three `column`s: `id`, `sender`, and `content`. It defines the names and types of these columns, and any constraints on them at the database level. For example, `id` is a column of `Long` values, which is also an auto-incrementing primary key.

The `*` method provides a *default projection* that maps between columns in the table and instances of our case class. Slick's `<>` method defines a two-way mapping between three columns and the three fields in `Message`, via the standard `tupled` and `unapply` methods generated as part of the case class. We'll cover projections and default projections in detail in [Chapter 4](#Modelling). For now, all you need to know is that this line allows us to query the database and get back `Messages` instead of tuples of `(String, String, Long)`.

The `tag` is an implementation detail that allows Slick to manage multiple uses of the table in a single query. Think of it like a table alias in SQL. We don't need to provide tags in our user code---Slick takes case of them automatically.

### Example Queries

Slick allows us to define and compose queries in advance of running them against the database. We start by defining a `TableQuery` object that represents a simple `SELECT *` style query on our message table:

~~~ scala
val messages = TableQuery[MessageTable]
~~~

Note that we're not *running* this query at the moment---we're simply defining it as a means to build other queries. For example, we can create a `SELECT * WHERE` style query using a combinator called `filter`:

~~~ scala
val halSays = messages.filter(_.sender === "HAL")
~~~

Again, we haven't run this query yet---we've simply defined it as a useful building block for yet more queries. This demonstrates an important part of Slick's query language---it is made from *composable* building blocks that permit a lot of valuable code re-use.

<div class="callout callout-info">
**Lifted Embedding**

If you're a fan of terminology, know that what we have discussed so far is called the *lifted embedding* approach in Slick:

 - define data types to store row data (case classes, tuples, or other types);
 - define `Table` objects representing mappings between our data types and the database;
 - define `TableQueries` and combinators to build useful queries before we run them against the database.

Lifted embedding is the standard way to work with Slick. We will discuss the other approach, called *Plain SQL querying*, in [Chapter 6](#PlainSQL).
 </div>



### Connecting to the Database

We've written all of the code so far without connecting to the database. Now it's time to open a connection and run some SQL. We start by defining a `Database` object, which acts as a factory for managing connections and transactions:

~~~ scala
def db = Database.forConfig("chapter01")
~~~

The parameter to `Database.forConfig` determines which configuration to use from the `application.conf` file.
This file is found in `src/main/resources`. It looks like this:

~~~ conf
chapter01 = {
  connectionPool = disabled
  url    = "jdbc:h2:mem:chapter01"
  driver = "org.h2.Driver"
  keepAliveConnection = true
}
~~~

This format comes from the [Typesafe Config](link-config) library, which is also used by Akka and the Play framework.

The parameters we're providing are intended to configure the underlying JDBC layer. The `url` parameter is the standard [JDBC connection URL][link-jdbc-connection-url], and the `driver` parameter is the fully qualified class name of the JDBC driver for our chosen DBMS. In this case we're creating an in-memory database called `"chapter01"`.  

By default the H2 in-memory database is deleted when the last connection is closed. As we will be running multiple connections in our examples, we enable `keepAliveConnection` to keep the data around until our program completes.

Slick manages database connections and transactions using auto-commit.
We'll see how to manually manage starting, committing, and rolling back transactions in [Chapter 3](#Modifying).

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

~~~ scala
messages.schema.createStatements.mkString
// res0: String =
//  create table "message" (
//   "sender" VARCHAR NOT NULL,
//   "content" VARCHAR NOT NULL,
//   "id" BIGINT GENERATED BY DEFAULT AS IDENTITY(START WITH 1) NOT NULL PRIMARY KEY
// )
~~~

But we've not sent this to the database yet. We've just printed the statement, to check it is what we think it should be.

In Slick, what you run against the database is an _action_. This is how we create an action for the `messages` schema:

~~~ scala
val action: DBIO[Unit] = messages.schema.create
~~~

The result of this `messages.schema.create` expression is a `DBUnit[Unit]`.

<div class="callout callout-info">
**DBIO and DBIOAction**

In this chapter we will talk about actions as having the type `DBIO[T]`.

This is a simplification. The more general type is `DBIOAction`, and specifically for this example, it is a `DBIOAction[Unit, NoStream, Effect.Schema]`. The details of all of this we will get to later in the book.

But `DBIO[T]` is a type alias supplied by Slick, and is perfectly fine to use.
</div>


What's important to know is that anything you can run against a database is a `DBIO[T]` (or a `DBIOAction`, more generally): a query, an update, you name it, they are all examples of a Database I/O Action.  

Let's run this action:

~~~ scala
val future: Future[Unit] = db.run(action)
~~~

The result of `run` is a `Future[T]`.  As creating the schema is just a side-effect, it's a `Future[Unit]`, matching up with the `DBIO[Unit]` we started with.

`Future`s are asynchronous. That's to say, it is place holder for some value that will eventually appear. We say the future _completes_ at some point. For us, this means when working with sample applications, or in the console, we will need to wait for a future to complete to the see the result:

~~~ scala
val result = Await.result(future, 2 seconds)
~~~

We will have more to say on `Future`s, what you can do with them, and how they compose in Chapter **TODO**.

### Inserting Data

Once our table is set up, we need to insert some test data. That would also be an action:

~~~ scala
val insert = messages ++= freshTestData
~~~

The `++=` method of `message` accepts a sequence of `Message` objects and translates them to a bulk `INSERT` query (recall that `freshTestData` is just a regular Scala `Seq[Message]`). We run the `insert` via `db.run`, and when the future completes, our table will be populated with data:

~~~ scala
val result: Future[Option[Int]] = db.run(insert)
~~~

The `freshTestData` contains four messages, so the result, when it completes, will be `Some(4)`.  It's optional because this is a batch insert. The underlying Java APIs do not guarantee a count of rows for batch inserts.  We discuss single and batch inserts and updates further in [Chapter 3](#Modifying).


### Selecting Data

Now our database has a few rows in it, we can start selecting data. We do this by taking a query, such as `messages` or `halSays`, and turning it into an action via the `result` method on a query:

~~~ scala
val messagesAction: DBIO[Seq[Message]] = messages.result

val messagesFuture: Future[Seq[Message]] = db.run(messagesAction)

val messagesResults = Await.result(messagesFuture, 2 seconds)
// messagesResults: Seq[Example.Message] = Vector(
//  Message(Dave,Hello, HAL. Do you read me, HAL?,1),
//  Message(HAL,Affirmative, Dave. I read you.,2),
//  Message(Dave,Open the pod bay doors, HAL.,3),
//  Message(HAL,I'm sorry, Dave. I'm afraid I can't do that.,4))
~~~

We can see the SQL issued to H2 using the `statements` method on the action:

~~~ scala
messages.result.statements
// res2: String = select x2."sender", x2."content", x2."id" from "message" x2
~~~

<div class="callout callout-info">
**`Await.result` and `exec`**

That `db.run` returns a `Future[R]`, and Slick performs all database communication asynchronously,
is incredibly useful when building applications that you don't want to block waiting for a database call.
However, it is  quite annoying when you are trying to explain how to use Slick.
For this reason we'll be using a method called `exec` to tidy away the detail of working with `Future`s so you can focus on Slick.

~~~ scala
def exec[T](action: DBIO[T]): T =
  Await.result(db.run(action), 2 seconds)
~~~

All the `exec` method does is run the action supplied and waits up to two seconds for the program to finish. For example, to run a query we could write:

~~~ scala
exec(messages.result)
~~~

Outside of the REPL, and outside of the simple applications we provide, you don't tend to wait on futures. In all likelihood the web framework you are using, or other technologies, will accept the future and handle it for you.
</div>

If we want to retrieve a subset of the messages in our table,
we simply run a modified version of our query.
For example, calling `filter` on `messages` creates a modified query with a `WHERE` expression in the SQL that retrieves the expected subset of results:

~~~ scala
messages.filter(_.sender === "HAL").result.statements
// res3: String = select x2."sender", x2."content", x2."id"
//                from "message" x2
//                where x2."sender" = 'HAL'
~~~

To run this query, we need to hand it to `db.run` as an action:

~~~ scala
exec(messages.filter(_.sender === "HAL").result)
// res4: Seq[Example.MessageTable#TableElementType] = Vector(
//   Message(HAL,Affirmative, Dave. I read you.,2),
//   Message(HAL,I'm sorry, Dave. I'm afraid I can't do that.,4))
~~~

If you remember, we actually generated this query earlier and stored it in the variable `halSays`. We can get exactly the same results from the database by running this stored query instead:

~~~ scala
exec(halSays.result)
// res5: Seq[Example.MessageTable#TableElementType] = Vector(
//   Message(HAL,Affirmative, Dave. I read you.,2),
//   Message(HAL,I'm sorry, Dave. I'm afraid I can't do that.,4))
~~~

The observant among you will remember that we created `halSays` before connecting to the database. This demonstrates perfectly the notion of composing a query from small parts and running it later on. We can even stack modifiers to create queries with multiple additional clauses. For example, we can `map` over the query to retrieve a subset of the data, modifying the `SELECT` clause in the SQL and the return type of the `result`:

~~~ scala
halSays.map(_.id).result.statements
// res6:List[String] = List(select x2."id" from "message" x2 where x2."sender" = 'HAL')

exec(halSays.map(_.id).result)
// res7: Seq[Int] = Vector(2, 4)
~~~

### For Comprehensions

Queries implement methods called `map`, `flatMap`, `filter`, and `withFilter`, making them compatible with Scala for comprehensions.
You will often see Slick queries written in this style:

~~~ scala
val halSays2 = for {
  message <- messages if message.sender === "HAL"
} yield message
~~~

Remember that for comprehensions are simply aliases for chains of method calls.
All we are doing here is building a query with a `WHERE` clause on it.
We don't touch the database until we execute the query:

~~~ scala
exec(halSays2.result)
// res8: Seq[Message] = ...
~~~

### Actions Combine

Like queries, actions can also be composed.

We can combine the actions to create the schema, insert the data, and query results into one action.  We can do this before we have a database connection, and we run the action like any other:

~~~ scala
val actions =
  messages.schema.create       andThen
  (messages ++= freshTestData) andThen
  messages.result
~~~

And if you want to get funky, `>>` is another name for `andThen`:

~~~ scala
val actions =
  messages.schema.create       >>
  (messages ++= freshTestData) >>
  messages.result
~~~

One important reason for composing queries and actions is to wrap them inside a transaction. In Chapter **TODO** we'll see this, and also that actions can be composed with for comprehensions, just like queries.

## Take Home Points

In this chapter we've seen a broad overview of the main aspects of Slick, including defining a schema, connecting to the database, and issuing queries to retrieve data.

We typically model data from the database as case classes and tuples that map to rows from a table. We define the mappings between these types and the database using `Table` classes such as `MessageTable`.

We define queries by creating `TableQuery` objects such as `messages` and transforming them with combinators such as `map` and `filter`.
These transformations look like transformations on collections, but they operate on the parameters of the query rather than the results returned.

We execute a query by creating an action object, via the `result` method of a query, and passing it to the `run` method of the database object.

The result of an action is a `Future[T]`. When the future completes, the result is available.

The query language is the one of the richest and most significant parts of Slick. We will spend the entire next chapter discussing the various queries and transformations available.

## Exercise: Bring Your Own Data

Let's get some experience with Slick by running queries against the example database.
Start sbt using `sbt.sh` and type `console` to enter the interactive Scala console.
We've configured sbt to run the example application before giving you control,
so you should start off with the test database set up and ready to go:

~~~ bash
bash$ ./sbt.sh
# sbt logging...

> console
# More sbt logging...
# Application runs...

scala>
~~~

Start by inserting an extra line of dialog into the database.
This line hit the cutting room floor late in the development of the film 2001,
but we're happy to reinstate it here:

~~~ scala
Message("Dave","What if I say 'Pretty please'?")
~~~

You'll need to insert the row using the `+=` method on `messages`.
Alternatively you could put the message in a `Seq` and use `++=`.
We've included some common pitfalls in the solution in case you get stuck.

<div class="solution">
Here's the solution:

~~~ scala
exec(messages += Message("Dave","What if I say 'Pretty please'?"))
// res5: Int = 1
~~~

The return value indicates that `1` row was inserted. Because we're using an auto-incrementing primary key, Slick ignores the `id` field for our `Message` and asks the database to allocate an `id` for the new row.
It is possible to get the insert query to return the new `id` instead of the row count, as we shall see next chapter.

Here are some things that might go wrong:

If you don't pass the action created by `+=` to `db` to be run, you'll get back the `Action` object instead.

~~~ scala
messages += Message("Dave","What if I say 'Pretty please'?")
res6: slick.profile.FixedSqlAction[Int,slick.dbio.NoStream,slick.dbio.Effect.Write] =
 slick.driver.JdbcActionComponent$InsertActionComposerImpl$$anon$8@7e0e6d1e
~~~

If you don't wait for the future to complete, you'll see just the future itself:

~~~ scala
db.run(messages += Message("Dave","What if I say 'Pretty please'?"))
res7: scala.concurrent.Future[Int] = scala.concurrent.impl.Promise$DefaultPromise@652a41e8
~~~
</div>

Now retrieve the new dialog by selecting all messages sent by Dave. You'll need to build the appropriate query using `messages.filter`, and create the action to be run by using its `result` method. Don't forget to run the query by using the `exec` helper method we provided.

Again, we've included some common pitfalls in the solution.

<div class="solution">
Here's the code:

~~~ scala
exec(messages.filter(_.sender === "Dave").result)

// res0: Seq[Example.MessageTable#TableElementType] = Vector(
//   Message(Dave,Hello, HAL. Do you read me, HAL?,1),
//   Message(Dave,Open the pod bay doors, HAL.,3),
//   Message(Dave,What if I say 'Pretty please'?,5))
~~~

Here are some things that might go wrong:

Note that the parameter to `filter` is built using a triple-equals operator, `===`, not a regular `==`. If you use `==` you'll get an interesting compile error:

~~~ scala
exec(messages.filter(_.sender == "Dave").result)

//<console>:18: error: inferred type arguments [Boolean] do not conform to method filter's
//  type parameter bounds [T <: slick.lifted.Rep[_]]
//              exec(messages.filter(_.sender == "Dave").result)
//                            ^
//<console>:18: error: type mismatch;
// found   : Example.MessageTable => Boolean
// required: Example.MessageTable => T
//              exec(messages.filter(_.sender == "Dave").result)
//                                            ^
//<console>:18: error: Type T cannot be a query condition
//  (only Boolean, Rep[Boolean] and Rep[Option[Boolean]] are allowed
//              exec(messages.filter(_.sender == "Dave").result)
//                                  ^

~~~

The trick here is to notice that we're not actually trying to compare `_.sender` and `"Dave"`. A regular equality expression evaluates to a `Boolean`, whereas `===` builds an SQL expression of type `Rep[Boolean]` (Slick uses the `Rep` type to represent expressions over `Column`s as well as `Column`s themselves.). The error message is baffling when you first see it but makes sense once you understand what's going on.

Finally, if you forget to call `result`,
you'll end up with a compilation error as `exec` and the call it is wrapping `db.run` both expect actions:

~~~ scala
exec(messages.filter(_.sender === "Dave"))
<console>:18: error: type mismatch;
 found   : slick.lifted.Query[Example.MessageTable,Example.MessageTable#TableElementType,Seq]
    (which expands to)  slick.lifted.Query[Example.MessageTable,Example.Message,Seq]
 required: slick.driver.H2Driver.api.DBIO[?]
    (which expands to)  slick.dbio.DBIOAction[?,slick.dbio.NoStream,slick.dbio.Effect.All]
              exec(messages.filter(_.sender === "Dave"))
                                  ^
~~~

`Query` types tend to be verbose, which can be distracting from the actual cause of the problem (which is that we're not expecting a `Query` object at all). We will discuss `Query` types in more detail next chapter.
</div>
