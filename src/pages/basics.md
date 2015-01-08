# Basics

## Orientation

Slick is a Scala library to provide access to relational databases in a simliar fashion to Scala collections. It is type safe. Tables, columns and queries are defined in Scala.

## Slick isn't an ORM

//TODO

## Basic Concepts

The class below represents a single row of the `message` table, which is constructed from three columns `id`, `from` and `message`.

Access to persist and alter instances of these class is achieved via the `TableQuery` instance.

~~~ scala
  final case class Message(id: Long = 0L, from: String, content: String, when: DateTime)

  final class MessageTable(tag: Tag) extends Table[Message](tag, "message") {
    def id = column[Long]("id", O.PrimaryKey, O.AutoInc)
    def from = column[String]("from")
    def content = column[String]("content")
    def when = column[DateTime]("when")
    def * = (id, from, content, when) <> (Message.tupled, Message.unapply)
  }

  lazy val messages = TableQuery[MessageTable]
~~~

The `message` table can be queried as though it is a Scala collection. For instance, the query below  will return all messages from the user `HAL`.

~~~ scala
  val query = for {
    message <- messages
    if message.from === "HAL"
  } yield message
~~~

However not until it is instructed to do so, making queries lazy, reusable and composable.

~~~ scala
val messages_from_HAL:List[Message] = query.list
~~~~

Database connecitivty will be required. This is provided by a slick driver and session.

~~~ scala
import scala.slick.driver.PostgresDriver.simple._

...


  Database.forURL("jdbc:postgresql:essential-slick",
                  user="core",
                  password="trustno1",
                  driver = "org.postgresql.Driver") withSession {
    implicit session =>
      ...
  }
}
~~~

The import indicates which database to connect to, in the above case PostgresSQL. `Database.forURL` creates a `DatabaseManager` which provides connections to the database.

Finally, a way to compile the code is needed. This is delegated to `sbt`, below is a simple build script which declares the minimum dependencies needed; Slick, the appropriate database driver, PostgresSQL in this case, and a logging library, which Slick requires for it's internal debug logging.

~~~ scala
name := "essential-slick"

version := "1.0"

scalaVersion := "2.11.4"

libraryDependencies += "com.typesafe.slick" %% "slick" % "2.1.0"

libraryDependencies += "org.postgresql" % "postgresql" % "9.3-1101-jdbc41"

libraryDependencies += "ch.qos.logback" % "logback-classic" % "1.1.2"

~~~


### Exercises

The objective of exercises for this chapter are to set up your enivronment.  This will enable you to execute examples and particpate in future exercises.  Commands to be executed on the filesystem are assumed to be rooted in a directory `essential-slick`.

**Database**

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

**sbt**

<div class="callout callout-info">
If you do not have `sbt` installed, there are instructions on the [scala-sbt][link-sbt] about how to do this.
</div>

To use Slick, create a regular Scala project and reference the Slick dependencies.

<div class="callout callout-info">
  **git project**

  If you are uninterested in copying the next few sections, we have a GitHub [project][link-example] containing the build file, directory structure and scala files.

  There will be branch per chapter if you want to follow along without typing the code.
</div>

This can be accomplished using SBT by creating a file `build.sbt` with the contents below:

~~~ scala
name := "essential-slick"

version := "1.0"

scalaVersion := "2.11.4"

libraryDependencies += "com.typesafe.slick" %% "slick" % "2.1.0"

libraryDependencies += "ch.qos.logback" % "logback-classic" % "1.1.2"

libraryDependencies += "org.postgresql" % "postgresql" % "9.3-1101-jdbc41"
~~~

<!--
(To do: explain the dependencies)

Do we want to do this here or later on?

-->

Once `build.sbt` is created, SBT can be run and the dependencies will be fetched.

<div class="callout callout-info">
If working with IntelliJ IDEA or the Eclipse Scala IDE, the _essential-slick-example_ project includes the plugins to generate the IDE project files:

~~~ scala
sbt> eclipse
~~~

or

~~~ scala
sbt> gen-idea
~~~~

The projects can then be opened in an IDE.  For Eclipse, this is _File -> Import -> Existing Project_ menu.
</div>

**Scala**

Finally, we are here, some code.

~~~ scala
package io.underscore.slick

import scala.slick.driver.PostgresDriver.simple._

object ExerciseOne extends Exercise {

  final case class Message(id: Long = 0L, from: String, content: String, when: DateTime)

  final class MessageTable(tag: Tag) extends Table[Message](tag, "message") {
    def id = column[Long]("id", O.PrimaryKey, O.AutoInc)
    def from = column[String]("from")
    def content = column[String]("content")
    def when = column[DateTime]("when")
    def * = (id, from, content, when) <> (Message.tupled, Message.unapply)
  }

  lazy val messages = TableQuery[MessageTable]

  Database.forURL("jdbc:postgresql:essential-slick",
                                 user = "essential",
                              password = "trustno1",
                   driver = "org.postgresql.Driver") withSession {
      implicit session ⇒

      //Create Schema
      messages.ddl.create

      //Define a query
      val query = for {
        message ← messages
        if message.from === "HAL"
      } yield message

      //Execute a query.
      val messages_from_HAL: List[Message] = query.list

      //Display the results of the query
      println(s" ${messages_from_HAL}")
  }

}
~~~

Running this application will create the schema. It can be run from an IDE, or with `sbt` from the command-line:

~~~ bash
$sbt "runMain io.underscore.slick.ExerciseOne"
~~~

The schema can be examined via `psql`, there should be no surprises:

~~~ sql
essential-slick=> \d
               List of relations
 Schema |      Name      |   Type   |   Owner
--------+----------------+----------+-----------
 public | message        | table    | essential
 public | message_id_seq | sequence | essential
(2 rows)

essential-slick=> \d message
                                 Table "public.message"
 Column  |          Type          |                      Modifiers
---------+------------------------+------------------------------------------------------
 from    | character varying(254) | not null
 message | character varying(254) | not null
 id      | bigint                 | not null default nextval('message_id_seq'::regclass)
Indexes:
    "message_pkey" PRIMARY KEY, btree (id)
~~~

Don't worry too much about the code at this point in time. We'll go into more detail later in the book. The important points are:

  * Slick should have created the schema,
  * Running the application should have returned `List()`, as there are currently no messages in the database, let alone from `HAL`.

** Schema Management **

Running the application more than once will give an error as `messages.ddl.create` attempts to create the message table. It doesn't check if the table already exists.

To make our example easier to work with, we could query the database meta data and find out if our table already exists before we create it:

~~~ scala
if (MTable.getTables(messages.baseTableRow.tableName).firstOption.isEmpty)
  messages.ddl.create
~~~~

However, for our simple example we'll end up dropping and creating the schema each time:

~~~ scala
MTable.getTables(messages.baseTableRow.tableName).firstOption match {
  case None =>
    messages.ddl.create
  case Some(t) =>
    messages.ddl.drop
    messages.ddl.create
 }
~~~

We'll look at other tools for managing schema migrations later.

**Inserting Data**

The following can be found in ExerciseTwo of the GitHub project, which will save a bit of typing. It can be run from the console using the following:

~~~ bash
$ sbt "runMain io.underscore.slick.ExerciseTwo"
~~~

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

** A Simple Query **

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
[info] Starting scala interpreter...
[info]

Session created, but you may want to also import a schema. For example:

    import io.underscore.slick.ExerciseTwo._


import scala.slick.driver.PostgresDriver.simple._
db: slick.driver.PostgresDriver.backend.DatabaseDef = scala.slick.jdbc.JdbcBackend$DatabaseFactoryDef$$anon$5@6dbc2f23
session: slick.driver.PostgresDriver.backend.Session = scala.slick.jdbc.JdbcBackend$BaseSession@5dbadb1d
Welcome to Scala version 2.10.3 (Java HotSpot(TM) 64-Bit Server VM, Java 1.7.0_45).
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

## Exercises

* How would you count the number of messages? Hint: in the Scala collections the method `length` gives you the size of the collection.

* Using a for comprehension, select the message with the id of 1.  What happens if you try to find a message with an id of 999?

* You know that for comprehensions are sugar for `map`, `flatMap`, and `filter`.  Use `filter` to find the message with an id of 1, and then the message with an id of 999. Hint: `first` and `firstOption` are useful alternatives to `run`.

* The method `startsWith` tests to see if a string starts with a particular sequence of characters.  For example `"Earth".startsWith("Ea")` is `true`.  Find all the messages with a name that starts with "Dave".  What query does the database run?

* Slick implements the method `like`. Find all the messages with an "Frank" in their content.

* Find all the messages with an "I" in their content, sent by "HAL".


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
