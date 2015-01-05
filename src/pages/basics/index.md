# Basics

## Our First Table

~~~ scala
package underscoreio.schema

import scala.slick.driver.PostgresDriver.simple._

object Example1 extends App {

  class Planet(tag: Tag) extends Table[(Int,String,Double)](tag, "planet") {
    def id = column[Int]("id", O.PrimaryKey, O.AutoInc)
    def name = column[String]("name")
    def distance = column[Double]("distance_au")
    def * = (id, name, distance)
  }

  lazy val planets = TableQuery[Planet]

  Database.forURL("jdbc:postgresql:essential-slick",
                  user="core",
                  password="trustno1",
                  driver = "org.postgresql.Driver") withSession {
    implicit session =>
      planets.ddl.create
  }

}
~~~

Running this application will create the schema. It can be run from an IDE, or with `sbt run-main underscoreio.schema.Example1`.

The schema can be examined via `psql`, there should be no surprises:

~~~ sql

essential-slick=# \d
             List of relations
 Schema |     Name      |   Type   | Owner
--------+---------------+----------+-------
 public | planet        | table    | core
 public | planet_id_seq | sequence | core
(2 rows)

essential-slick=# \d planet
                                   Table "public.planet"
   Column    |          Type          |                      Modifiers
-------------+------------------------+-----------------------------------------------------
 id          | integer                | not null default nextval('planet_id_seq'::regclass)
 name        | character varying(254) | not null
 distance_au | double precision       | not null
Indexes:
    "planet_pkey" PRIMARY KEY, btree (id)
~~~

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


