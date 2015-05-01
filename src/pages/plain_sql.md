# Plain SQL {#PlainSQL}

Slick supports plain SQL queries as well as the lif􏰄ted embedded style we've used. Plain queries don't compose as nicely as lifted, but enable you to execute essentially arbitrary SQL when you need to.

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


### Constructing Queries

Interpolators are used to create plain SQL queries, `sql` for select and `sqlu` for update.
The queries produced by both and `sql` and `sqlu` are `StaticQuery`s. As the word "static" suggests,
these kinds of queries do not compose, other than via a form of string concatenation.

The operations available to you are just:

* `+` to append a string to the query, giving a new query; and
* `+?` to add a value, and correctly escape the value for use in SQL.

**Note**: `sql` really returns a `SQLInterpolationResult`, we'll see more about this a little later.

As an example, we can find all room id's for messages, and then create a new query based on this to filter by message content:

``` scala
val pattern = "%Dave%"
val query     = sql"""SELECT "room" from "message"""".as[Long]
val sensitive = query + """ WHERE "content" NOT LIKE """ +? pattern
```

The result of this is a new `StaticQuery` which we can run.

### Queries with Custom Types

Out of the box Slick knows how to convert many data types to and from SQL data types. The example we've seen so far is turning a Scala `String` into a SQL string and a SQL BIGINT to a Scala `Long`.

We'll look at this more in the coming sections.


## Select

Let's start with a simple example, return a list of room Ids.

~~~ scala
    val s = sql"""select "room" from "message" """
    val q = s.as[Long]
    val r = q.list

    r.foreach { println}
~~~

The above is pretty simple, we define a query using the `sql` interpolator, using the `as` method
we declare the Scala type we expect `room` to be and finally we execute the query.


We can improve our example above by using the types we created in chapter 2 - Id[T], what's the point in having types if we aren't going to use them!

~~~ scala
    val s = sql"""select "room" from "message" """
    val q = s.as[Id[RoomTable]]
    val r = q.list

    r.foreach { println}
~~~

If we try and run this we will get a compiler error:

~~~
could not find implicit value for parameter rconv: scala.slick.jdbc.GetResult[chapter05.ChatSchema.Id[chapter05.PlainQueries.schema.RoomTable]]
~~~

We'll see how to fix this in the next section.

### Select with Custom Types

**TODO**: Decide if we want to talk about   `asUpdate`

`sql` returns a `SQLInterpolationResult`, we use use the `as[T]` method to declare the expected Scala type.
If, as in the case above there isn't an implicit available to map between the SQL types and our expected type,
we get an error.

To create our own mappings we use the Slick object `GetResult`.
The signature of `GetResult` is `GetResult[T]( PositionedResult )`,
`PositionedResult` is a wrapper to a results set, it handles moving between columns and rows.
All we need to do is ask for the next value we want via methods such as `nextBigDecimal`, `nextClobOption` or `nextString`.

With this knowledge we can fix the previous example:

~~~ scala
implicit val getRoomIdResult    = GetResult(r => Id[RoomTable](r.nextLong()))
~~~

<!-- this needs improving -->
There are also two helper methods, which make life *much* easier - `<<` and `<<?`.
They wrap `GetResult` and mean we do not need to define what we expect the column type to be, as long as there is
an existing implicit defined for the mapping we need.
Hence we can re-write the room id mapping to:

~~~ scala
implicit val getRoomIdResult    = GetResult(r => Id[RoomTable](r << ?))
~~~

`<<?` is used for optional column mappings, such as the room id on message. Rather than writing

~~~ scala
implicit val getORoomIdResult: GetResult[Option[Id[RoomTable]]] = ↩
             GetResult(r => r.nextLongOption().map(i => Id[RoomTable](i)))
~~~

we can write:

<!-- << ? breaks the syntax highlighter in sublime. -->
~~~ scala
implicit val getOptionalRoomIdResult: GetResult[Option[Id[RoomTable]]] = ↩
             GetResult( _ <<?)
~~~

There are some things to be aware of when using plain SQL.
The complier will not be able to help you, apart from pointing out when values are mispelt.

~~~ scala
  val daveId[RoomTable] = Id(1)
  val airLockId         = 1

  val plainSQL = sql"""
      select *
      from "message" inner join "user" on "message"."sender" = "user"."id"
                     inner join "room" on "message"."room"   = "room"."id"
      where "user"."id" = ${daveId} and "room"."id" = ${airLockId}"""

    val results = plainSQL.as[Message].list

    results.foreach(result => println(result))
~~~

In the example above, notice that `daveId` is actually of type  `Id[RoomTable]` and `airLockId` is a plain old `Long`,
and yet, this example will compile and run.
It will of course, return rubbish.


### Exercises

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
DROP TABLE "user";
~~~

When we attempt to return all users from `user`,
the table has been dropped and get we get the error:

~~~
org.h2.jdbc.JdbcSQLException: Table "user" not found; SQL statement:
select * from "user"  [42102-185]
~~~
</div>


## Update

Back in [Chapter 2](#Querying) we saw how to modify rows with the `update` method. We noted that batch updates where challenging when we wanted to use the row's current value. The example we used was appending an exclamation mark to a message's content:

``` sql
UPDATE "message" SET "content" = CONCAT("content", '!')
```

Plain SQL updates will allow us to do this. As with select, there's an interpolated, and it's called `sqlu`:


~~~ scala
import scala.slick.jdbc.StaticQuery.interpolation

val query =
  sqlu"""UPDATE "message" SET "content" = CONCAT("content", '!')"""

val numRowsModified = query.first
~~~

The `query` we have constructed, just like other queries, is not run until we evaluate it in the context of a session via `first` (or `firstOption`, or `list`, and so on).

We also have access to `$` for binding to variables, just as we did for `sql`:

~~~ scala
val char = "!"
val query =
  sqlu"""UPDATE "message" SET "content" = CONCAT("content", $char)"""
~~~

This gives us two benefits: the compiler will point out typos in variables names, but also the input is santitized against SQL injection attacks.

### Updating with Custom Types


For plain queries this mapping is implemented via `SetParameter` type class, which is the mirror of the `GetParamater` type class discussed in the previous section.

What happens if you try to set a parameter of a type not automatically handled by Slick? In that case you need to provide an instance of `SetParameter` for the type.

For example, JodaTime's `DateTime` is not known to Slick by default. We can teach Slick how to set `DataTime` parameters like this:

``` scala
implicit object SetDateTime extends SetParameter[DateTime] {
  def apply(dt: DateTime, pp: PositionedParameters): Unit =
    pp.setTimestamp(new Timestamp(dt.getMillis))
    // or...
    // pp >> new Timestamp(dt.getMillis)
    // ...if you prefer.
}
```

`PositionedParameters` is an implementation detail of Slick, wrapping a SQL statement and a place holder for a value.  Effectively we're saying how to treat a `DateTime` regardless of where it appears in the update statement.

In addition to a `Timestamp` (via `setTimestamp`), you can set: `Boolean`, `Byte`, `Short`, `Int`, `Long`, `Float`, `Double`, `BigDecimal`, `Array[Byte]`, `Blob`, `Clob`, `Date`, `Time`, as well as `Object` and `null`.  There are _setXXX_ methods on `PositionedParameters` for `Option` types, too.

With this in place we can construct plain SQL updates using `DateTime` instances:

``` scala
sqlu"""UPDATE message SET "ts" = """ +? DateTime.now
```

Without the `SetParameter[DateTime]` instance the compiler would tell you:

```
could not find implicit SetParameter[DateTime]
```

<div class="callout callout-warning">
**Compile Warnings**

The code we've written produces the following warning:

```
Adaptation of argument list by inserting () has been deprecated:
  this is unlikely to be what you want.
```

This is a limitation of the Slick 2.1 implementation, and is being resoled for Slick 3.0.
For now, you'll have to live with the warning.
</div>


### Exercises

The examples for this section are in the _chatper-05_ folder, in the source file _updates.scala_.

You can run the code example with:

```
$ sbt
> runMain chapter05.PlainUpdatesExample
```

#### String Interpolation Mistake

When we constructed our `sensitive` query, we used `+?` to include a `String` in our query.

It looks as if we could have used regular string interpolation instead:

``` scala
val sensitive = query + s""" WHERE "content" NOT LIKE $pattern"""
```

Why didn't we do that?

<div class="solution">
The standard Scala string interpolator doesn't have any knowledge of SQL.  It doesn't know that `Strings` need to be quoted in single quotes, for example.

In contrast, Slick's `sql` and `sqlu` interpolators do understand SQL and do the correct embedding of values.  When working with regular `String`s, as we were, you must use `+?` to ensure values are correctly encoded for SQL.
</div>


#### Unsafe Composition

Here's a utility method that takes any string, and return a query to append the string to all messages.

~~~ scala
def append(s: String) =
  sqlu"""UPDATE "message" SET "content" = CONCAT("content", $s)"""
~~~

Using, but not modifying, the method, restrict the update to messages from "HAL".

Would it be possible to construct invalid SQL?

<div class="solution">
~~~ scala
def append(s: String) =
  sqlu"""UPDATE "message" SET "content" = CONCAT("content", $s)"""

val halOnly = append("!") + """ WHERE "sender" = 'HAL' """
~~~

It is very easy to get this query wrong and only find out at run-time. Notice, for example, we had to include a space before "WHERE" and use the correct single quoting around "HAL".
</div>


## Take Home Points

- `#$` is incredibly dangerous. Information should always be escaped before it goes near a database. Never forget little bobby tables.

![Image from https://xkcd.com/327](src/img/exploits_of_a_mom.png)

Plain SQL updates allow you overcome limitations in the lifted embedded style of updates. They are created with the `sqlu` interpolator. They have limited ability to be composed, offering just `+` for `String`s and `+?` for parameters.

Custom types can be used with the interpolators providing an implicit `GetParamter` (select) or `SetParameter`(update) is in scope for the type.

