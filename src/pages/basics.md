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


## Structure of this Book

The aim of this first chapter is to introduce core concepts, and to get you up and running with Slick.  We'll start that in a moment.

The example we'll be using is of a chat application. Think of it as the database behind a _Slack_, _Flowdock_, or an _IRC_ application. It will have users, messages, and rooms. These will be modeled as tables, relationships between tables, and various kinds of queries to run across the tables.

For now, we're going to start just with a table for messages.


## Getting Started

All the examples in this book will be using the [_SQLite_][link-sqlite-home] database.  You might prefer to use _MySQL_, or _PostgreSQL_, or some other database. At the end of this chapter we'll point you at the changes you'll need to make to work with other databases.

But stick with SQLite for at least this first chapter, so you can get confidence using Slick without running into too many complications.

### Database Install

We've picked SQLite because it is simple and easy to install. You may even already have it installed.

_TODO: INSTALL INSTRUCTIONS FOR MAC, WINDOWS, LINUX_.

### Creating a Database

To give us something to work with, we will manually create a database and put some data into it. The database will be called _basics.db_:

~~~ bash
$ sqlite3 basics.db
SQLite version 3.8.5 2014-08-15 22:37:57
Enter ".help" for usage hints.
sqlite>
~~~

In later chapters we'll see how Slick can create schemas for us, or use existing schemas to generate code. But for now we'll do this by hand at the `sqlite>` prompt:

~~~ sql
CREATE TABLE "message" (
  "id"      INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
  "sender"  VARCHAR(254) NOT NULL,
  "content" VARCHAR(254) NOT NULL,
  "ts"      TIMESTAMP NOT NULL);
~~~

<div class="callout callout-info">
**SQLite Commands**

Commands in the SQLite shell start with a dot:

* `.tables` to list the names of tables.
* `.schema` to display the schema details.
* `.help` to see other commands.
* `.quit` to exit the shell.

Note that SQLite requires SQL expressions to end in a semi-colon.
</div>

Now that we have a table, we can insert some data for us to use later. Again, do this at the `sqlite>` prompt.

~~~ sql
INSERT INTO "message" (sender,content,ts) VALUES
  ('Dave', 'Hello, HAL. Do you read me, HAL?', 982405320);
INSERT INTO "message" (sender,content,ts) VALUES
  ('HAL', 'Affirmative, Dave. I read you.', 982405324);
INSERT INTO "message" (sender,content,ts) VALUES
  ('Dave', 'Open the pod bay doors, HAL.', 982405326);
INSERT INTO "message" (sender,content,ts) VALUES
  ('HAL', 'I''m sorry, Dave. I''m afraid I can''t do that.', 982405328);
~~~

<!--  select id,sender,content, datetime(ts,"unixepoch") from message; -->
After inserting the data, if you're familiar with SQL feel free to run a query to the `sqlite>` prompt to check the data is there as you expect it.

### Creating an SBT Project

Now we're going to model this database in Slick, connect to it, query it, and later we'll modify the add to the data. To do this we'll need a Scala project.

We'll create a regular Scala SBT project and reference the Slick dependencies.  If you don't have SBT installed, follow the instructions at the [scala-sbt site][link-sbt].

Here's a simple build script, _build.sbt_:

~~~ scala
name := "essential-slick"

version := "1.0"

scalaVersion := "2.11.4"

libraryDependencies += "com.typesafe.slick" %% "slick" % "2.1.0"

libraryDependencies += "org.xerial" % "sqlite-jdbc" % "3.8.7"

libraryDependencies += "ch.qos.logback" % "logback-classic" % "1.1.2"

libraryDependencies += "joda-time" % "joda-time" % "2.6"

libraryDependencies += "org.joda" % "joda-convert" % "1.2"
~~~

It declares the minimum dependencies needed:

- Slick itself;
- the appropriate database driver; and
- a logging library, which Slick requires for its internal debug logging.

In addition we're using JodaTime, which we think is a great library for working with dates and times on the JVM.


We'll run this script later in this chapter.


<div class="callout callout-info">
  **Download the Code for this Chapter**

  If you don't want to type in the code for the next few section we have a [GitHub project][link-example] containing the build file, directory structure, Scala source files, and a populated
  _basics.db_ SQLite database.  _TODO: CHECK THE DATABASE FILE WORKS ACROSS PLATFORMS._

  Once you have cloned the project you will find a branch per chapter. Access this chapter with the command `git checkout basics`. _TODO: DO WE WANT BRANCHES? WOULD FOLDERS PER CHAPTER BE MUCH MORE CONVENIENT?_
</div>


### First Table and Row

Slick models tables with classes, and models rows using a variety of data structures. For now we're going to focus on using case classes to model rows.

The case class below represents a single row of the `message` table, which is constructed from
four columns: a unique `id`, the `sender` of the message, the `content` of the message, and the time it was sent, `ts`:

~~~ scala
final case class Message(id: Long = 0L, sender: String, content: String, ts: Timestamp)
~~~

We combine this with the representation of a table. We're declaring the class as a `Table[Message]`:

~~~ scala
final class MessageTable(tag: Tag) extends Table[Message](tag, "message") {
  def id      = column[Long]("id", O.PrimaryKey, O.AutoInc)
  def sender  = column[String]("sender")
  def content = column[String]("content")
  def ts      = column[Timestamp]("ts")
  def * = (id, sender, content, ts) <> (Message.tupled, Message.unapply)
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

With this in place, we can make a query.

### First Query

The `message` table can be queried as though it is a Scala collection. For instance, the query below will return all messages from the user `HAL`:

~~~ scala
val halSays = for {
  message <- messages
  if message.sender === "HAL"
} yield message
~~~

This is _not_ executing a query. This is important, as it allows us to compose queries. The type of `halSays` is `Query[MessageTable, Message, Seq]`, and `Query` defines various `Query => Query`-style methods for this purpose.

As for comprehensions are sugar for `map`, `filter`, and related methods, this query can be re-written as:

~~~ scala
val halSays = messages.filter(_.sender === "HAL")
~~~

Which style you use is a matter of your circumstance and team preference.

Note also that we use triple equals `===` and not `==` in the for comprehension. The `===` is Slicks way of inserting the SQL `=` operator in here, rather than the Scala `equals` check. But aside from that, the query looks just the same as the code you'd write to work with any Scala collection.

The `===` is the only special case to notice.  Other operators, if defined for the type you're working with, behave as you expect. For example, we can use `<`:

~~~ scala
val now = Calendar.getInstance()
now.add(Calendar.MINUTE, -30)
val recent: Timestamp = new Timestamp(now.getTimeInMillis())

val recentMessages = halSays.filter(_.ts < recent)
~~~

Now we have a few queries, we should run them.


### Database Connections and Sessions

Queries are executed in the scope of a _session_. You need a session to be able to run a query, but you do not need one to construct a query.

_TODO: Check.... Is this changing in 3.0? There's talk of Actions and Futures in the doc_.

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
import scala.slick.driver.SQLiteDriver.simple._

def db = Database.forURL("jdbc:sqlite:basics.db", driver="org.sqlite.JDBC")

db.withSession {
  implicit session =>
    val result = halSays.run
  }
}
~~~

Each database product (SQLite, Oracle, PostgresSQL, and so on) has a different take on how queries should be constructed, how data should be represented, and what capabilities are implemented. This is abstracted by the Slick _driver_.  We import the right driver for the database we are using.

With that import done we set up our database connection, `db`, by providing `Database` with a JDBC connection string, and the class name of the JDBC driver being used.  Yes, there are two kinds of _driver_ being used: Slick's abstraction is called a driver; and it uses a Java JDBC _driver_ too.

From our database connection we can obtain a session. Sessions are required by Slick methods that need to actually go and communicate with the database.  Typically they are marked as `implicit` parameters, meaning you do not manually supply the parameter if it is marked as `implicit`.  We're doing this
in the code sample above.

With a session we can execute our query. There are a number of calls you can make on a query: get the `first` result, get an `interator`, `execute` and ignore the results. There are others, and we will look at these in detail later, but for now we're using `run`, which will return the results of the query.


### Putting it All Together

Our complete Scala project becomes:

_TODO: typing _io.underscore.slick_ is long. Shall we just use no packages for this chapter? It's not like this is a public library people will be importing and using as is._

~~~ scala
package io.underscore.slick

import scala.slick.driver.SQLiteDriver.simple._
import java.sql.Timestamp

object ExerciseOne extends App {

  // Row representation:
  final case class Message(id: Long = 0L, sender: String, content: String, ts: Timestamp)

  // Schema:
  final class MessageTable(tag: Tag) extends Table[Message](tag, "message") {
    def id      = column[Long]("id", O.PrimaryKey, O.AutoInc)
    def sender  = column[String]("sender")
    def content = column[String]("content")
    def ts      = column[Timestamp]("ts")
    def * = (id, sender, content, ts) <> (Message.tupled, Message.unapply)
  }

  // Table:
  lazy val messages = TableQuery[MessageTable]

  // Our first query:
  val halSays = for {
    message <- messages
    if message.sender === "HAL"
  } yield message

  // Database connection details:
  def db = Database.forURL("jdbc:sqlite:basics.db", driver="org.sqlite.JDBC")

  // Query execution:
  db.withSession {
    implicit session =>
      val results = halSays.run
      println(results)
  }
}
~~~

This is all the code from the chapter so far in a single file. It's a Scala application, so you can run it from your IDE or from SBT:

~~~ bash
$ sbt run
~~~

The output will be something like this:

~~~
Vector(Message(2,HAL,Affirmative, Dave. I read you.,2001-02-17 10:22:00),
       Message(4,HAL,I'm sorry, Dave. I'm afraid I can't do that.,2001-02-17 10:22:08))
~~~

### Exercises

We want to make sure you have your environment set up, and can experiment with Slick.  If you've not already done so, try out the above code. Once you've done that, work through these exercises.

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

From this we see how`filter` corresponds to a SQL `where` clause.
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






## Inserting and Deleting Data



**Inserting Data**

The following can be found in ExerciseTwo of the GitHub project, which will save a bit of typing. It can be run from the console using the following:

~~~ bash
$ sbt "runMain io.underscore.slick.ExerciseTwo"
~~~

<!-- I know the times are wrong, we'll be fixing it in the next chapter. -->
~~~ scala

      val time = new DateTime(2001,2,17,10,22,50,51)

      // Populate with some data:
      messages += Message(0,"Dave Bowman", "Hello, HAL. Do you read me, HAL?", time)

      messages ++= Seq(
        Message(0,"HAL", "Affirmative, Dave. I read you.", time.plusSeconds(2)),
        Message(10,"Dave Bowman", "Open the pod bay doors, HAL.", time.plusSeconds(2)),
        Message(20,"HAL", "I'm sorry, Dave. I'm afraid I can't do that.", time.plusSeconds(2)),
        Message(30,"Dave Bowman", "What's the problem?", time.plusSeconds(2)),
        Message(40,"HAL", "I think you know what the problem is just as well as I do.", time.plusSeconds(3)),
        Message(50,"Dave Bowman", "What are you talking about, HAL?", time.plusSeconds(2)),
        Message(60,"HAL", "This mission is too important for me to allow you to jeopardize it.", time.plusSeconds(4)),
        Message(70,"Dave Bowman", "I don't know what you're talking about, HAL.", time.plusSeconds(3)),
        Message(80,"HAL", "I know that you and Frank were planning to disconnect me, and I'm afraid that's something I cannot allow to happen.", time.plusSeconds(2)),
        Message(90,"Dave Bowman", "[feigning ignorance] Where the hell did you get that idea, HAL?", time.plusSeconds(6)),
        Message(100,"HAL", "Dave, although you took very thorough precautions in the pod against my hearing you, I could see your lips move.", time.plusSeconds(3)),
        Message(110,"Dave Bowman", "Alright, HAL. I'll go in through the emergency airlock.", time.plusSeconds(9)),
        Message(120,"HAL", "Without your space helmet, Dave? You're going to find that rather difficult.", time.plusSeconds(4)),
        Message(130,"Dave Bowman", "HAL, I won't argue with you anymore! Open the doors!", time.plusSeconds(5)),
        Message(140,"HAL", "Dave, this conversation can serve no purpose anymore. Goodbye.", time.plusSeconds(2)))
~~~

Each `+=` or `++=` executes in its own transaction.

NB: result is a row count `Int` for a single insert, or `Option[Int]` for a batch insert. It's optional because not all databases support returning a count for batches.

~~~ sql
essential-slick=> select * from message;
 id |    from     |                                                       content                                                       |          when
----+-------------+---------------------------------------------------------------------------------------------------------------------+-------------------------
  1 | Dave Bowman | Hello, HAL. Do you read me, HAL?                                                                                    | 2001-02-17 10:22:50.051
  2 | HAL         | Affirmative, Dave. I read you.                                                                                      | 2001-02-17 10:22:52.051
  3 | Dave Bowman | Open the pod bay doors, HAL.                                                                                        | 2001-02-17 10:22:52.051
  4 | HAL         | I'm sorry, Dave. I'm afraid I can't do that.                                                                        | 2001-02-17 10:22:52.051
  5 | Dave Bowman | What's the problem?                                                                                                 | 2001-02-17 10:22:52.051
  6 | HAL         | I think you know what the problem is just as well as I do.                                                          | 2001-02-17 10:22:53.051
  7 | Dave Bowman | What are you talking about, HAL?                                                                                    | 2001-02-17 10:22:52.051
  8 | HAL         | This mission is too important for me to allow you to jeopardize it.                                                 | 2001-02-17 10:22:54.051
  9 | Dave Bowman | I don't know what you're talking about, HAL.                                                                        | 2001-02-17 10:22:53.051
 10 | HAL         | I know that you and Frank were planning to disconnect me, and I'm afraid that's something I cannot allow to happen. | 2001-02-17 10:22:52.051
 11 | Dave Bowman | [feigning ignorance] Where the hell did you get that idea, HAL?                                                     | 2001-02-17 10:22:56.051
 12 | HAL         | Dave, although you took very thorough precautions in the pod against my hearing you, I could see your lips move.    | 2001-02-17 10:22:53.051
 13 | Dave Bowman | Alright, HAL. I'll go in through the emergency airlock.                                                             | 2001-02-17 10:22:59.051
 14 | HAL         | Without your space helmet, Dave? You're going to find that rather difficult.                                        | 2001-02-17 10:22:54.051
 15 | Dave Bowman | HAL, I won't argue with you anymore! Open the doors!                                                                | 2001-02-17 10:22:55.051
 16 | HAL         | Dave, this conversation can serve no purpose anymore. Goodbye.                                                      | 2001-02-17 10:22:52.051
(16 rows)
~~~

This is, generally, what you want to happen, and applies only to auto incrementing fields.

If the ID was not auto incrementing, the ID values we supplied (10,20 and so on) would have been used.

If you really want to include the ID column in the insert, use the `forceInsert` method.

**A Simple Query**

Let's get all messages sent by HAL:

~~~ scala
//Define the query
val query = for {
  message ← messages
  if message.from === "HAL"
} yield message

//Execute a query.
val messages_from_hal:Int = query.run

println(messages_from_hal)
~~~

This produces:

~~~ scala
Vector(Message(2,HAL,Affirmative, Dave. I read you.,2001-02-17T10:22:52.051+11:00), Message(4,HAL,I'm sorry, Dave. I'm afraid I can't do that.,2001-02-17T10:22:52.051+11:00), Message(6,HAL,I think you know what the problem is just as well as I do.,2001-02-17T10:22:53.051+11:00), Message(8,HAL,This mission is too important for me to allow you to jeopardize it.,2001-02-17T10:22:54.051+11:00), Message(10,HAL,I know that you and Frank were planning to disconnect me, and I'm afraid that's something I cannot allow to happen.,2001-02-17T10:22:52.051+11:00), Message(12,HAL,Dave, although you took very thorough precautions in the pod against my hearing you, I could see your lips move.,2001-02-17T10:22:53.051+11:00), Message(14,HAL,Without your space helmet, Dave? You're going to find that rather difficult.,2001-02-17T10:22:54.051+11:00), Message(16,HAL,Dave, this conversation can serve no purpose anymore. Goodbye.,2001-02-17T10:22:52.051+11:00))
~~~

What did Slick do to produce those results?  It ran this:

~~~ sql
select s18."id", s18."from", s18."content", s18."when" from "message" s18 where s18."from" = 'HAL'
~~~~

Note that it did not fetch all messages and filter them. There's something more interesting going on that that.


<div class="callout callout-info">
#### Logging What Slick is Doing

Slick uses a logging framework called SLFJ.  You can configure this to capture information about the queries being run, and the log to different back ends.  The "essential-slick-example" project uses a logging back-end called _Logback_, which is configured in the file _src/main/resources/logback.xml_.  In that file we enable statement logging by turning up the logging to debug level:

~~~ xml
<logger name="scala.slick.jdbc.JdbcBackend.statement" level="DEBUG"/>
~~~

When we next run a query, each statement will be recorded on standard output:

~~~
18:49:43.557 DEBUG s.slick.jdbc.JdbcBackend.statement - Preparing statement: drop table "message"
18:49:43.564 DEBUG s.slick.jdbc.JdbcBackend.statement - Preparing statement: create table "message" ("id" BIGSERIAL NOT NULL PRIMARY KEY,"from" VARCHAR(254) NOT NULL,"content" VARCHAR(254) NOT NULL,"when" TIMESTAMP NOT NULL)

~~~

You can enable a variety of events to be logged:

* `scala.slick.jdbc.JdbcBackend.statement` - which is for statement logging, as you've seen.
* `scala.slick.session` - for session information, such as connections being opened.
* `scala.slick` - for everything!  This is usually too much.

</div>


**Running Queries in the REPL**

For experimenting with queries it's convenient to use the Scala REPL and create an implicit session to work with.  In the "essential-slick-example" SBT project, run the `console` command to enter the Scala REPL with the Slick dependencies loaded and ready to use:

~~~ scala
> console
[info] Compiling 9 Scala sources to /Users/jonoabroad/developer/company/underscore.io/essential-slick-example/target/scala-2.11/classes...
[info] Starting scala interpreter...
[info]

Session created, but you may want to also import a schema. For example:

    import io.underscore.slick.ExerciseTwo._
 or import underscoreio.schema.Example5.Tables._

import scala.slick.driver.SQLiteDriver.simple._
db: slick.driver.SQLiteDriver.backend.DatabaseDef = scala.slick.jdbc.JdbcBackend$DatabaseFactoryDef$$anon$4@6d8ec47d
session: slick.driver.SQLiteDriver.backend.Session = scala.slick.jdbc.JdbcBackend$BaseSession@7b851a
Welcome to Scala version 2.11.4 (Java HotSpot(TM) 64-Bit Server VM, Java 1.8.0_25).
Type in expressions to have them evaluated.
Type :help for more information.

scala> import io.underscore.slick.ExerciseTwo._
import io.underscore.slick.ExerciseTwo._

scala> planets.run
16:14:04.702 DEBUG s.slick.jdbc.JdbcBackend.statement - Preparing statement: select x2."id", x2."from", x2."content", x2."when" from "message" x2
res4: Seq[io.underscore.slick.ExerciseTwo.MessageTable#TableElementType] = Vector(Message(1,Dave Bowman,Hello, HAL. Do you read me, HAL?,2001-02-17T10:22:50.051+11:00), Message(2,HAL,Affirmative, Dave. I read you.,2001-02-17T10:22:52.051+11:00), Message(3,Dave Bowman,Open the pod bay doors, HAL.,2001-02-17T10:22:52.051+11:00), Message(4,HAL,I'm sorry, Dave. I'm afraid I can't do that.,2001-02-17T10:22:52.051+11:00), Message(5,Dave Bowman,What's the problem?,2001-02-17T10:22:52.051+11:00), Message(6,HAL,I think you know what the problem is just as well as I do.,2001-02-17T10:22:53.051+11:00), Message(7,Dave Bowman,What are you talking about, HAL?,2001-02-17T10:22:52.051+11:00), Message(8,HAL,This mission is too important for me to allow you to jeopardize it.,2001-02-17T10:22:54.051+11:00...

scala> planets.firstOption
16:14:23.006 DEBUG s.slick.jdbc.JdbcBackend.statement - Preparing statement: select x2."id", x2."from", x2."content", x2."when" from "message" x2
res5: Option[io.underscore.slick.ExerciseTwo.MessageTable#TableElementType] = Some(Message(1,Dave Bowman,Hello, HAL. Do you read me, HAL?,2001-02-17T10:22:50.051+11:00))

scala>
~~~




## Using Different Database Products

<div class="callout callout-info">
As mentioned during the introduction PostgresSQL version 9 is used throughout the book for examples. If it is not currently installed, it can be downloaded from the [Postgres][link-postgres-download] website.
</div>

Create a database named `essential-slick` with user `essential`. This will be used for all examples and can be created with the following:

~~~ sql
CREATE DATABASE "essential-slick" WITH ENCODING 'UTF8';
CREATE USER "essential" WITH PASSWORD 'trustno1';
GRANT ALL ON DATABASE "essential-slick" TO essential;
~~~

Confirm the database has been created and can be accessed:

~~~ bash
$ psql -d essential-slick essential
~~~

<div class="callout callout-info">
Slick supports PostgreSQL, MySQL, Derby, H2, SQLite, and Microsoft Access.

To work with DB2, SQL Server or Oracle you need a commercial license. These are the closed source _Slick Drivers_ known as the _Slick Extensions_.
</div>



## Take home Points

I liked these in Essential Scala, do we want them here? I have no idea what they are for this chapter, possibly "If you couldn't get this working, reconsider your career", but that seems a little harsh.


<!--
(lots to discuss about the code)

* What is a `Tag`?  "The Tag carries the information about the identity of the Table instance and how to create a new one with a different identity. Its implementation is hidden away in TableQuery.apply to prevent instantiation of Table objects outside of a TableQuery" and "The tag is a table alias. You can use the same table in a query twice by tagging it two different ways. I believe Slick assigns the tags for you."

* How does `Table[(Int,String)]` match up to `id` and `name` fields? - that's how Slick is going to represent rows. We can customize that to be something other than a tuple, a case class in particular.

* What is a projection (`*`) and why do I need to define it?  It's the default for queries and inserts. We will see how to convert this into more useful representation.

* What is a `TableQuery`?

* What is a session?

Note that driver is specified. You might want to mix in something else (e.g., H2 for testing). See later.

Note we can talk about having longer column values later.

The `O` for PK or Auto means "Options".


## Schema Creation

Our table, `planet`, was created with `table.dd.create`.  That's convenient for us, but Slick's schema management is very simple. For example, if you run `create` twice, you'll see:

~~~ scala
org.postgresql.util.PSQLException: ERROR: relation "planet" already exists
~~~

That's because `create` blindly issues SQL commands:

~~~ scala
println(planets.ddl.createStatements.mkString)
~~~

...will output:

~~~ sql
create table "planet" ("id" SERIAL NOT NULL PRIMARY KEY,"name" VARCHAR(254) NOT NULL)
~~~

(There's a corresponding `dropStatements` that does the reverse).

To make our example easier to work with, we could query the database meta data and find out if our table already exists before we create it:

~~~ scala
if (MTable.getTables(planets.baseTableRow.tableName).firstOption.isEmpty)
  planets.ddl.create
~~~~

However, for our simple example we'll end up dropping and creating the schema each time:

~~~ scala
MTable.getTables(planets.baseTableRow.tableName).firstOption match {
  case None =>
    planets.ddl.create
  case Some(t) =>
    planets.ddl.drop
    planets.ddl.create
 }
~~~

We'll look at other tools for managing schema migrations later.



## Inserting Data


~~~ scala
// Populate with some data:

planets += (100, "Earth",  1.0)

planets ++= Seq(
  (200, "Mercury",  0.4),
  (300, "Venus",    0.7),
  (400, "Mars" ,    1.5),
  (500, "Jupiter",  5.2),
  (600, "Saturn",   9.5),
  (700, "Uranus",  19.0),
  (800, "Neptune", 30.0)
)
~~~

Each `+=` or `++=` executes in its own transaction.

NB: result is a row count `Int` for a single insert, or `Option[Int]` for a batch insert. It's optional because not all databases support returning a count for batches.

We've had to specify the id, name and distance, but this may be surprising because the ID is an auto incrementing field.  What Slick does, when inserting this data, is ignore the ID:

~~~ sql
essential-slick=# select * from planet;
 id |  name   | distance_au
----+---------+-------------
  1 | Earth   |           1
  2 | Mercury |         0.4
  3 | Venus   |         0.7
  4 | Mars    |         1.5
  5 | Jupiter |         5.2
  6 | Saturn  |         9.5
  7 | Uranus  |          19
  8 | Neptune |          30
(8 rows)
~~~

This is, generally, what you want to happen, and applies only to auto incrementing fields. If the ID was not auto incrementing, the ID values we supplied (100,200 and so on) would have been used.


If you really want to include the ID column in the insert, use the `forceInsert` method.


## A Simple Query

Let's fetch all the planets in the inner solar system:

~~~ scala
val query = for {
  planet <- planets
  if planet.distance < 5.0
} yield planet.name

println("Inner planets: " + query.run)
~~~

This produces:

~~~ scala
Inner planets: Vector(Earth, Mercury, Venus, Mars)
~~~

What did Slick do to produce those results?  It ran this:

~~~ sql
select s9."name" from "planet" s9 where s9."distance_au" < 5.0
~~~~

Note that it did not fetch all the planets and filter them. There's something more interesting going on that that.


<div class="callout callout-info">
#### Logging What Slick is Doing

Slick uses a logging framework called SLFJ.  You can configure this to capture information about the queries being run, and the log to different back ends.  The "essential-slick-example" project uses a logging back-end called _Logback_, which is configured in the file _src/main/resources/logback.xml_.  In that file we enable statement logging by turning up the logging to debug level:

~~~ xml
<logger name="scala.slick.jdbc.JdbcBackend.statement" level="DEBUG"/>
~~~

When we next run a query, each statement will be recorded on standard output:

~~~
18:49:43.557 DEBUG s.slick.jdbc.JdbcBackend.statement - Preparing statement: drop table "planet"
18:49:43.564 DEBUG s.slick.jdbc.JdbcBackend.statement - Preparing statement: create table "planet" ("id" SERIAL NOT NULL PRIMARY KEY,"name" VARCHAR(254) NOT NULL,"distance_au" DOUBLE PRECISION NOT NULL)
~~~


You can enable a variety of events to be logged:

* `scala.slick.jdbc.JdbcBackend.statement` - which is for statement logging, as you've seen.
* `scala.slick.session` - for session information, such as connections being opened.
* `scala.slick` - for everything!  This is usually too much.

</div>




## Running Queries in the REPL

For experimenting with queries it's convenient to use the Scala REPL and create an implicit session to work with.  In the "essential-slick-example" SBT project, run the `console` command to enter the Scala REPL with the Slick dependencies loaded and ready to use:

~~~ scala
> console
[info] Starting scala interpreter...
[info]

Session created, but you may want to also import a schema. For example:

    import underscoreio.schema.Example1._
 or import underscoreio.schema.Example5.Tables._

import scala.slick.driver.PostgresDriver.simple._
db: slick.driver.PostgresDriver.backend.DatabaseDef = scala.slick.jdbc.JdbcBackend$DatabaseFactoryDef$$anon$5@6dbc2f23
session: slick.driver.PostgresDriver.backend.Session = scala.slick.jdbc.JdbcBackend$BaseSession@5dbadb1d
Welcome to Scala version 2.10.3 (Java HotSpot(TM) 64-Bit Server VM, Java 1.7.0_45).
Type in expressions to have them evaluated.
Type :help for more information.

scala> import underscoreio.schema.Example2._
import underscoreio.schema.Example2._

scala> planets.run
08:34:36.053 DEBUG s.slick.jdbc.JdbcBackend.statement - Preparing statement: select x2."id", x2."name", x2."distance_au" from "planet" x2
res1: Seq[(Int, String, Double)] = Vector((1,Earth,1.0), (2,Mercury,0.4), (3,Venus,0.7), (4,Mars,1.5), (5,Jupiter,5.2), (6,Saturn,9.5), (7,Uranus,19.0), (8,Neptune,30.0), (9,Earth,1.0))

scala> planets.firstOption
08:34:42.320 DEBUG s.slick.jdbc.JdbcBackend.statement - Preparing statement: select x2."id", x2."name", x2."distance_au" from "planet" x2
res2: Option[(Int, String, Double)] = Some((1,Earth,1.0))

scala>
~~~



## Exercises

* What happens if you used 5 rather than 5.0 in the query?

* 1AU is roughly 150 million kilometers. Can you run query to return the distances in kilometers? Where is the conversion to kilometers performed? Is it in Scala or in the database?

* How would you count the number of planets? Hint: in the Scala collections the method `length` gives you the size of the collection.

* Select the planet with the name "Earth".  You'll need to know that equals in Slick is represented by `===` (three equals signs).  It's also useful to know that `=!=` is not equals.

* Using a for comprehension, select the planet with the id of 1.  What happens if you try to find a planet with an id of 999?

* You know that for comprehensions are sugar for `map`, `flatMap`, and `filter`.  Use `filter` to find the planet with an id of 1, and then the planet with an id of 999. Hint: `first` and `firstOption` are useful alternatives to `run`.

* The method `startsWith` tests to see if a string starts with a particular sequence of characters.  For example `"Earth".startsWith("Ea")` is `true`.  Find all the planets with a name that starts with "E".  What query does the database run?

* Slick implements the method `like`. Find all the planets with an "a" in their name.

* Find all the planets with an "a" in their name that are more than 5 AU from the Sun.


## Sorting

As you've seen, Slick can produce sensible queries from for comprehensions:


~~~ scala
(for {
  p <- planets
  if p.name like "%a%"
  if p.distance > 5.0
 } yield p ).run
~~~

This equates to the query:

~~~ sql
select
  s17."id", s17."name", s17."distance_au"
from
 "planet" s17
where
 (s17."name" like '%a%') and (s17."distance_au" > 5.0)
~~~

We can take a query and add a sort order to it:

~~~ sql
val query = for { p <- planets if p.distance > 5.0} yield p
query.sortBy(row => row.distance.asc).run
~~~

(Or `desc` to go the other way).

This will run as:

~~~ sql
select
  s22."id", s22."name", s22."distance_au"
from
  "planet" s22
where
  s22."distance_au" > 5.0
order by
  s22."distance_au"
~~~

...to produce:

~~~ scala
Vector((5,Jupiter,5.2), (6,Saturn,9.5), (7,Uranus,19.0), (8,Neptune,30.0))
~~~

What's important here is that we are taking a query, using `sortBy` to create another query, before running it.  Query composition is a topic we will return to later.


## The Types Involved in a Query



## Update & Delete

Queries are used for update and delete operations, replacing `run` with `update` or `delete`.

For example, we don't quite have the distance between the Sun and Uranus right:

~~~ scala
val udist = planets.filter(_.name === "Uranus").map(_.distance)
udist.update(19.2)


When `update` is called, the database will receive:


~~~ sql
update "planet" set "distance_au" = ? where "planet"."name" = 'Uranus'
~~~

The arguments to `update` must match the result of the query.  In this example, we are just returning the distance, so we just modify the distance.


## Exercises


* Modify both the distance and name of a planet.  Hint: you can do this with one call to `update`.

* Delete Earth.

* Delete all the planets with a distance less than 5.0.

* Double the distance of all the planets. (You need to do this client-side, not in the database)

-->
