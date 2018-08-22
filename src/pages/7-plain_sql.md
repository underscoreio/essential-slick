```tut:invisible
import slick.jdbc.H2Profile.api._
import scala.concurrent.{Await,Future}
import scala.concurrent.duration._
import scala.concurrent.ExecutionContext.Implicits.global

val db = Database.forConfig("chapter07")

def exec[T](action: DBIO[T]): T = Await.result(db.run(action), 4.seconds)
```
# Plain SQL {#PlainSQL}

Slick supports Plain SQL queries in addition to the lifted embedded style we've seen up to this point. Plain queries don't compose as nicely as lifted, or offer quite the same type safely.  But they enable you to execute essentially arbitrary SQL when you need to. If you're unhappy with a particular query produced by Slick, dropping into Plain SQL is the way to go.

In this section we will see that:

- the [interpolators][link-scala-interpolation] `sql` (for select) and `sqlu` (for updates) are used to create Plain SQL queries;

- values can be safely substituted into queries using a `${expresson}` syntax;

- custom types can be used in Plain SQL, as long as there is a converter in scope; and

- the `tsql` interpolator can be used to check the syntax and types of a query via a database at compile time.

<div class="callout callout-info">
**A Table to Work With**

For the examples that follow, we'll set up a table for rooms.
For now we'll do this as  we have in other chapters using the lifted embedded style:

```tut:book
case class Room(title: String, id: Long = 0L)

class RoomTable(tag: Tag) extends Table[Room](tag, "room") {
 def id    = column[Long]("id", O.PrimaryKey, O.AutoInc)
 def title = column[String]("title")
 def * = (title, id).mapTo[Room]
}

lazy val rooms = TableQuery[RoomTable]

val roomSetup = DBIO.seq(
  rooms.schema.create,
  rooms ++= Seq(Room("Air Lock"), Room("Pod"), Room("Brain Room"))
)

val setupResult = exec(roomSetup)
```
</div>

## Selects

Let's start with a simple example of returning a list of room IDs.

```tut:book
val action = sql""" select "id" from "room" """.as[Long]

Await.result(db.run(action), 2.seconds)
```

Running a Plain SQL query looks similar to other queries we've seen in this book: call `db.run` as usual.

The big difference is with the construction of the query. We supply both the SQL we want to run and specify the expected result type using `as[T]`.
And the result we get back is an action to run, rather than a `Query`.

The `as[T]` method is pretty flexible.  Let's get back the room ID and room title:

```tut:book
val roomInfo = sql""" select "id", "title" from "room" """.as[(Long,String)]

exec(roomInfo)
```

Notice we specified a tuple of `(Long, String)` as the result type.  This matches the columns in our SQL `SELECT` statement.

Using `as[T]` we can build up arbitrary result types.  Later we'll see how we can use our own application case classes too.

One of the most useful features of the SQL interpolators is being able to reference Scala values in a query:

```tut:book
val roomName = "Pod"

val podRoomAction = sql"""
  select
    "id", "title"
  from
    "room"
  where
    "title" = $roomName """.as[(Long,String)].headOption

exec(podRoomAction)
```

Notice how `$roomName` is used to reference a Scala value `roomName`.
This value is incorporated safely into the query.
That is, you don't have to worry about SQL injection attacks when you use the SQL interpolators in this way.

<div class="callout callout-warning">
**The Danger of Strings**

The SQL interpolators are essential for situations where you need full control over the SQL to be run. Be aware there  is some loss of compile-time safety. For example:

```tut:book
val t = 42

val badAction =
  sql""" select "id" from "room" where "title" = $t """.as[Long]
```

This compiles, but fails at runtime as the type of the `title` column is a `String` and we've provided an `Int`:

```tut:book
exec(badAction.asTry)
```

The equivalent query using the lifted embedded style would have caught the problem at compile time. 
The `tsql` interpolator, described later in this chapter, helps here by connecting to a database at compile time to check the query and types.

Another danger is with the `#$` style of substitution. This is called _splicing_, and is used when you _don't_ want SQL escaping to apply. For example, perhaps the name of the table you want to use may change:

```tut:book
val table = "room"
val action = sql""" select "id" from "#$table" """.as[Long]
```

In this situation we do not want the value of `table` to be treated as a `String`. If we did, it'd be an invalid query: `select "id" from "'message'"` (notice the double quotes and single quotes around the table name, which is not valid SQL).

This means you can produce unsafe SQL with splicing. The golden rule is to never use `#$` with input supplied by users.

To be sure you remember it, say it again with us:  never use `#$` with input supplied by users.
</div>


### Select with Custom Types

Out of the box Slick knows how to convert many data types to and from SQL data types. The examples we've seen so far include turning a Scala `String` into a SQL string, and a SQL BIGINT to a Scala `Long`. These conversions are available via `as[T]`.  

If we want to work with a type that Slick doesn't know about, we need to provide a conversion.  That's the role of the `GetResult` type class.

For an example, let's set up a table for messages with some interesting structure:

```tut:book
import org.joda.time.DateTime

case class Message(
  sender  : String,
  content : String,
  created : DateTime,
  updated : Option[DateTime],
  id      : Long = 0L
)
```

The point of interest for the moment is that we have a `created` field of type `DateTime`.
This is from Joda Time, and Slick does not ship with built-in support for this type.

This is the query we want to run:

```tut:book:fail
sql""" select "created" from "message" """.as[DateTime]
```

OK, that won't compile as Slick doesn't know anything about `DateTime`.
For this to compile we need to provide an instance of `GetResult[DateTime]`:

```tut:silent
import slick.jdbc.GetResult
import java.sql.Timestamp
import org.joda.time.DateTimeZone.UTC
```
```tut:book
implicit val GetDateTime =
  GetResult[DateTime](r => new DateTime(r.nextTimestamp(), UTC))
```

`GetResult` is wrapping up a function from `r` (a `PositionedResult`) to `DateTime`.  The `PositionedResult` provides access to the database value (via `nextTimestamp`, `nextLong`, `nextBigDecimal` and so on).  We use the value from `nextTimestamp` to feed into the constructor for `DateTime`.

The name of this value doesn't matter. 
What's important is that the value is implicit and the type is `GetResult[DateTime]`.
This allows the compiler to lookup our conversion function when we mention a `DateTime`.

Now we can construct our action:

```tut:book
sql""" select "created" from "message" """.as[DateTime]
```

### Case Classes

As you've probably guessed, returning a case class from a Plain SQL query means providing a `GetResult` for the case class.  Let's work through an example for the messages table.

Recall that a message contains: an ID, some content, the sender ID, a timestamp, and an optional timestamp.

To provide a `GetResult[Message]` we need all the types inside the `Message` to have `GetResult` instances.
We've already tackled `DateTime`.
And Slick knows how to handle `Long` and `String`. 
So that leaves us with `Option[DateTime]` and the `Message` itself.

For optional values, Slick provides `nextXXXOption` methods, such as `nextLongOption`.
For the optional date time we read the database value using `nextTimestampOption` and then `map` to the right type:

```tut:book
implicit val GetOptionalDateTime = GetResult[Option[DateTime]](r =>
  r.nextTimestampOption.map(ts => new DateTime(ts, UTC))
)
```

With all the individual columns mapped we can pull them together in a `GetResult` for `Message`.
There are two helper methods which make it easier to construct these instances:

- `<<` for calling the appropriate _nextXXX_ method; and

- `<<?` when the value is optional.

We can use them like this:

```tut:book
implicit val GetMessage = GetResult(r =>
   Message(sender  = r.<<,
           content = r.<<,
           created = r.<<,
           updated = r.<<?,
           id      = r.<<)
 )
```

This works because we've provided implicits for the components of the case class.
As the types of the fields are known, `<<` and `<<?` can use the implicit `GetResult[T]` for the type of each type.

Now we can select into `Message` values:

```tut:book
val action: DBIO[Seq[Message]] =
  sql""" select * from "message" """.as[Message]
```

In all likelihood you'll prefer the lifted embedded style over Plain SQL in this specific example.
But if you do find yourself using Plain SQL, for performance reasons perhaps, it's useful to know how to convert database values up into meaningful domain types.


<div class="callout callout-warning">
**`SELECT *`**

We sometimes use `SELECT *` in this chapter to fit our code examples onto the page.
You should avoid this in your code base as it leads to brittle code.

An example: if, outside of Slick, a table is modified to add a column, the results from the query will unexpectedly change.  You code may not longer be able to map results.
</div>




## Updates

Back in [Chapter 3](#UpdatingRows) we saw how to modify rows with the `update` method.
We noted that batch updates were challenging when we wanted to use the row's current value.
The example we used was appending an exclamation mark to a message's content:

```sql
UPDATE "message" SET "content" = CONCAT("content", '!')
```

Plain SQL updates will allow us to do this. The interpolator is `sqlu`:

```tut:book
val action =
  sqlu"""UPDATE "message" SET "content" = CONCAT("content", '!')"""
```

The `action` we have constructed, just like other actions, is not run until we evaluate it via `db.run`.  But when it is run, it will append the exclamation mark to each row value, which is what we couldn't do as efficiently with the lifted embedded style.

Just like the `sql` interpolator, we also have access to `$` for binding to variables:

```tut:book
val char = "!"
val action =
  sqlu"""UPDATE "message" SET "content" = CONCAT("content", $char)"""
```

This gives us two benefits: the compiler will point out typos in variables names,
but also the input is sanitized against [SQL injection attacks][link-wikipedia-injection].

In this case, the statement that Slick generates will be:

```tut:book
action.statements.head
```


### Updating with Custom Types

Working with basic types like `String` and `Int` is fine, but sometimes you want to update using a richer type.
We saw the `GetResult` type class for mapping select results, and for updates this is mirrored with the `SetParameter` type class.

We can teach Slick how to set `DataTime` parameters like this:

```tut:book
import slick.jdbc.SetParameter

implicit val SetDateTime = SetParameter[DateTime](
  (dt, pp) => pp.setTimestamp(new Timestamp(dt.getMillis))
 )
```

The value `pp` is a `PositionedParameters`. This is an implementation detail of Slick, wrapping a SQL statement and a placeholder for a value.
Effectively we're saying how to treat a `DateTime` regardless of where it appears in the update statement.

In addition to a `Timestamp` (via `setTimestamp`), you can set: `Boolean`, `Byte`, `Short`, `Int`, `Long`, `Float`, `Double`, `BigDecimal`, `Array[Byte]`, `Blob`, `Clob`, `Date`, `Time`, as well as `Object` and `null`.  There are _setXXX_ methods on `PositionedParameters` for `Option` types, too.

There's further symmetry with `GetResuts` in that we could have used `>>` in our `SetParameter`:

```tut:book
implicit val SetDateTime = SetParameter[DateTime](
  (dt, pp) => pp >> new Timestamp(dt.getMillis))
```

With this in place we can construct Plain SQL updates using `DateTime` instances:

```tut:book
val now =
  sqlu"""UPDATE "message" SET "created" = ${DateTime.now}"""
```

Without the `SetParameter[DateTime]` instance the compiler would tell you:

```scala
could not find implicit SetParameter[DateTime]
```



## Typed Checked Plain SQL

We've mentioned the risks of Plain SQL, which can be summarized as not discovering a problem with your query until runtime.  The `tsql` interpolator removes some of this risk, but at the cost of requiring a connection to a database at compile time.

<div class="callout callout-info">
**Run the Code**

These examples won't run in the REPL.
To try these out, use the `tsql.scala` file inside the `chapter-07` folder.
This is all in the [example code base on GitHub][link-example].
</div>

### Compile Time Database Connections

To get started with `tsql` we provide a database configuration information on a class:

```scala
import slick.backend.StaticDatabaseConfig

@StaticDatabaseConfig("file:src/main/resources/application.conf#tsql")
object TsqlExample {
  // queries go here
}
```

The `@StaticDatabaseConfig` syntax is called an _annotation_. This particular `StaticDatabaseConfig` annotation is telling Slick to use the connection called "tsql" in our configuration file.  That entry will look like this:

```scala
tsql {
  profile = "slick.jdbc.H2Profile$"
  db {
    connectionPool = disabled
    url = "jdbc:h2:mem:chapter06; INIT=
       runscript from 'src/main/resources/integration-schema.sql'"
    driver = "org.h2.Driver"
    keepAliveConnection = false
  }
}
```

Note the `$` in the profile class name is not a typo. The class name is being passed to Java's `Class.forName`, but of course Java doesn't have a singleton as such. The Slick configuration does the right thing to load `$MODULE` when it sees `$`. This interoperability with Java is described in [Chapter 29 of _Programming in Scala_][link-pins-interop].

You won't have seen this when we introduced the database configuration in Chapter 1. That's because this `tsql` configuration has a different format, and combines the Slick profile (`slick.jdbcr.H2Profile`) and the JDBC driver (`org.h2.Drvier`) in one entry.

A consequence of supplying a `@StaticDatabaseConfig` is that you can define one databases configuration for your application and a different one for the compiler to use. That is, perhaps you are running an application, or test suite, against an in-memory database, but validating the queries at compile time against a full-populated production-like integration database.

In the example above, and the accompanying example code, we use an in-memory database to make Slick easy to get started with.  However, an in-memory database is empty by default, and that would be no use for checking queries against. To work around that we provide an `INIT` script to populate the in-memory database.
For our purposes, the `integration-schema.sql` file only needs to contain one line:

```sql
create table "message" (
  "content" VARCHAR NOT NULL,
  "id"      BIGSERIAL NOT NULL PRIMARY KEY
);
```


### Type Checked Plain SQL

With the `@StaticDatabaseConfig` in place we can use `tsql`:

```scala
val action: DBIO[Seq[String]] = tsql""" select "content" from "message" """
```

You can run that query as you would `sql` or `sqlu` query.
You can also use custom types via `SetParameter` type class. However, `GetResult` type classes are not supported for `tsql`.

Let's get the query wrong and see what happens:

```scala
val action: DBIO[Seq[String]] =
  tsql"""select "content", "id" from "message""""
```

Do you see what's wrong? If not, don't worry because the compiler will find the problem:

```scala
type mismatch;
[error]  found    : SqlStreamingAction[
                        Vector[(String, Int)],
                        (String, Int),Effect ]
[error]  required : DBIO[Seq[String]]
```

The compiler wants a `String` for each row, because that's what we've declared the result to be.
However it has found, via the database, that the query will return `(String,Int)` rows.

If we had omitted the type declaration, the action would have the inferred type of `DBIO[Seq[(String,Int)]]`.
So if you want to catch these kinds of mismatches, it's good practice to declare the type you expect when using `tsql`.

Let's see other kinds of errors the compiler will find.

How about if the SQL is just wrong:

```scala
val action: DBIO[Seq[String]] =
  tsql"""select "content" from "message" where"""
```

This is incomplete SQL, and the compiler tells us:

```scala
exception during macro expansion: ERROR: syntax error at end of input
[error]   Position: 38
[error]     tsql"""select "content" from "message" WHERE"""
[error]     ^
```

And if we get a column name wrong...

```scala
val action: DBIO[Seq[String]] =
  tsql"""select "text" from "message" where"""
```

...that's also a compile error too:

```scala
Exception during macro expansion: ERROR: column "text" does not exist
[error]   Position: 8
[error]     tsql"""select "text" from "message""""
[error]     ^
```

Of course, in addition to selecting rows, you can insert:

```scala
val greeting = "Hello"
val action: DBIO[Seq[Int]] =
  tsql"""insert into "message" ("content") values ($greeting)"""
```

Note that at run time, when we execute the query, a new row will be inserted.
At compile time, Slick uses a facility in JDBC to compile the query and retrieve the meta data without having to run the query. 
In other words, at compile time the database is not mutated.


## Take Home Points

Plain SQL allows you a way out of any limitations you find with Slick's lifted embedded style of querying.

Two main string interpolators for SQL are provided: `sql` and `sqlu`:

- Values can be safely substituted into Plain SQL queries using `${expression}`.

- Custom types can be used with the interpolators providing an implicit `GetResult` (select) or `SetParameter` (update) is in scope for the type.

- Raw values can be spliced into a query with `#$`. Use this with care: end-user supplied information should never be spliced into a query.

The `tsql` interpolator will check Plain SQL queries against a database at compile time.  The database connection is used to validate the query syntax, and also discover the types of the columns being selected. To make best use of this, always declare the type of the query you expect from `tsql`.


## Exercises

For these exercises we will use a  combination of messages and users.
We'll set this up using the lifted embedded style:

```tut:silent
case class User(
  name  : String,
  email : Option[String] = None,
  id    : Long = 0L
)

class UserTable(tag: Tag) extends Table[User](tag, "user") {
 def id    = column[Long]("id", O.PrimaryKey, O.AutoInc)
 def name  = column[String]("name")
 def email = column[Option[String]]("email")
 def * = (name, email, id).mapTo[User]
}

lazy val users = TableQuery[UserTable]
lazy val insertUsers = users returning users.map(_.id)

case class Message(senderId: Long, content: String, id: Long = 0L)

class MessageTable(tag: Tag) extends Table[Message](tag, "message") {
 def id       = column[Long]("id", O.PrimaryKey, O.AutoInc)
 def senderId = column[Long]("sender_id")
 def content  = column[String]("content")
 def * = (senderId, content, id).mapTo[Message]
}

lazy val messages = TableQuery[MessageTable]

val setup = for {
   _ <- (users.schema ++ messages.schema).create
   daveId <- insertUsers += User("Dave")
   halId  <- insertUsers += User("HAL")
   rowsAdded <- messages ++= Seq(
    Message(daveId, "Hello, HAL. Do you read me, HAL?"),
    Message(halId,  "Affirmative, Dave. I read you."),
    Message(daveId, "Open the pod bay doors, HAL."),
    Message(halId,  "I'm sorry, Dave. I'm afraid I can't do that.")
   )
} yield rowsAdded

val setupResult = exec(setup)
```

### Plain Selects

Let's get warmed up some some simple exercises.

Write the following four queries as Plain SQL queries:

- Count the number of rows in the message table.

- Select the content from the messages table.

- Select the length of each message ("content") in the messages table.

- Select the content and length of each message.

Tips:

- Remember that you need to use double quotes around table and column names in the SQL.

- We gave the database tables names which are singular: `message`, `user`, etc.

<div class="solution">
The SQL statements are relatively simple. You need to take care to make the `as[T]` align to the result of the query.

```tut:book
val q1 = sql""" select count(*) from "message" """.as[Int]
val a1 = exec(q1)

val q2 = sql""" select "content" from "message" """.as[String]
val a2 = exec(q2)
a2.foreach(println)

val q3 = sql""" select length("content") from "message" """.as[Int]
val a3 = exec(q3)

val q4 = sql""" select "content", length("content") from "message" """.as[(String,Int)]
val a4 = exec(q4)
a4.foreach(println)
```

```tut:invisible
assert(a1.head == 4, s"Expected 4 results for a1, not $a1")
assert(a2.length == 4, s"Expected 4 results for a2, not $a2")
assert(a3 == Seq(32,30,28,44), s"Expected specific lenghts, not $a3")
assert(a4.length == 4, s"Expected 4 results for a4, not $a4")
```
</div>

### Conversion

Convert the following lifted embedded query to a Plain SQL query.

```tut:book
val whoSaidThat =
  messages.join(users).on(_.senderId === _.id).
  filter{ case (message,user) =>
    message.content === "Open the pod bay doors, HAL."}.
  map{ case (message,user) => user.name }

exec(whoSaidThat.result)
```

Tips:

- If you're not familiar with SQL syntax, peak at the statement generated for `whoSaidThat` given above.

- Remember that strings in SQL are wrapped in single quotes, not double quotes.

- In the database, the sender's ID is `sender_id`.


<div class="solution">
There are various ways to implement this query in SQL.  Here's one of them...

```tut:book
val whoSaidThat = sql"""
  select
    "name" from "user" u
  join
    "message" m on u."id" = m."sender_id"
  where
    m."content" = 'Open the pod bay doors, HAL.'
  """.as[String]

exec(whoSaidThat)
```
</div>


### Substitution

Complete the implementation of this method using a Plain SQL query:

```tut:book
def whoSaid(content: String): DBIO[Seq[String]] =
  ???
```

Running `whoSaid("Open the pod bay doors, HAL.")` should return a list of the people who said that. Which should be Dave.

This should be a small change to your solution to the last exercise.

<div class="solution">
The solution requires the use of a `$` substitution:

```tut:book
def whoSaid(content: String): DBIO[Seq[String]] =
  sql"""
    select
      "name" from "user" u
    join
      "message" m on u."id" = m."sender_id"
    where
      m."content" = $content
    """.as[String]

exec(whoSaid("Open the pod bay doors, HAL."))

exec(whoSaid("Affirmative, Dave. I read you."))
```
</div>


### First and Last

This H2 query returns the alphabetically first and last messages:

```tut:book
exec(sql"""
  select min("content"), max("content")
  from "message" """.as[(String,String)]
)
```

In this exercise we want you to write a `GetResult` type class instance so that the result of the query is one of these:

```tut:book:silent
case class FirstAndLast(first: String, last: String)
```

The steps are:

1. Remember to `import slick.jdbc.GetResult`.

2. Provide an implicit value for `GetResult[FirstAndLast]`

3. Make the query use `as[FirstAndLast]`

<div class="solution">
```tut:book
import slick.jdbc.GetResult

implicit val GetFirstAndLast =
  GetResult[FirstAndLast](r => FirstAndLast(r.nextString, r.nextString))


val query =  sql""" select min("content"), max("content")
                    from "message" """.as[FirstAndLast]

exec(query)
```
</div>


### Plain Change

We can use Plain SQL to modify the database.
That means inserting rows, updating rows, deleting rows, and also modifying the schema.

Go ahead and create a new table, using Plain SQL, to store the crew's jukebox playlist.
Just store a song title. Insert a row into the table.

<div class="solution">
For modifications we use `sqlu`, not `sql`:

```tut:book
exec(sqlu""" create table "jukebox" ("title" text) """)

exec(sqlu""" insert into "jukebox"("title")
             values ('Bicycle Built for Two') """)

exec(sql""" select "title" from "jukebox" """.as[String])
```
</div>


### Robert Tables

We're building a web site that allows searching for users by their email address:

```tut:book
def lookup(email: String) =
  sql"""select "id" from "user" where "email" = '#${email}'"""

// Example use:
exec(lookup("dave@example.org").as[Long].headOption)
```

What the problem with this code?

<div class="solution">
If you are familiar with [xkcd's Little Bobby Tables](http://xkcd.com/327/),
the title of the exercise has probably tipped you off:  `#$` does not escape input.

This means a user could use a carefully crafted email address to do evil:

```tut:book
val action = lookup("""';DROP TABLE "user";--- """).as[Long]
exec(action)
```

This "email address" turns into two queries:

~~~ sql
SELECT * FROM "user" WHERE "email" = '';
~~~

and

~~~ sql
DROP TABLE "user";
~~~

Trying to access the users table after this will produce:

```tut:book
exec(users.result.asTry)
```

Yes, the table was dropped by the query.

Never use `#$` with user supplied input.
</div>
