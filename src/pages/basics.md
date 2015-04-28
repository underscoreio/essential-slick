# Basics

## Orientation

Slick is a Scala library for accessing relational databases. The code you write with Slick looks a lot like code you'd write using the Scala collections library. You can treat a query like a collection and `map` and `filter` it, or use it in a for comprehension. This is how we'll be working with Slick for the majority of this text.

Your queries are type safe, meaning the compiler will spot some kinds of mistake you might make. A further benefit is that your queries _compose_, allowing you to build up expressions to run against the database.

However, if that's not your style, you'll be happy to know that Slick supports _plain SQL queries_. These look a lot like SQL embedded in your Scala code. We show this style in [Plain SQL](#PlainSQL).



Aside from querying, Slick helps manage database connections, transactions, schema, foreign keys, auto incrementing fields and all the things you might expect from any database library. You can even drop down below Slick to deal with JDBC directly, if that's something you're familiar with and find you need.

<div class="callout callout-info">
**Slick isn't an ORM**

If you've used other database libraries such as [Hibernate][link-hibernate] or [Active Record][link-active-record], you might expect Slick to be an _Object-Relational Mapping (ORM)_ tool. It is not, and it's best not to think of Slick in this way.

ORMs attempt to map object standard oriented data models onto relational database backends. By contrast, Slick provides a more database-like set of tools such as queries, rows and columns. We're not going to argue the pros and cons of ORMs here, but if this is an area that interests you, take a look at ["Coming from ORM to Slick"][link-ref-orm].

If you aren't familiar with ORMs, congratulations. You already have one less thing to worry about!
</div>

## The Chat Example

The aim of this first chapter is to introduce core concepts and get you up and running with Slick.

We'll be using an example of a chat application here and in the rest of the book. Think of it as the database behind a _Slack_, _Flowdock_, or _IRC_ application. It will have users, messages, and rooms. These will be modeled as tables, relationships between tables, and various kinds of queries to run across the tables.

For now, though, we're going to start with a single table for storing messages.


## Getting Started

All of the examples in this book will use the [H2][link-h2-home] database, which is written in Java and runs along-side our application code as a simple library. We've picked H2 because there are no external software dependencies to install. In other words, we can forego any system administration and get on with writing Scala code immediately.

You might prefer to use _MySQL_, _PostgreSQL_, or some other database---and you can. In [Appendix A](#altdbs) we'll point you at the changes you'll need to make to work with other databases. However, we recommend you stick with H2 for at least this first chapter, so you can get confidence using Slick without running into database-specific complications.

<div class="callout callout-info">
**Download the Code for this Book**

If you don't want to type in the code for the next few section we have a [GitHub project][link-example] containing the build file, directory structure, and Scala source files.

You can download a ZIP file with all the code in it, or clone it as you would any other Git project. Once you have the code downloaded, look in the _chapter-01_ folder.
</div>


### SBT Build File

We're going to see how to model a messages table in Slick, connect to it, insert data, and query it. To do this we'll need a Scala project.

We'll create a regular project using the [Scala Build Tool (SBT)][link-sbt]. If you don't have SBT installed, follow the instructions at the [scala-sbt site][link-sbt]. Here's the _build.sbt_ file we'll be using:

~~~ scala
name := "essential-slick-chapter-01"

version := "1.0"

scalaVersion := "2.11.6"

libraryDependencies ++= Seq(
  "com.typesafe.slick" %% "slick"           % "2.1.0",
  "com.h2database"      % "h2"              % "1.4.185",
  "ch.qos.logback"      % "logback-classic" % "1.1.2",
  "joda-time"           % "joda-time"       % "2.6",
  "org.joda"            % "joda-convert"    % "1.2")
~~~

This file declares the minimum dependencies we require:

- Slick itself;
- the H2 database; and
- a logging library, which Slick requires for debug logging.

In addition we're using [Joda Time][link-joda-time], which is a great library for working with dates and times.


### The Code

The Scala code we will end up with in this chapter is as follows. You don't need to understand all of this yet---we'll go through everything in detail later on---but you may find you get the gist:

~~~ scala
package chapter01

import scala.slick.driver.H2Driver.simple._
import java.sql.Timestamp
import org.joda.time.DateTime
import org.joda.time.DateTimeZone.UTC

object Example extends App {

  // Custom column mapping:
  implicit val jodaDateTimeType =
    MappedColumnType.base[DateTime, Timestamp](
      dt => new Timestamp(dt.getMillis),
      ts => new DateTime(ts.getTime, UTC))

  // Row representation:
  final case class Message(
    sender: String,
    content: String,
    ts: DateTime,
    id: Long = 0L)

  // Schema:
  final class MessageTable(tag: Tag)
      extends Table[Message](tag, "message") {
    def id      = column[Long]("id",
                    O.PrimaryKey, O.AutoInc)
    def sender  = column[String]("sender")
    def content = column[String]("content")
    def ts      = column[DateTime]("ts")
    def * = (sender, content, ts, id) <>
              (Message.tupled, Message.unapply)
  }

  // Table:
  lazy val messages = TableQuery[MessageTable]

  // Our first query:
  val halSays = for {
    message <- messages
    if message.sender === "HAL"
  } yield message

  // Database connection details:
  def db = Database.forURL(
    "jdbc:h2:mem:chapter01",
    driver="org.h2.Driver")

  db.withSession { implicit session =>
    // Create the table:
    messages.ddl.create

    // Insert the conversation,
    // which took place in Feb, 2001:
    val start = new DateTime(2001, 2, 17, 10, 22, 50)

    messages ++= Seq(
      Message("Dave", "Hello, HAL. Do you read me, HAL?",
        start),
      Message("HAL", "Affirmative, Dave. I read you.",
        start plusSeconds 2),
      Message("Dave", "Open the pod bay doors, HAL.",
        start plusSeconds 4),
      Message("HAL", "I'm sorry, Dave. I'm afraid I can't do that.",
        start plusSeconds 6)
    )

    // Run the query:
    println(halSays.run)
  }
}
~~~

Let's look at the concepts in this code before we run it.


### Representing a Table and Row

Slick models database tables with instances of the `Table` trait, and rows using a variety of data structures. In this example we're modelling rows using a natural Scala representation--- a case class, `Message`.

The `Message` case class represents a single row of the `message` table, which is constructed from
four columns: the `sender` of the message, the `content` of the message, the time it was sent,`ts` and a unique `id`. This is the class we use to hold data in Scala---it has very little to do with the database itself:

~~~ scala
final case class Message(sender: String, content: String, ts: DateTime, id: Long = 0L)
~~~

In addition to `Message` we also have `MessageTable`, which tells Slick how to translate between the `"messages"` table at the database level and the `Message` class in our Scala application:

~~~ scala
final class MessageTable(tag: Tag)
    extends Table[Message](tag, "message") {

  def id      = column[Long]("id",
                  O.PrimaryKey, O.AutoInc)
  def sender  = column[String]("sender")
  def content = column[String]("content")
  def ts      = column[DateTime]("ts")

  def * = (sender, content, ts, id) <>
            (Message.tupled, Message.unapply)
}
~~~

`MessageTable` defines four columns: `id`, `sender`, `content`, and `ts`. It also defines the types of those columns and any constraints on them at the database level. For example, `id` is a column of `Long` values, which is the primary key for the table and auto-increments.

The mysterious `*` is the _default projection_, which uses Slick's `<>` method to define a mapping between the four database columns and the four fields of `Message`. This dictates the data type we'll get back when we query the `"messages"` table.
Don't worry too much about the details here---we'll go into methods such as `*`, `<>`, `tupled`, and `unapply` in more detail in Chapter 3.

The `tag` is an implementation detail that allows Slick to manage multiple uses of the table in a single query. Think of it like a table alias in SQL. We don't need to provide tags in our user code---slick takes case of them automatically.

After the definition of `MessageTable`, the last part of out code defines a `TableQuery`, which is our main entry point we use to access, persist, and alter data:

~~~ scala
lazy val messages = TableQuery[MessageTable]
~~~

There's plenty going on in these three short code snippets. In particular there are three concepts being introduced:

- a _representation of our data_---in this case a case class called `Message`;
- a `Table` object _representing the schema for a table_---in this case `MessageTable`; and
- a table query acting as _an entry point for querying the database_.

If you're a fan of terminology, know that this is the _lifted embedded_ approach to Slick.  It is the standard, non-experimental, way to work with Slick.


### Custom Column Mappings

We want to work with types that have meaning to our application. This means moving data from the simple types the database uses into something else. We've already seen one aspect of this where the column values for `id`, `sender`, `content`, and `ts` fields are mapped into a row representation of `Message`.

At a level down from that, we can also control how our types are converted into column values.  For example, we're using [JodaTime][link-jodatime]'s `DateTime` class. Support for this is not built-in to Slick, but we want to show it here to illustrate how painless it is to map types to the database.

The mapping for JodaTime `DateTime` is:

~~~ scala
import java.sql.Timestamp
import org.joda.time.DateTime
import org.joda.time.DateTimeZone.UTC

implicit val jodaDateTimeType =
  MappedColumnType.base[DateTime, Timestamp](
    dt => new Timestamp(dt.getMillis),
    ts => new DateTime(ts.getTime, UTC)
  )
~~~

What we're providing here is two functions:

- one that takes a `DateTime` and turns it into a database-friend value, namely a `java.sql.Timestamp`; and
- another that does the reverse, taking a database value and turning it into a `DataTime`.

Using the Slick `MappedColumnType.base` call enables this machinery, which is marked as `implicit` so the Scala compiler can invoke it when we mention a `DateTime`.

This is something we will emphasis and encourage you to use in your applications: work with meaningful types in your code, and let Slick take care of the mechanics of how those types are turned into database values.


### Creating the Table in the Database

Having modelled the table in Scala, we can ask Slick to create the table in the database:

~~~ scala
messages.ddl.create
~~~

DDL stands for _data definition language_ and is standard part of SQL. The DDL applies to the structure of tables, columns and other aspects of the schema, as opposed to the actual data held in those structures.

For H2, Slick will execute the create table statement you might expect:

~~~ sql
create table "message" (
  "sender"  VARCHAR NOT NULL,
  "content" VARCHAR NOT NULL,
  "ts"      TIMESTAMP NOT NULL,
  "id"      BIGINT GENERATED BY DEFAULT AS IDENTITY(START WITH 1) NOT NULL PRIMARY KEY
)
~~~

Slick DDL supports `create` and `drop`. This is useful working with in memory databases, as we are doing in this chapter. You're unlikely to use Slick's DLL to manage schema migrations, as they are relatively simple.

### Inserting Data

Inserting rows into the table looks just like adding elements to a collection:

~~~ scala
messages ++= Seq(
  Message("Dave", "Hello, HAL. Do you read me, HAL?",             start),
  Message("HAL",  "Affirmative, Dave. I read you.",               start plusSeconds 2),
  Message("Dave", "Open the pod bay doors, HAL.",                 start plusSeconds 4),
  Message("HAL",  "I'm sorry, Dave. I'm afraid I can't do that.", start plusSeconds 6)
)
~~~

This will create four new rows in the database.

Both creating the table and inserting data will require a connection to the database, which we will look at in a moment.  But first, let's see what a query looks like.


### Querying

As with inserts, queries look as though we are working with Scala collection. For instance, the query below will return all messages from the user `HAL`:

~~~ scala
val halSays = for {
  message <- messages
  if message.sender === "HAL"
} yield message
~~~

This is _not_ executing a query. This is important, as it allows us to compose queries and pass queries around without holding open a database connection. The type of `halSays` is `Query[MessageTable, Message, Seq]`, and `Query` defines various `Query => Query`-style methods for composing queries.

As for comprehensions are sugar for `map`, `filter`, and related methods, this query can be re-written as:

~~~ scala
val halSays = messages.filter(_.sender === "HAL")
~~~

Which style you use is a matter of your circumstance and team preference.

Note also that we use triple equals `===` and not `==` in the query. The `===` is Slicks way of inserting the SQL `=` operator in here, rather than the Scala `equals` check. But aside from that, the query looks just the same as the code you'd write to work with any Scala collection.

The `===`and corresponding `=!=` are the only special cases.  Other operators, if defined for the type you're working with, behave as you expect. For example, we can use less than:

~~~ scala
val now = new DateTime(2001,2,17, 10,22,54)
val recentMessages = halSays.filter(_.ts < now)
~~~

...and when we `run` that the SQL will be something like:

~~~ sql
select "sender", "content", "ts", "id" from "message" where
  ("sender" = 'HAL') and
  ("ts" < '2001-02-17 10:22:54.0')
~~~

Now that we have a few queries, we should run them.


### Database Connections and Sessions

Queries are executed in the scope of a _session_. You need a session to be able to run a query, but you do not need one to construct a query.

A session is our connection to the database, and we can obtain one from Slick's `Database` object. We can do that from a configuration file, and Java's `DataSource` or JNDI technologies.  For this introduction, we're going to use a JDBC URL:

~~~ scala
import scala.slick.driver.H2Driver.simple._

def db = Database.forURL("jdbc:h2:mem:chapter01", driver="org.h2.Driver")

db.withSession {
  implicit session =>
    val result = halSays.run
  }
}
~~~

<div class="callout callout-info">
  **JDBC**

  If you don't have a background working with Java, you may not have heard of
  Java Database Connectivity (JDBC).  It's a specification for accessing databases in a vendor
  neutral way. That is, it aims to be independent of the specific database you are connecting to.

  The specification is mirrored by a library implemented for each database you want to connect to. This library is called  the _JDBC driver_.

  JDBC works with _connection strings_, which are URLs for telling the driver where your database is, and
  providing connection details (such as a username and password, perhaps).
</div>

Each database product (H2, Oracle, PostgresSQL, and so on) has a different take on how queries should be constructed, how data should be represented, and what capabilities are implemented. This is abstracted by the Slick _driver_.  We import the right driver for the database we are using.

With that import done we set up our database connection, `db`, by providing `Database` with a JDBC connection string, and the class name of the JDBC driver being used.  Yes, there are two kinds of _driver_ being used: Slick's abstraction is called a driver; and it uses a JDBC driver too.

From our database connection we can obtain a session. Sessions are required by Slick methods that need to actually go and communicate with the database.  Typically the session parameter is marked as `implicit`, meaning you do not have to manually supply the parameter.  We're doing this
in the code sample above as `run` requires a session, and the session it uses is the one we defined as implicit.

With a session we can execute our query. There are a number of calls you can make on a query, as listed in the table below.

------------------------------------------------------------------
Method          Executes the query and will:
-----------     --------------------------------------------------
 `execute`      Ignore the result.

 `first`        Return the first result, or throw an exception if there is no result.

 `firstOption`  Return `Some[T]` for the first result; `None` if there is no result.

 `list`         Return a fully populated `List[T]` of the results.

 `iterator`     Provides an iterator over the results.

 `run`          Acts like `first` for queries for a value, but something like `list` for a collection
                of values.
-----------     --------------------------------------------------

: A Selection of Statement Invokers

For now we're using `run`, which will return the results of the query as a collection.

### Putting it All Together

Our complete Scala project becomes:

~~~ scala
package chapter01

import scala.slick.driver.H2Driver.simple._
import java.sql.Timestamp
import org.joda.time.DateTime
import org.joda.time.DateTimeZone.UTC

object Example extends App {

  // Custom column mapping:
  implicit val jodaDateTimeType =
    MappedColumnType.base[DateTime, Timestamp](
      dt => new Timestamp(dt.getMillis),
      ts => new DateTime(ts.getTime, UTC)
    )

  // Row representation:
  final case class Message(sender: String, content: String, ts: DateTime, id: Long = 0L)

  // Schema:
  final class MessageTable(tag: Tag) extends Table[Message](tag, "message") {
    def id      = column[Long]("id", O.PrimaryKey, O.AutoInc)
    def sender  = column[String]("sender")
    def content = column[String]("content")
    def ts      = column[DateTime]("ts")
    def * = (sender, content, ts, id) <> (Message.tupled, Message.unapply)
  }

  // Table:
  lazy val messages = TableQuery[MessageTable]

  // Our first query:
  val halSays = for {
    message <- messages
    if message.sender === "HAL"
  } yield message

  // Database connection details:
  def db = Database.forURL("jdbc:h2:mem:chapter01", driver="org.h2.Driver")

  // Query execution:
  db.withSession {
    implicit session =>

      // Create the table:
      messages.ddl.create

      // Insert the conversation, which took place in Feb, 2001:
      val start = new DateTime(2001,2,17, 10,22,50)

      messages ++= Seq(
        Message("Dave", "Hello, HAL. Do you read me, HAL?",             start),
        Message("HAL",  "Affirmative, Dave. I read you.",               start plusSeconds 2),
        Message("Dave", "Open the pod bay doors, HAL.",                 start plusSeconds 4),
        Message("HAL",  "I'm sorry, Dave. I'm afraid I can't do that.", start plusSeconds 6)
      )

      // Run the query:
      println(halSays.run)
  }
}
~~~

This is all the code from the chapter so far in a single file. It's a Scala application, so you can run it from your IDE or from SBT:

~~~ bash
$ cd chapter-01
$ sbt run
~~~

The output will be:

~~~
Vector(
  Message(HAL,Affirmative, Dave. I read you.,2001-02-17T10:22:52.000Z,2),
  Message(HAL,I'm sorry, Dave. I'm afraid I can't do that.,2001-02-17T10:22:56.000Z,4) )
~~~

You have now built and run a simple Slick application.


### Exercises

We want to make sure you have your environment set up, and can experiment with Slick.  If you've not already done so, try out the above code.  In the [example project][link-example] the code is in _main.scala_ in the folder _chapter-01_.

Once you've done that, work through the exercises below.  An easy way to try things out is to use  _triggered execution_ with SBT:

~~~ bash
$ cd example-01
$ sbt
> ~run
~~~

That `~run` will monitor the project for changes, and when a change is seen, the _main.scala_ program will be compiled and run. This means you can edit _main.scala_ and then look in your terminal window to see the output.


#### Count the Messages

How would you count the number of messages? Hint: in the Scala collections the method `length` gives you the size of the collection.

<div class="solution">
~~~ scala
val results = halSays.length.run
~~~

You could also use `size`, which is an alias for `length`.
</div>

#### Selecting a Message

Using a for comprehension, select the message with the id of 1.  What happens if you try to find a message with an id of 999?

Hint: our IDs are `Long`s. Adding `L` after a number in Scala, such as `99L`, makes it a long.

<div class="solution">
~~~ scala
val query = for {
  message <- messages if message.id === 1L
} yield message

val results = query.run
~~~

Asking for `999`, when there is no row with that ID, will give back an empty collection.
</div>

#### One Liners

Re-write the query from the last exercise to not use a for comprehension.  Which style do you prefer? Why?

<div class="solution">
~~~ scala
val results = messages.filter(_.id === 1L).run
~~~
</div>

#### Checking the SQL

Calling the `selectStatement` method on a query will give you the SQL to be executed.  Apply that to the last exercise. What query is reported? What does this tell you about the way `filter` has been mapped to SQL?

<div class="solution">
The code you need to run is:

~~~ scala
val sql = messages.filter(_.id === 1L).selectStatement
println(sql)
~~~

The result will be something like:

~~~ SQL
select x2."id", x2."sender", x2."content", x2."ts" from "message" x2 where x2."id" = 1
~~~

From this we see how `filter` corresponds to a SQL `where` clause.
</div>


#### Selecting Columns

So far we have been returning `Message` classes or counts.  Select all the messages in the database, but return just their contents.  Hint: think of messages as a collection and what you would do to a collection to just get back a single field of a case class.

Check what SQL would be executed for this query.

<div class="solution">
~~~ scala
val query = messages.map(_.content)
println(s"The query is:  ${query.selectStatement}")
println(s"The result is: ${query.run}")
~~~

You could have also said:

~~~ scala
val query = for { message <- messages } yield message.content
~~~

The query will just return the `content` column from the database:

~~~ SQL
select x2."content" from "message" x2
~~~
</div>

#### First Result

The methods `first` and `firstOption` are useful alternatives to `run`. Find the first message that HAL sent.  What happens if you use `first` to find a message from "Alice" (note that Alice has sent no messages).

<div class="solution">
~~~ scala
val msg1 = messages.filter(_.sender === "HAL").map(_.content).first
println(msg1)
~~~

You should get "Affirmative, Dave. I read you."

For Alice, `first` will throw a run-time exception. Use `firstOption` instead.
</div>


#### The Start of Something

The method `startsWith` on a `String` tests to see if the string starts with a particular sequence of characters. Slick also implements this for string columns. Find the message that starts with "Open". How is that query implemented in SQL?

<div class="solution">
~~~ scala
messages.filter(_.content startsWith "Open")
~~~

The query is implemented in terms of `LIKE`:

~~~ SQL
select x2."id", x2."sender", x2."content", x2."ts" from "message" x2 where x2."content" like 'Open%' escape '^'
~~~
</div>


#### Liking

Slick implements the method `like`. Find all the messages with "do" in their content. Can you make this case insensitive?

<div class="solution">
The query is:

~~~ scala
messages.filter(_.content.toLowerCase like "%do%")
~~~

The SQL will turn out as:

~~~ SQL
select x2."id", x2."sender", x2."content", x2."ts" from "message" x2 where lower(x2."content") like '%do%'
~~~

There are three results: "_Do_ you read me", "Open the pod bay *do*ors", and "I'm afraid I can't _do_ that".
</div>



## Take Home Points

Slick models a database using:

* Scala types, such as case classes, for rows;
* `Table[T]` classes for the table schema; and
* `TableQuery[T]` for the table itself.

Slick will map column values to and from the database, and we can teach Slick about our own types with custom mappings.

Queries and inserts look much like operations on Scala collections.

Session are:

* Required when running a query, insert, or schema change; but
* Not required to construct and compose queries.

In the next chapter we will look deleting and updating data, and in more depth on inserting data.



