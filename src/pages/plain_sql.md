# Plain SQL {#PlainSQL}

Slick supports plain SQL queries as well as the lifted embedded style we've seen up to this point. Plain queries don't compose as nicely as lifted, or offer the same type safely.  But they enable you to execute essentially arbitrary SQL when you need to. If you're unhappy with a particular query produced by Slick, dropping into Plain SQL is the way to go.

In this section we will see that:

- the [interpolators][link-scala-interpolation] `sql` and `sqlu` (for updates) are used to create plain SQL queries;
- values can be safely substituted into queries using a `${expresson}` syntax;
- you can build up a query from `String`s and values using `+` and `+?`; and
- custom types can be used in plain SQL, as long as there is a converter in scope.


## Selects

Let's start with a simple example of returning a list of room IDs.

~~~ scala
import scala.slick.jdbc.StaticQuery.interpolation

val query = sql""" select "id" from "room" """.as[Long]
val result = query.list

println(results)
// List(1, 2, 3)
~~~

We need to import `interpolation` to enable the use of the `sql` interpolator.

Once we've done that, running a plain SQL looks similar to other queries we've seen in this book: just call `list` (or `first` etc). You need an implicit `session` in scope, as you do for all queries.

The big difference is with the construction of the query. We supply both the SQL we want to run and specify the expected result type using `as[T]`.

The `as[T]` method is pretty flexible.  Let's get back the room ID and room title:

~~~ scala
val roomInfoQ = sql""" select "id", "title" from "room" """.as[(Long,String)]
val roomInfo = roomInfoQ.list
println(roomInfo)
// List((1,Air Lock), (2,Pod), (3,Brain Room))
~~~

Notice we specified a tuple of `(Long, String)` as the result type.  This matches the columns in our SQL `SELECT` statement.

Using `as[T]` we can build up arbitrary result types.  Later we'll see how we can use our own application case classes too.

One of the most useful features of the SQL interpolators is being able to reference Scala values in a query:

~~~ scala
val t = "Pod"
sql""" select "id", "title" from "room" where "title" = $t """. ↩
                                                as[(Long,String)].firstOption
// Some((2,Pod))
~~~

Notice how `$t` is used to reference a Scala value `t`. This value is incorporated safely into the query.  That is, you don't have to worry about SQL injection attacks when you use the SQL interpolators in this way.

<div class="callout callout-warning">
**The Danger of Strings**

The SQL interpolators are essential for situations where you need full control over the SQL to be run. Be aware there there is some loss compile-time of safety. For example:

~~~ scala
val t = 42
sql""" select "id" from "room" where "title" = $t """.as[Long].firstOption
// JdbcSQLException: Data conversion error converting "Air Lock"; SQL statement:
// [error]  select "id" from "room" where "title" = ?
~~~

That example compiles without error, but fails at runtime as the type of the `title` column is a `String` and we've provided an `Integer`.  The equivalent query using the lifted embedded style would have caught the problem at compile time.

Another place you can unstuck is with the `#$` style of substitution.  This is used when you _don't_ want SQL escaping to apply. For example, perhaps the name of the table you want to use may change:

~~~ scala
val table = "message"
val query = sql""" select "id" from "#$table" """.as[Long]
~~~

In this situation we do not want the value of `table` to be treated as a String. That would give you the invalid query: `select "id" from "'message'"`.  However, using this construct means you can produce dangerous SQL. The golden rule is to never use `#$` with input supplied by a user.
</div>


### Constructing Queries

In addition to using `$` to reference Scala values in queries, you can build up queries incrementally.

The queries produced by both and `sql` and `sqlu` (which we see later) are `StaticQuery`s. As the word "static" suggests,
these kinds of queries do not compose, other than via a form of string concatenation.

The operations available to you are:

* `+` to append a string to the query, giving a new query; and
* `+?` to add a value, and correctly escape the value for use in SQL.

As an example, we can find all IDs for messages...

~~~ scala
val query = sql"""SELECT "id" from "message"""".as[Long]
~~~

...and then create a new query based on this to filter by message content:

``` scala
val pattern   = "%Dave%"
val sensitive = query + """ WHERE "content" NOT LIKE """ +? pattern
```

The result of this is a new `StaticQuery` which we can execute.


### Select with Custom Types

Out of the box Slick knows how to convert many data types to and from SQL data types. The examples we've seen so far include turning a Scala `String` into a SQL string, and a SQL BIGINT to a Scala `Long`.

These conversions are available to `as[T]` and `+?`.  If we want to work with a type that Slick doesn't know about, we need to provide a conversion.  That's the role of the `GetResult` type class.

As an example, we can fetch the timestamp on our messages using JodaTime's `DateTime`:

~~~ scala
sql""" select "ts" from "message" """.as[DateTime]
~~~

For this to compile we need to provide an instance of `GetResult[DateTime]`:

~~~ scala
implicit val GetDateTime =
  GetResult[DateTime](r => new DateTime(r.nextTimestamp(), DateTimeZone.UTC))
~~~

`GetResult` is wrapping up a function from `r` (a `PositionedResult`) to `DateTime`.  The `PositionedResult` provides access to the database value (via `nextTimestamp`, `nextLong`, `nextBigDecimal` and so on).  We use the value from `nextTimestamp` to feed into the constructor for `DateTime`.

The name of this value doesn't matter.  What's important is the type, `GetResult[DateTime]`. This allows the compiler to lookup our conversion function when we mention a `DateTime`.

If we try to construct a query without a `GetResult[DateTime]` instance in scope, the compiler will complain:

~~~
could not find implicit value for parameter rconv:
  scala.slick.jdbc.GetResult[DateTime]
~~~

### Case Classes

As you've probably guessed, returning a case class from a Plain SQL query means providing a `GetResult` for the case class.  Let's work through an example for the messages table.

<div class="callout callout-info">
**Run the Code**

You'll find the example queries for this section in the file _select.sql_ over at [the associated GitHub repository][link-example].
</div>


Recall that a message contains: an ID, some content, the sender ID, a timestamp, an optional room ID, and an optional recipient for private messages.  We'll model this as we did in Chapter 4, by wrapping the `Long` primary keys in the type `Id[Table]`.

This gives us:

~~~ scala
case class Message(
  senderId: Id[UserTable],
  content:  String,
  ts:       DateTime,
  roomId:   Option[Id[RoomTable]] = None,
  toId:     Option[Id[UserTable]] = None,
  id:       Id[MessageTable]      = Id(0L) )
~~~

To provide a `GetResult[Message]` we need all the types inside the `Message` to have `GetResult` instances.  We've already tackled `DateTime`.  That leaves  `Id[MessageTable]`, `Id[UserTable]`, `Option[Id[UserTable]`, and `Option[Id[RoomTable]`.

Dealing with the two non-option IDs is straight-forward:

~~~ scala
implicit val GetUserId    = GetResult(r => Id[UserTable](r.nextLong))
implicit val GetMessageId = GetResult(r => Id[MessageTable](r.nextLong))
~~~

For the optional ones we need to use `nextLongOption` and then `map` to the right type:

~~~ scala
implicit val GetOptUserId = GetResult(r => r.nextLongOption.map(i => Id[UserTable](i)))
implicit val GetOptRoomId = GetResult(r => r.nextLongOption.map(i => Id[RoomTable](i)))
~~~

With all the individual columns mapped we can pull them into a `GetResult` for `Message`. There are two helper methods which make it easier to construct these instances:

- `<<` for calling the appropriate _nextXXX_ method; and
- `<<?` when the value is optional.

We can use them like this:

~~~ scala
implicit val GetMessage = GetResult(r =>
   Message(senderId  = r.<<,
           content   = r.<<,
           ts        = r.<<,
           id        = r.<<,
           roomId    = r.<<?,
           toId      = r.<<?) )
~~~

This works because we've provided implicits for the components of the case class. As the types of the fields are known, `<<` and `<<?` simply expect the implicit `GetResult[T]` for each type.

Now we can select into `Message` values:

~~~ scala
val result: List[Message] =
  sql""" select * from "message" """.as[Message].list
~~~

In all likelihood you'll prefer `messages.list` over Plain SQL in this specific example. But if you do find yourself using Plain SQL, for performance reasons perhaps, it's useful to know how to convert database values up into meaningful domain types.


<div class="callout callout-warning">
**`SELECT *`**

We sometimes use `SELECT *` in this chapter to fit our code examples onto the page.
You should avoid this in your code base as it leads to brittle code.

An example: if, outside of Slick, a table is modified to add a column, the results from the query will unexpectedly change.  You code may not longer be able to map results.
</div>




## Updates

Back in [Chapter 4](#Querying) we saw how to modify rows with the `update` method. We noted that batch updates where challenging when we wanted to use the row's current value. The example we used was appending an exclamation mark to a message's content:

``` sql
UPDATE "message" SET "content" = CONCAT("content", '!')
```

Plain SQL updates will allow us to do this. The interpolator is `sqlu`:

~~~ scala
import scala.slick.jdbc.StaticQuery.interpolation

val query =
  sqlu"""UPDATE "message" SET "content" = CONCAT("content", '!')"""

val numRowsModified = query.first
~~~

The `query` we have constructed, just like other queries, is not run until we evaluate it in the context of a session.

We also have access to `$` for binding to variables, just as we did for `sql`:

~~~ scala
val char = "!"
val query =
  sqlu"""UPDATE "message" SET "content" = CONCAT("content", $char)"""
~~~

This gives us two benefits: the compiler will point out typos in variables names, but also the input is sanitized against SQL injection attacks.


### Composing Updates

All the techniques described for selects applies for composing plain SQL updates.

As an example, we can start with an unconditional update...

~~~ scala
val query = sqlu"""UPDATE "message" SET "content" = CONCAT("content", $char)"""
~~~

...and then create an alternative query using the `+` method defined on `StaticQuery`:

~~~ scala
val pattern = "%!"
val sensitive =  query + """ WHERE "content" NOT LIKE """ +? pattern
~~~

The resulting query would append an `!` only to rows that don't already end with that character.


### Updating with Custom Types

Working with basic types like `String` and `Int` is fine, but sometimes you want to update using a richer type. We saw the `GetResult` type class for mapping select results, and for updates this is mirrored with the `SetParameter` type class.

What happens if you want to set a parameter of a type not automatically handled by Slick? You need to provide an instance of `SetParameter` for the type.

For example, JodaTime's `DateTime` is not known to Slick by default. We can teach Slick how to set `DataTime` parameters like this:

``` scala
implicit val SetDateTime = SetParameter[DateTime](
  (dt, pp) => pp.setTimestamp(new Timestamp(dt.getMillis))
 )
```

The value `pp` is a `PositionedParameters`. This is an implementation detail of Slick, wrapping a SQL statement and a placeholder for a value.  Effectively we're saying how to treat a `DateTime` regardless of where it appears in the update statement.

In addition to a `Timestamp` (via `setTimestamp`), you can set: `Boolean`, `Byte`, `Short`, `Int`, `Long`, `Float`, `Double`, `BigDecimal`, `Array[Byte]`, `Blob`, `Clob`, `Date`, `Time`, as well as `Object` and `null`.  There are _setXXX_ methods on `PositionedParameters` for `Option` types, too.

There's further symmetry with `GetResuts` in that we could have used `>>` in our `SetParameter`:

~~~ scala
(dt, pp) => pp >> new Timestamp(dt.getMillis)
~~~


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

The code we've written in this chapter produces the following warning:

```
Adaptation of argument list by inserting () has been deprecated:
  this is unlikely to be what you want.
```

This is a limitation of the Slick 2.1 implementation, and is being resoled for Slick 3.0.
For now, you'll have to live with the warning.
</div>



## Take Home Points

Plain SQL allows you a way out of any limitations you find with Slick's lifted embedded style of querying.  Two string interpolators for SQL are provided: `sql` and `sqlu`.

Values can be safely substituted into Plain SQL queries using `${expression}`.

Custom types can be used with the interpolators providing an implicit `GetResult` (select) or `SetParameter`(update) is in scope for the type.

The tools for composing these kinds of queries is limited. Use `+`, `+?`, and `$#`, but do so with care. End-user supplied information should always be escaped before being used in a query.


## Exercises

The examples for this section are in the _chatper-06_ folder, in the source files _selects.scala_ and _updates.scala_.

### Robert Tables

We're building a web site that allows searching for users by their email address:

~~~ scala
def lookup(email: String) =
  sql"""select id from "user" where "user"."email" = '#${email}'"""

// Example use:
lookup("dave@example.org").as[Long].firstOption
~~~

What the problem with this code?

<div class="solution">
If you are familiar with [xkcd's Little Bobby Tables](http://xkcd.com/327/),
the title of the exercise has probably tipped you off:  `#$` does not escape input.

This means a user could use a carefully crafted email address to do evil:

~~~ scala
lookup("""';DROP TABLE "user";--- """).as[Long].list
~~~

This "email address" turns into two queries:

~~~ sql
SELECT * FROM "user" WHERE "user"."email" = '';
~~~

and

~~~ sql
DROP TABLE "user";
~~~

Trying to access the users table after this will produce:

~~~
org.h2.jdbc.JdbcSQLException: Table "user" not found
~~~

Yes, the table was dropped by the query.
</div>


### String Interpolation Mistake

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


### Unsafe Composition

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
