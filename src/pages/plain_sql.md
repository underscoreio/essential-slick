# Plain SQL {#PlainSQL}

Slick supports plain SQL queries in addition to the lifted embedded style we've seen up to this point. Plain queries don't compose as nicely as lifted, or offer quite the same type safely.  But they enable you to execute essentially arbitrary SQL when you need to. If you're unhappy with a particular query produced by Slick, dropping into Plain SQL is the way to go.

In this section we will see that:

- the [interpolators][link-scala-interpolation] `sql` (for select) and `sqlu` (for updates) are used to create plain SQL queries;
- values can be safely substituted into queries using a `${expresson}` syntax;
- custom types can be used in Plain SQL, as long as there is a converter in scope; and
- the `tsql` interpolator can be used to check the syntax and types of a query via a database at compile time.

## Selects

Let's start with a simple example of returning a list of room IDs.

~~~ scala
val query = sql""" select "id" from "room" """.as[Long]

Await.result(db.run(query), 2 seconds)
// Vector(1, 2, 3)
~~~

Running a plain SQL query looks similar to other queries we've seen in this book: just call hand it to `db.run` as usual.

The big difference is with the construction of the query. We supply both the SQL we want to run and specify the expected result type using `as[T]`.

The `as[T]` method is pretty flexible.  Let's get back the room ID and room title:

~~~ scala
val roomInfoQ = sql""" select "id", "title" from "room" """.as[(Long,String)]

// When executed will produce:
// Vector((1,Air Lock), (2,Pod), (3,Brain Room))
~~~

Notice we specified a tuple of `(Long, String)` as the result type.  This matches the columns in our SQL `SELECT` statement.

Using `as[T]` we can build up arbitrary result types.  Later we'll see how we can use our own application case classes too.

One of the most useful features of the SQL interpolators is being able to reference Scala values in a query:

~~~ scala
val t = "Pod"
val podRoomQuery = sql"""
  select
    "id", "title"
  from
    "room"
  where
    "title" = $t """.as[(Long,String)].headOption

// Some((2,Pod))
~~~

Notice how `$t` is used to reference a Scala value `t`. This value is incorporated safely into the query.  That is, you don't have to worry about SQL injection attacks when you use the SQL interpolators in this way.

<div class="callout callout-warning">
**The Danger of Strings**

The SQL interpolators are essential for situations where you need full control over the SQL to be run. Be aware there there is some loss compile-time of safety. For example:

~~~ scala
val t = 42
sql""" select "id" from "room" where "title" = $t """.as[Long].headOption
// JdbcSQLException: Data conversion error converting "Air Lock"
~~~

That example compiles without error, but fails at runtime as the type of the `title` column is a `String` and we've provided an `Int`.  The equivalent query using the lifted embedded style would have caught the problem at compile time.

The `tsql` interpolator, described later in this chapter, helps here by connecting to a database at compile time to check the query and types.

Another place you can become unstuck is with the `#$` style of substitution. This is called _splicing_, and is used when you _don't_ want SQL escaping to apply. For example, perhaps the name of the table you want to use may change:

~~~ scala
val table = "message"
val query = sql""" select "id" from "#$table" """.as[Long]
~~~

In this situation we do not want the value of `table` to be treated as a `String`. If you did, you'd end up with the invalid query: `select "id" from "'message'"`.  

However, this means you can produce dangerous SQL with splicing. The golden rule is to never use `#$` with input supplied by a user.
</div>


### Select with Custom Types

Out of the box Slick knows how to convert many data types to and from SQL data types. The examples we've seen so far include turning a Scala `String` into a SQL string, and a SQL BIGINT to a Scala `Long`.

These conversions are available to `as[T]`.  If we want to work with a type that Slick doesn't know about, we need to provide a conversion.  That's the role of the `GetResult` type class.

As an example, we can fetch the timestamp on our messages using JodaTime's `DateTime`:

~~~ scala
sql""" select "ts" from "message" """.as[DateTime]
~~~

For this to compile we need to provide an instance of `GetResult[DateTime]`:

~~~ scala
import slick.jdbc.GetResult

implicit val GetDateTime =
  GetResult[DateTime](r => new DateTime(r.nextTimestamp(), DateTimeZone.UTC))
~~~

`GetResult` is wrapping up a function from `r` (a `PositionedResult`) to `DateTime`.  The `PositionedResult` provides access to the database value (via `nextTimestamp`, `nextLong`, `nextBigDecimal` and so on).  We use the value from `nextTimestamp` to feed into the constructor for `DateTime`.

The name of this value doesn't matter.  What's important is the type, `GetResult[DateTime]`, and that it is marked as implicit. This allows the compiler to lookup our conversion function when we mention a `DateTime`.

If we try to construct a query without a `GetResult[DateTime]` instance in scope, the compiler will complain:

~~~
could not find implicit value for parameter rconv:
  slick.jdbc.GetResult[DateTime]
~~~

### Case Classes

As you've probably guessed, returning a case class from a Plain SQL query means providing a `GetResult` for the case class.  Let's work through an example for the messages table.

<div class="callout callout-info">
**Run the Code**

You'll find the example queries for this section in the file _select.sql_ over at [the associated GitHub repository][link-example].
</div>


Recall that a message contains: an ID, some content, the sender ID, a timestamp, an optional room ID, and an optional recipient for private messages.  We'll model this as we did in [Chapter 4](#value-classes), by wrapping the `Long` primary keys in the type `Id[Table]`.

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
val query: DBIO[Seq[Message]] =
  sql""" select * from "message" """.as[Message]
~~~

In all likelihood you'll prefer the lifted embedded style over Plain SQL in this specific example. But if you do find yourself using Plain SQL, for performance reasons perhaps, it's useful to know how to convert database values up into meaningful domain types.


<div class="callout callout-warning">
**`SELECT *`**

We sometimes use `SELECT *` in this chapter to fit our code examples onto the page.
You should avoid this in your code base as it leads to brittle code.

An example: if, outside of Slick, a table is modified to add a column, the results from the query will unexpectedly change.  You code may not longer be able to map results.
</div>




## Updates

Back in [Chapter 4](#UpdatingRows) we saw how to modify rows with the `update` method. We noted that batch updates where challenging when we wanted to use the row's current value. The example we used was appending an exclamation mark to a message's content:

``` sql
UPDATE "message" SET "content" = CONCAT("content", '!')
```

Plain SQL updates will allow us to do this. The interpolator is `sqlu`:

~~~ scala
val query =
  sqlu"""UPDATE "message" SET "content" = CONCAT("content", '!')"""
~~~

The `query` we have constructed, just like other queries, is not run until we evaluate it via `db.run`.  But when it is run, it will append the exclamation mark to each row value, which is what we couldn't do as efficiently with the lifted embedded style.

Just like the `sql` interpolator, we also have access to `$` for binding to variables:

~~~ scala
val char = "!"
val query =
  sqlu"""UPDATE "message" SET "content" = CONCAT("content", $char)"""
~~~

This gives us two benefits: the compiler will point out typos in variables names, but also the input is sanitized against SQL injection attacks.


### Updating with Custom Types

Working with basic types like `String` and `Int` is fine, but sometimes you want to update using a richer type. We saw the `GetResult` type class for mapping select results, and for updates this is mirrored with the `SetParameter` type class.

What happens if you want to set a parameter of a type not automatically handled by Slick? You need to provide an instance of `SetParameter` for the type.

For example, JodaTime's `DateTime` is not known to Slick by default. We can teach Slick how to set `DataTime` parameters like this:

``` scala
import slick.jdbc.SetParameter

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
val now =
  sqlu"""UPDATE "message" SET "ts" = ${DateTime.now}"""
```

Without the `SetParameter[DateTime]` instance the compiler would tell you:

```
could not find implicit SetParameter[DateTime]
```



## Typed Checked Plain SQL

We've mentioned the risks of Plain SQL, which can be summarized as not discovering a problem with your query until runtime.  The `tsql` interpolator removes some of this risk, but at the cost of requiring a connection to a database at compile time.


### Compile Time Database Connections

To get started with `tsql` we provide a database configuration information on a class:

```scala
import slick.backend.StaticDatabaseConfig

@StaticDatabaseConfig("file:src/main/resources/application.conf#tsql")
object PlainExample extends App {
  ...
}
```

The `@StaticDatabaseConfig` syntax is called an _annotation_. This particular `StaticDatabaseConfig` annotation is telling Slick to use the connection called "tsql" in our configuration file.  That entry will look like this:

```
tsql = {
  driver = "slick.driver.H2Driver$"
  db {
    connectionPool = disabled
    url = "jdbc:h2:mem:chapter06;INIT=runscript from 'src/main/resources/integration-schema.sql'"
    driver = "org.h2.Driver"
    keepAliveConnection = false
  }
}
```

Note the `$` in the driver class name is not a typo. The class name is being passed to Java's `Class.forName`, but of course Java doesn't have a singleton as such. The Slick configuration does the right thing to load `$MODULE` when it sees `$`. This interoperability with Java is described in [Chapter 29 of Programming in Scala][link-pins-interop].

You won't have seen this when we introduced the database configuration in Chapter 1. That's because this `tsql` configuration has a different formant, and combines the Slick driver (`slicker.driver.H2Driver$`) and the JDBC driver (`org.h2.Drvier`) in one entry.

A consequence of supplying a `@StaticDatabaseConfig` is that you can define one databases configuration for your application and a different one for the compiler to use. That is, perhaps you are running an application, or test suite, against an in-memory database, but validating the queries at compile time against a full-populated production-like integration database.

In the example above, and the accompanying example code, we use an in-memory database to make Slick easy to get started with.  However, an in-memory database is empty by default, and that would be no use for checking queries against. To work around that we provide an `INIT` script to populate the in-memory database.


### Type Checked Plain SQL

With the `@StaticDatabaseConfig` in place we can use `tsql`:

```scala
val program: DBIO[Seq[String]] =
  tsql"""select "content" from "message""""
```  

You can run that query as you would `sql` or `sqlu` query. You can also use custom types via `SetParameter` type class. However, `GetResult` type classes are not supported for `tsql`.

To make this interesting, let's get the query wrong and see what happens:

```scala
val program: DBIO[Seq[String]] =
  tsql"""select "content", "id" from "message""""
```

Do you see what's wrong? If not, don't worry because the compiler will find the problem:

```
type mismatch;
[error]  found   : SqlStreamingAction[Vector[(String, Int)],(String, Int),Effect]
[error]  required: DBIO[Seq[String]]
[error]     (which expands to)  DBIOAction[Seq[String],NoStream,Effect.All]
```

The compiler wants a `String` for each row, because that's what we've declared the result to be. However it is found, via the database, that the query will return `(String,Int)` rows.

If we had omitted the type declaration, the program would have the inferred type of DBIO[Seq[(String,Int)]]. So if you want to catch these kinds of mismatches, it's good practice to declare the type you expect when using `tsql`.

Let's see other kinds of errors the compiler will find.

How about if the SQL is just wrong:

~~~scala
val program: DBIO[Seq[String]] =
  tsql"""select "content" from "message" where"""
~~~

This is incomplete SQL, and the compiler tells us:

~~~
exception during macro expansion: ERROR: syntax error at end of input
[error]   Position: 38
[error]     tsql"""select "content" from "message" WHERE"""
[error]     ^
~~~

And if we get a column name wrong...

~~~scala
val program: DBIO[Seq[String]] =
  tsql"""select "text" from "message" where"""
~~~

...that's also a compile error too:

~~~
Exception during macro expansion: ERROR: column "text" does not exist
[error]   Position: 8
[error]     tsql"""select "text" from "message""""
[error]     ^
~~~

Of course, in addition to selecting rows, you can insert:

```scala
val greeting = "Hello"
val program: DBIO[Seq[Int]] =
  tsql"""insert into "message" ("content") values ($greeting)"""
```

Note that at run time, when we execute the query, a new row will be inserted. At compile time, Slick uses a facility in JDBC to compile the query and retrieve the meta data without having to run the query. In other words, at compile time the database is not mutated.


## Take Home Points

Plain SQL allows you a way out of any limitations you find with Slick's lifted embedded style of querying.  

Two main string interpolators for SQL are provided: `sql` and `sqlu`:

- Values can be safely substituted into Plain SQL queries using `${expression}`.

- Custom types can be used with the interpolators providing an implicit `GetResult` (select) or `SetParameter`(update) is in scope for the type.

- Raw values can be spliced into a query with `$#`, but do so with care. End-user supplied information should always be escaped before being used in a query.

The `tsql` interpolator will check Plain SQL queries against a database at compile time.  The database connection is used to validate the query syntax, and also discover the types of the columns being selected. To make best use of this, always declare the type of the query you expect from `tsql`.


## Exercises

The examples for this section are in the _chatper-06_ folder, in the source files `selects.scala`, `updates.scala`, and `tsql.scala`.


### Robert Tables

We're building a web site that allows searching for users by their email address:

~~~ scala
def lookup(email: String) =
  sql"""select id from "user" where "user"."email" = '#${email}'"""

// Example use:
lookup("dave@example.org").as[Long].headOption
~~~

What the problem with this code?

<div class="solution">
If you are familiar with [xkcd's Little Bobby Tables](http://xkcd.com/327/),
the title of the exercise has probably tipped you off:  `#$` does not escape input.

This means a user could use a carefully crafted email address to do evil:

~~~ scala
lookup("""';DROP TABLE "user";--- """).as[Long]
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
