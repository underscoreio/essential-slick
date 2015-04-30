# Plain SQL {#PlainSQL}

Slick supports plain SQL queries as well as the lif􏰄ted embedded style we've used. Plain queries don't compose as nicely as lifted, but enable you to execute essentially arbitrary SQL when you need to.

To be able to use plain SQL we need to configure our environment a little differently to when we used Slick. As we are no longer using Slick, we don't need the Slick driver, we now
need to use a JDBC driver. The JDBC driver offers a `dynamicSession` method which simplifies session hanlding. Finally we need to import access to plain SQL functionality. We do this by importing `scala.slick.jdbc.StaticQuery`, giving us:

~~~ scala
import scala.slick.driver.JdbcDriver.backend.{ Database ⇒ DDB }
import Database.dynamicSession
import scala.slick.jdbc.{ StaticQuery ⇒ Q }
~~~

TODO: SetParameter[T]

## Select

Let's start with a simple example, return a list of room Ids.

~~~ scala
    val s = sql"""select "room" from "message" """
    val q = s.as[Long]
    val r = q.list

    r.foreach { println}
~~~


-- Explain what is happening.
This would better if we were using the types we created in chapter 2.

~~~ scala
    val s = sql"""select "room" from "message" """
    val q = s.as[Id[RoomTable]]
    val r = q.list

    r.foreach { println}
~~~

If we try and run this we will get a compiler error

~~~
could not find implicit value for parameter rconv: scala.slick.jdbc.GetResult[chapter05.ChatSchema.Id[chapter05.PlainQueries.schema.RoomTable]]
~~~

This is because slick needs to know how to map from the database value to our class `Id[RoomTable]`.
We create these mappings as impilicits, if you look in the chapter 5 chat schema you'll seem a bunch of them defined.

To get our example working, we need to tell slick how to map from a `Long` to `Id[RoomTable]`.
We use the Slick object `GetResult` to do this:

~~~ scala
implicit val getRoomIdResult    = GetResult(r => Id[RoomTable](r.nextLong()))
~~~

The signature of `GetResult` is `GetResult[T]( PositionedResult => T)`,
`PositionedResult` has many methods on it defining the different type a column can be.
As we can see in the example above `nextLong` is one of them.
There are also two helper methods, which make life *much* easier - `<<` and `<<?`.
They wrap  `GetResult` and mean we do not need to define what we expect the column type to be.
Hence we can re-write the room id mapping to:

~~~ scala
implicit val getRoomIdResult    = GetResult(r => Id[RoomTable](r << ?))
~~~

`<<?` is used for optional column mappings.


TODO: FINISH THIS.

~~~ scala
DDB.forURL(dbURL,dbDriver) withDynSession {
  import Q.interpolation

  val daveId:Id[RoomTable]    = Id(1)
  val airLockId               = 1

  val plainSQL = sql"""
      select *
      from "message" inner join "user" on "message"."sender" = "user"."id"
                     inner join "room" on "message"."room"   = "room"."id"
      where "user"."id" = ${daveId} and "room"."id" = ${airLockId}"""

    val results = plainSQL.as[Message].list

    results.foreach(result => println(result))
~~~


<div class="callout callout-warning">
**`SELECT *`**

Throughout the chapter we will use `SELECT *`,this is for brevity.
You should avoid this in your code base as Slick depends on the
column ordering of the results set to be known so you can populate
your case classes via `GetResult` objects.

<!--
    Isn't this a reason TO use SELECT *  ?
    If the column ordering is defined by the projection
    Then that will provide at least *some* type saftey -
    It needs to be the same order as the case class.
  -->

</div>


## Update


back in [Chapter 2](#Querying)...

The alternative is to use the SQL we original wanted via a _plain SQL query_. This is an alternative to the collections-like style we've used up to this point.  Here's how this update looks as a plain query:

~~~ scala
import scala.slick.jdbc.StaticQuery.interpolation

val query =
  sqlu"""UPDATE "message" SET "content" = CONCAT("content", '!')"""

val numRowsModified = query.first
~~~

`sqlu` is a _[string interoplator][link-scala-interpolation]_ for SQL updates. The `query` we have constructed, just like other queries, is not run until we evaluate it in the context of a session via `first` (or `firstOption`, or `list`, and so on). However, there is a big difference from the other queries we've seen. The type of `query` is `StaticQuery[Unit,Int]`. As the word "static" suggests, these kinds of queries do not compose, other than via a form of string concatenation.

As we are using a string interpolation, we have access to `$` for binding to variables:

~~~ scala
val char = "!"
val query =
  sqlu"""UPDATE "message" SET "content" = CONCAT("content", $char)"""
~~~

This gives us two benefits: the compiler will point out typos in variables names, but also the input is santitized against SQL injection attacks.

We'll look at plain SQL in more depth in chapter 4, including the `sql` interpolator for select statements.


### Exercises

#### Interpolated Variables

Write a method that will take any string, and return a query to append the string to all messages. Use a plain SQL query to do this.

What happens if you try to append special SQL characters, such as `'` (single quote), `"` (double quote), or `;` (semicolon)?

<div class="solution">
~~~ scala
def append(s: String) =
  sqlu"""UPDATE "message" SET "content" = CONCAT("content", $s)"""
~~~

The `$s` interpolation is safely escaped, allowing any unsafe text to be used without risk.
</div>

#### Unsafe Composition

Using, but not modifying, the method from the last exercise, restrict the update to messages from "HAL".

Would it be possible to construct invalid SQL?

<div class="solution">
~~~ scala
def append(s: String) =
  sqlu"""UPDATE "message" SET "content" = CONCAT("content", $s)"""

val halOnly = append("!") + """ WHERE "sender" = 'HAL' """
~~~

It is very easy to get this query wrong and only find out at run-time. Notice, for example, we had to include a space before "WHERE" and use the correct single quoting around "HAL".

A slight improvement on this is to automatically escape values. We can do this by using `+?` to introduce parameters:

~~~ scala
val halOnly = append("!") + """ WHERE "sender" = """ +? "HAL"
~~~

The methods `+` and `+?` are the only `StaticQuery` method for composing queries.

</div>

## Exercises

#### Robert Tables

What will the following do?

~~~ scala
def userByEmail(email:String) = {
    sql"""select * from "user" where "user"."email" = '#${email}'"""
}

val ohDear = userByEmail("""';DROP TABLE "user";--- """).as[User].list

results.foreach(result => println(result))

sql"""select * from "user" """.as[User].list.foreach(result => println(result))
~~~


<div class="solution">
If you are familiar with [joins][link-xkcd],
the title of the exercise has probably tipped you off.
`#$` does not escape input, so the SQL we run is actually two queries:

~~~ sql
SELECT * FROM "user" WHERE "user"."email" = '';
~~~
and

~~~ sql
DROP TABLE "user";---
~~~

When we attempt to return all users from `user`,
the table has been dropped and get we get the error:

~~~
org.h2.jdbc.JdbcSQLException: Table "user" not found; SQL statement:
select * from "user"  [42102-185]
~~~
</div>


## Take Home Points

- `#$` is incredibly dangerous. Information should always be escaped before it goes near a database. Never forget little bobby tables.

![Image from https://xkcd.com/327](src/img/exploits_of_a_mom.png)




