# Basics

## Orientation

Slick is a Scala library for accessing relational databases. The code you write with Slick looks a lot like code you'd write using the Scala collections library. You can treat a query like a collection and `map` and `filter` it, or use a for comprehension. This is how we'll be working with Slick for the majority of this text.

Your queries are type safe, meaning the compiler will spot some kinds of mistake you might make. A further benefit is that your queries _compose_, allowing you to build up expressions to run against the database.

However, if that's not your style, you'll be happy to know that Slick supports _plain SQL queries_. These look a lot like SQL embedded in your Scala code. We show this style in **chapter or section TODO**.

Aside from querying, Slick of course deals with database connections, transactions, schema, foreign keys, auto incrementing fields and all the things you might expect from any database library. You can even drop right down below Slick to the level of dealing with Java's JDBC concepts, if that's something you're familiar with and find you need.

We will explain what all these phrases mean and how they work in practice as we go.

<div class="callout callout-info">
**Slick isn't an ORM**

If you've used database libraries such as _Hibernate_ or _Active Record_ you might expect Slick to be an Object-Relational Mapping (ORM) tool. It's not. And it's best not to try to think of Slick in that way.

Instead, think of Slick in terms of being closer to the concepts of the database itself: rows and columns. We're not going to argue the pros and cons of ORMs here, but if this is an area that interests you, take a look at ["Coming from ORM to Slick"][link-ref-orm].

If you've not familiar with ORMs, congratulations. You already have one less thing to worry about!
</div>


## The Chat Example

The aim of this first chapter is to introduce core concepts, and to get you up and running with Slick.

We'll be using an example of a chat application here and in the rest of the book. Think of it as the database behind a _Slack_, _Flowdock_, or an _IRC_ application. It will have users, messages, and rooms. These will be modeled as tables, relationships between tables, and various kinds of queries to run across the tables.

The database will end up looking like this:

**TODO: Insert diagram**

However, for now, we're going to start just with a table for messages:

**TODO: Insert table picture, possibly**


## Getting Started

All the examples in this book will be using the [H2][link-h2-home] database. We've picked H2 because there's nothing to install. In other words, we can get on with writing our Scala application immediately.

You might prefer to use _MySQL_, or _PostgreSQL_, or some other database---and you can. At the end of this chapter we'll point you at the changes you'll need to make to work with other databases. But stick with H2 for at least this first chapter, so you can get confidence using Slick without running into database-specific complications.


### SBT Build File

We're going to see how to model this table in Slick, connect to it, insert data, and query it. To do this we'll need a Scala project.

We'll create a regular Scala SBT project and reference the Slick dependencies.  If you don't have SBT installed, follow the instructions at the [scala-sbt site][link-sbt].

Here's the build script, _build.sbt_, we'll be using:

~~~ scala
name := "essential-slick-chapter-01"

version := "1.0"

scalaVersion := "2.11.5"

libraryDependencies ++= Seq(
  "com.typesafe.slick" %% "slick"           % "2.1.0",
  "com.h2database"      % "h2"              % "1.4.185",
  "ch.qos.logback"      % "logback-classic" % "1.1.2",
  "joda-time"           % "joda-time"       % "2.6",
  "org.joda"            % "joda-convert"    % "1.2")
~~~

This file declares the minimum dependencies needed:

- Slick itself;
- the database driver for H2; and
- a logging library, which Slick requires for its internal debug logging.

In addition we're using JodaTime, which we think is a great library for working with dates and times on the Java Virtual Machine.

We'll run this script later in this chapter.

<div class="callout callout-info">
  **Download the Code for this Book**

  If you don't want to type in the code for the next few section we have a [GitHub project][link-example] containing the build file, directory structure, and Scala source files.

  You can download a ZIP file with all the code in it, or cloned it as you would any other Git project. Once you have the code downloaded, look in the _chapter-01_ folder.
</div>


### The Code

The Scala code we will end up with in this chapter is as follows. You're not expected to understand this yet, but you may find you get the gist:

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

Before we run this code we are going to walk through the parts and outline the concepts.


### Representing a Table and Row

Slick models tables with classes, and models rows using a variety of data structures. For now we're going to focus on using case classes to model rows.

The case class below represents a single row of the `message` table, which is constructed from
four columns: the `sender` of the message, the `content` of the message, the time it was sent,`ts` and a unique `id`:

~~~ scala
final case class Message(sender: String, content: String, ts: DateTime, id: Long = 0L)
~~~

We combine this with the representation of a table. We're declaring the class as a `Table[Message]`:

~~~ scala
final class MessageTable(tag: Tag) extends Table[Message](tag, "message") {
  def id      = column[Long]("id", O.PrimaryKey, O.AutoInc)
  def sender  = column[String]("sender")
  def content = column[String]("content")
  def ts      = column[DateTime]("ts")
  def * = (sender, content, ts, id) <> (Message.tupled, Message.unapply)
}
~~~

`MessageTable` defines columns and constraints on those columns. These are mostly easy to read. For example, `id` is a column of `Long` values, which is the primary key and auto-increments.

The mysterious `*` is the _default projection_, which is what you'll get back from a query on the table by default. In this example we are mapping the data into and out of the `Message` case class using the `<>` operator that Slick provides.

Don't worry to much about what is going on here with methods such as `*`, `tupled`, and `unapply`, as we'll be looking at these in detail at the beginning of the next chapter.

The `tag` on the table is not something we have to supply when using the table. Slick takes care of that. Its purpose is to allow Slick to manage multiple uses of the table in a single query.

The last part of the code is a hook to access, persist, and alter data. This is achieved via the `TableQuery` instance:

~~~ scala
lazy val messages = TableQuery[MessageTable]
~~~

There's plenty going on in these three short code snippets. In particular there are three concepts being introduced:

- the representation of a row of data, as a case class called `Message`;
- the schema for a table, as the class `MessageTable`; and
- a table query, `messages`, which is the entry point for manipulating the table.

If you're a fan of terminology, know that this is the _lifted embedded_ approach to Slick.  It is the standard, non-experimental, way to work with Slick.


### Custom Column Mappings

We want to work with types have have meaning to our application. This means moving data from the simple types the database uses into something else. We've already seen one aspect of this where the column values for `id`, `sender`, `content`, and `ts` fields are mapped into a row representation of `Message`.

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

Slick DDL supports `create` and `drop`. This is useful working with in memory databases, as we are doing in this chapter, and as we will when we look at testing in chapter **TODO**.  You're unlikely to use Slicks DLL to manage schema migrations, as they relatively simple. We will look at other ways to deal with schema migrations in chapter **TODO**.


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

As with inserts, queried look as though we are working with Scala collection. For instance, the query below will return all messages from the user `HAL`:

~~~ scala
val halSays = for {
  message <- messages
  if message.sender === "HAL"
} yield message
~~~

This is _not_ executing a query. This is important, as it allows us to compose queries and pass queries around without holding open a database connection. The type of `halSays` is `Query[MessageTable, Message, Seq]`, and `Query` defines various `Query => Query`-style methods for this purpose.

As for comprehensions are sugar for `map`, `filter`, and related methods, this query can be re-written as:

~~~ scala
val halSays = messages.filter(_.sender === "HAL")
~~~

Which style you use is a matter of your circumstance and team preference.

Note also that we use triple equals `===` and not `==` in the for comprehension. The `===` is Slicks way of inserting the SQL `=` operator in here, rather than the Scala `equals` check. But aside from that, the query looks just the same as the code you'd write to work with any Scala collection.

The `===` is the only special case to notice.  Other operators, if defined for the type you're working with, behave as you expect. For example, we can use `<`...

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

<div class="callout callout-info">
  **JDBC**

  If you don't have a background working with Java, you may not have heard of
  Java Database Connectivity (JDBC).  It's a specification for accessing databases in a vendor
  neutral way. That is, it aims to be independent of the specific database you are connecting to.

  The specification is mirrored by a library implemented for each database you want to connect to. This library is called  the _JDBC driver_.

  JDBC works with _connection strings_, which are URLs for telling the driver where your database is, and
  providing connection details (such as a username and password, perhaps).
</div>

~~~ scala
import scala.slick.driver.H2Driver.simple._

def db = Database.forURL("jdbc:h2:mem:chapter01", driver="org.h2.Driver")

db.withSession {
  implicit session =>
    val result = halSays.run
  }
}
~~~

Each database product (H2, Oracle, PostgresSQL, and so on) has a different take on how queries should be constructed, how data should be represented, and what capabilities are implemented. This is abstracted by the Slick _driver_.  We import the right driver for the database we are using.

With that import done we set up our database connection, `db`, by providing `Database` with a JDBC connection string, and the class name of the JDBC driver being used.  Yes, there are two kinds of _driver_ being used: Slick's abstraction is called a driver; and it uses a Java JDBC _driver_ too.

From our database connection we can obtain a session. Sessions are required by Slick methods that need to actually go and communicate with the database.  Typically they are marked as `implicit` parameters, meaning you do not manually supply the parameter if it is marked as `implicit`.  We're doing this
in the code sample above.

With a session we can execute our query. There are a number of calls you can make on a query: get the `first` result, get an `interator`, `execute` and ignore the results. There are others, and we will look at these in detail later, but for now we're using `run`, which will return the results of the query.


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

So far we have been returning `Message` classes or counts.  Select all the messages in the database, but return just their contents.  Check what SQL would be executed for this query.

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

There are three results: "_Do_ you read me", "Open the pod bay _do_ors", and "I'm afraid I can't _do_ that".
</div>



## Using Different Database Products

<div class="callout callout-info">
As mentioned during the introduction H2 is used throughout the book for examples. However Slick also supports PostgreSQL, MySQL, Derby, SQLite, and Microsoft Access.

To work with DB2, SQL Server or Oracle you need a commercial license. These are the closed source _Slick Drivers_ known as the _Slick Extensions_.
</div>

If you want to use a different database for the exercises in the book,
you will need to make the following changes.
Each chapter uses it's own database ---
so these steps will need to be applied for each chapter.

Ensure that:

 * a database is available with the correct name,
 * the `build.sbt` file has the correct dependency,
 * the correct JDBC driver is referenced in the code,
 * the correct Slick driver is used.

### PostgreSQL

If it is not currently installed, it can be downloaded from the [PostgreSQL][link-postgres-download] website.

#### Create a database

Create a database named `chapter-01` with user `essential`. This will be used for all examples and can be created with the following:

~~~ sql
CREATE DATABASE "chapter-01" WITH ENCODING 'UTF8';
CREATE USER "essential" WITH PASSWORD 'trustno1';
GRANT ALL ON DATABASE "chapter-01" TO essential;
~~~

Confirm the database has been created and can be accessed:

~~~ bash
$ psql -d chapter-01 essential
~~~

#### Update `build.sbt` dependencies

Replace `"com.h2database" % "h2" % "1.4.185"` with `"org.postgresql" % "postgresql" % "9.3-1100-jdbc41"`,
then reload the project using `reload`.

Don't forget to regenerate any IDE project files.

####  Update JDBC references

Replace `Database.forURL` parameters with `"jdbc:postgresql:chapter-01", user="essential", password="trustno1", driver="org.postgresql.Driver"`.

####  Update Slick driver

Change the import from `import scala.slick.driver.H2Driver.simple._` to
`import scala.slick.driver.PostgresDriver.simple._`.

### MySQL

If it is not currently installed, it can be downloaded from the [MySQL][link-mysql-download] website.

#### Create a database

Create a database named `chapter-01` with user `essential`. This will be used for all examples and can be created with the following:

~~~ sql
CREATE USER 'essential'@'localhost' IDENTIFIED BY 'trustno1';
CREATE DATABASE `chapter-01` CHARACTER SET utf8 COLLATE utf8_bin;
GRANT ALL ON `chapter-01`.* TO 'essential'@'localhost';
flush privileges;
~~~

Confirm the database has been created and can be accessed:

~~~ bash
$mysql -u chapter-01 essential -p
~~~

#### Update `build.sbt` dependencies

Replace `"com.h2database" % "h2" % "1.4.185"` with `"mysql" % "mysql-connector-java" % "5.1.34"`,
then reload the project using `reload`.

Don't forget to regenerate any IDE project files.

####  Update JDBC driver references

Replace `Database.forURL` parameters with `"jdbc:mysql://localhost:3306/chapter-01&useUnicode=true&amp;characterEncoding=UTF-8&amp;autoReconnect=true", user="essential", password="trustno1", driver="com.mysql.jdbc.Driver"`.

#### Update Slick driver

Change the import from `import scala.slick.driver.H2Driver.simple._` to
`import scala.slick.driver.MySQLDriver.simple._`.

## Take Home Points

Slick models a database using:

* Scala types, such as case classes, for rows;
* `Table[T]` classes for the table schema; and
* `TableQuery[T]` for the table itself.

Slick will map column values to and from the database, and we can teach slick about our own types with custom mappings.

Queries and inserts look much like operations on Scala collections.

Session are:

* Required when running a query, insert, or schema change; but
* Not required to construct and compose queries.

In the next chapter we will look deleting and updating data, and in more depth on inserting data.



