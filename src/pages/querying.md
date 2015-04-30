# Querying the Database {#Querying}

The last chapter provided a shallow end-to-end overview of Slick. We saw how to model data, create queries, connect to a database, and run those queries. In this chapter we will look in more detail at the various types of query we can perform on a single table of data. We will:

- learn various methods for building and invoking select queries;
- learn more about inserting, updating, and deleting data;
- look at the similarities between selecting, inserting, and deleting rows;
- learn more about auto-incrementing primary keys.

We'll begin by looking at the most important (and most complex) type of query---the *select* query.

## Select Queries

Select queries are our main means of retrieving data. In this section we'll look at simple select queries that operate on a single table. In [Chapter 4](#joins) we'll look at more complex queries involving joins, agregates, and grouping clauses.

### Selecting All The Rows

The simplest select query is the `TableQuery` generated from a `Table`. In the following example, `messages` is a `TableQuery` for `MessageTable`:

~~~ scala
final class MessageTable(tag: Tag)
    extends Table[Message](tag, "message") {

  def id      = column[Long]("id", O.PrimaryKey, O.AutoInc)
  def sender  = column[String]("sender")
  def content = column[String]("content")

  def * = (sender, content, id) <>
    (Message.tupled, Message.unapply)
}
// defined class MessageTable

lazy val messages = TableQuery[MessageTable]
// messages: scala.slick.lifted.TableQuery[MessageTable] = <lazy>
~~~

The type of `messages` is `TableQuery[MessageTable]`, which is a subtype of a more general `Query` type that Slick uses to represent select, update, and delete queries. We'll discuss these types in the next section.

We can see the SQL of the select query by calling the `selectStatement` method:

~~~ scala
messages.selectStatement
// res11: String = select x2."sender", x2."content", x2."id"
//                 from "message" x2
~~~

Our `TableQuery` is the equivalent of the SQL `SELECT * from message`.

<div class="callout callout-warning">
**Query Extension Methods**

Like many of the "query invoker" methods discussed below, the `selectStatement` method is actually an extension method applied to `Query` via an implicit conversion. You'll need to have everything from `H2Driver.simple` in scope for this to work:

~~~ scala
import scala.slick.driver.H2Driver.simple._
~~~
</div>

### The *filter* Method

We can create a query for a subset of rows using the `filter` method:

~~~ scala
messages.filter(_.sender === "HAL")
// res14: scala.slick.lifted.Query[
//   MessageTable,
//   MessageTable#TableElementType,
//   Seq
// ] = scala.slick.lifted.WrappingQuery@1b4b6544
~~~

The parameter to `filter` is a function from an instance of `MessageTable` to a value of type `Column[Boolean]` representing a `WHERE` clause for our query:

~~~ scala
messages.filter(_.sender === "HAL").selectStatement
// res15: String = select ... where x2."sender" = 'HAL'
~~~

Slick uses the `Column` type to represent expressions over columns as well as individual columns. A `Column[Boolean]` can either be a `Boolean`-valued column in a table, or a `Boolean` expression involving multiple columns. Slick can automatically promote a value of type `A` to a constant `Column[A]`, and provides a suite of methods for building expressions as we shall see below.

### The Query and TableQuery Types

The types in our `filter` expression deserve some deeper explanation. Slick represents all queries using a trait `Query[M, U, C]` that has three type parameters:

 - `M` is called the *mixed* type. This is the function parameter type we see when calling methods like `map` and `filter`.
 - `U` is called the *unpacked* type. This is the type we collect in our results.
 - `C` is called the *collection* type. This is the type of collection we accumulate results into.

In the examples above, `messages` is of a subtype of `Query` called `TableQuery`. Here's a simplified version of the definition in the Slick codebase:

~~~ scala
trait TableQuery[T <: Table[_]] extends Query[T, T#TableElementType, Seq] {
  // ...
}
~~~

A `TableQuery` is actually a `Query` that uses a `Table` (e.g. `MessageTable`) as its mixed type and the table's element type (the type parameter in the constructor, e.g. `Message`) as its unpacked type. In other words, the function we provide to `messages.filter` is actually passed a parameter of type `MessageTable`:

~~~ scala
messages.filter { messageTable: MessageTable =>
  messageTable.sender === "HAL"
}
~~~

This makes sense. `messageTable.sender` is one of the `columns` we defined in `MessageTable` above, and `messageTable.sender === "HAL"` creates a Scala value representing the SQL expression `message.sender = 'HAL'`.

This is the process that allows Slick to type-check our queries. `Queries` have access to the type of the `Table` used to create them, which allows us to directly reference the `Columns` on the `Table` when we're using combinators like `map` and `filter`. Every `Column` knows its own data type, so Slick can ensure we only compare columns of compatible types. If we try to compare `sender` to an `Int`, for example, we get a type error:

~~~ scala
messages.filter(_.sender === 123)
// <console>:16: error: Cannot perform option-mapped operation
//       with type: (String, Int) => R
//   for base type: (String, String) => Boolean
//               messages.filter(_.sender === 123)
//                                        ^
~~~

### The *map* Method

Sometimes we don't want to select all of the data in a `Table`. We can use the `map` method on a `Query` to select specific columns for inclusion in the results. This changes both the mixed type and the unpacked type of the query:

~~~ scala
messages.map(_.content)
// res1: scala.slick.lifted.Query[
//   scala.slick.lifted.Column[String],
//   String,
//   Seq
// ] = scala.slick.lifted.WrappingQuery@407beadd
~~~

Because the unpacked type has changed to `String`, we now have a query that selects `Strings` when run. If we run the query we see that only the `content` of each message is retrieved:

~~~ scala
messages.map(_.content).run
// res2: Seq[String] = Vector(
//   Hello, HAL. Do you read me, HAL?,
//   Affirmative, Dave. I read you.,
//   Open the pod bay doors, HAL.,
//   I'm sorry, Dave. I'm afraid I can't do that.,
//   What if I say 'Pretty please'?)
~~~

Also notice that the generated SQL has changed. The revised query isn't just selecting a single column from the query results---it is actually telling the database to restrict the results to that column in the SQL:

~~~ scala
messages.map(_.sender).selectStatement
// res3: String = select x2."content" from "message" x2
~~~

Finally, notice that the mixed type of our new query has changed to `Column[String]`. This means we are only passed the `content` column if we `filter` or `map` over this query:

~~~ scala
val seekBeauty = messages.
  map(_.content).
  filter(content: Column[String] => content like "%Pretty%")
// seekBeauty: scala.slick.lifted.Query[
//   scala.slick.lifted.Column[String],
//   String,
//   Seq
// ] = scala.slick.lifted.WrappingQuery@6cc2be89

seekBeauty.run
// res4: Seq[String] = Vector(What if I say 'Pretty please'?)
~~~

This change of mixed type can complicate query composition with `map`. We recommend calling `map` only as the final step in a sequence of transformations on a query, after all other operations have been applied.

It is worth noting that we can `map` to anything that Slick can pass to the database as part of a `SELECT` clause. This includes individual `Columns` and `Tables`, as well as `Tuples` of the above. For example, we can use `map` to select the `id` and `content` columns of messages:

~~~ scala
messages.map(t => (t.id, t.content))
// res5: scala.slick.lifted.Query[
//   (Column[Long], Column[String]),
//   (Long, String),
//   Seq
// ] = scala.slick.lifted.WrappingQuery@2a1117d3
~~~

The mixed and unpacked types change accordingly, and the SQL is modified as we might expect:

~~~ scala
messages.map(t => (t.id, t.content)).selectStatement
// res6: String = select x2."id", x2."content" ...
~~~

We can also select column expressions as well as single `Columns`:

~~~ scala
messages.map(t => t.id * 1000L).selectStatement
// res7: String = select x2."id" * 1000 ...
~~~

### Column Expressions

Methods like `filter` and `map` require us to build expressions based on columns in our tables. The `Column` type is used to represent expressions as well as individual columns. Slick provides a variety of extension methods on `Column` for building expressions. Here are the most important ones:

#### Equality, Inequality, and Comparison Methods

The `===` and `=!=` methods operate on any type of `Column` and produce a `Column[Boolean]`. Here are some examples:

~~~ scala
messages.filter(_.sender === "Dave").selectStatement
// res3: String = select ... where x2."sender" = 'Dave'

messages.filter(_.sender =!= "Dave").selectStatement
// res4: String = select ... where not (x2."sender" = 'Dave')
~~~

The `<`, `>`, `<=`, and `>=` methods also operate on any type of `Column` (not just numeric columns):

~~~ scala
messages.filter(_.sender < "HAL").selectStatement
// res7: String = select ... where x2."sender" < 'HAL'

messages.filter(m => m.sender >= m.content).selectStatement
// res8: String = select ... where x2."sender" >= x2."content"
~~~

-------------------------------------------------------------------------
Scala Code       Operand Types        Result Type        SQL Equivalent
---------------- -------------------- ------------------ ----------------
`col1 === col2`  `A` or `Option[A]`   `Boolean`          `col1 = col2`

`col1 =!= col2`  `A` or `Option[A]`   `Boolean`          `col1 <> col2`

`col1 < col2`    `A` or `Option[A]`   `Boolean`          `col1 < col2`

`col1 > col2`    `A` or `Option[A]`   `Boolean`          `col1 > col2`

`col1 <= col2`   `A` or `Option[A]`   `Boolean`          `col1 <= col2`

`col1 >= col2`   `A` or `Option[A]`   `Boolean`          `col1 >= col2`

-------------------------------------------------------------------------

: Column comparison methods.
  Operand and result types should be interpreted as parameters to `Column[_]`.

#### String Column Methods

Slick provides the `++` method for string concatenation (SQL's `||` operator):

~~~ scala
messages.filter(m => m.sender ++ "> " + m.content).selectStatement
// res9: String = select x2."sender" || '> ' || x2."content" ...
~~~

and the `like` method for SQL's classic string pattern matching:

~~~ scala
messages.filter(_.content like "%bay doors%").selectStatement
// res10: String = ... where x2."content" like '%Pretty%'
~~~

Slick also provides methods such as `startsWith`, `length`, `toUpperCase`, `trim`, and so on. These are implemented differently in different DBMSs---the examples below are purely for illustration:

--------------------------------------------------------------------------------------------------------
Scala Code              Operand Column Types               Result Type        SQL Equivalent
----------------------- ---------------------------------- ------------------ --------------------------
`col1.length`           `String` or `Option[String]`       `Int`              `char_length(col1)`

`col1 ++ col2`          `String` or `Option[String]`       `String`           `col1 || col2`

`col1 like col2`        `String` or `Option[String]`       `Boolean`          `col1 like col2`

`col1 startsWith col2`  `String` or `Option[String]`       `Boolean`          `col1 like (col2 || '%')`

`col1 endsWith col2`    `String` or `Option[String]`       `Boolean`          `col1 like ('%' || col2)`

`col1.toUpperCase`      `String` or `Option[String]`       `String`           `upper(col1)`

`col1.toLowerCase`      `String` or `Option[String]`       `String`           `lower(col1)`

`col1.trim`             `String` or `Option[String]`       `String`           `trim(col1)`

`col1.ltrim`            `String` or `Option[String]`       `String`           `ltrim(col1)`

`col1.rtrim`            `String` or `Option[String]`       `String`           `rtrim(col1)`

--------------------------------------------------------------------------------------------------------

: String column methods.
  Operand and result types should be interpreted as parameters to `Column[_]`.

#### Numeric Column Methods

Slick provides a comprehensive set of methods that operate on `Columns` with numeric values: `Ints`, `Longs`, `Doubles`, `Floats`, `Shorts`, `Bytes`, and `BigDecimals`.

--------------------------------------------------------------------------------------------------------
Scala Code              Operand Column Types               Result Type        SQL Equivalent
----------------------- ---------------------------------- ------------------ --------------------------
`col1 + col2`           `A` or `Option[A]`                 `A`                `col1 + col2`

`col1 - col2`           `A` or `Option[A]`                 `A`                `col1 - col2`

`col1 * col2`           `A` or `Option[A]`                 `A`                `col1 * col2`

`col1 / col2`           `A` or `Option[A]`                 `A`                `col1 / col2`

`col1 % col2`           `A` or `Option[A]`                 `A`                `mod(col1, col2)`

`col1.abs`              `A` or `Option[A]`                 `A`                `abs(col1)`

`col1.ceil`             `A` or `Option[A]`                 `A`                `ceil(col1)`

`col1.floor`            `A` or `Option[A]`                 `A`                `floor(col1)`

`col1.round`            `A` or `Option[A]`                 `A`                `round(col1, 0)`

--------------------------------------------------------------------------------------------------------

: Numeric column methods.
  Operand and result types should be interpreted as parameters to `Column[_]`.

#### Boolean Column Methods

Slick also provides a set of methods that operate on boolean `Columns`:

--------------------------------------------------------------------------------------------------------
Scala Code              Operand Column Types               Result Type        SQL Equivalent
----------------------- ---------------------------------- ------------------ --------------------------
`col1 && col2`           `Boolean` or `Option[Boolean]`    `Boolean`          `col1 and col2`

`col1 || col2`           `Boolean` or `Option[Boolean]`    `Boolean`          `col1 or col2`

`!col1`                  `Boolean` or `Option[Boolean]`    `Boolean`          `not col1`

--------------------------------------------------------------------------------------------------------

: Boolean column methods.
  Operand and result types should be interpreted as parameters to `Column[_]`.

#### Optional Column Methods

Slick models nullable columns in SQL as `Columns` with `Option` types. If we have a nullable column in our database, we should always declare it as optional in our `Table`:

~~~ scala
final class PersonTable(tag: Tag) /* ... */ {
  // ...
  def nickname = column[Option[String]]("nickname")
  // ...
}
~~~

Sometimes it's necessary to convert from a non-nullable column to a nullable one in a query. For example, if we're performing an outer join on two tables, it is always possible that columns in one table will contain `null` values. In these circumstances, we can convert a non-`Optional` column into an `Optional` one using the `?` operator:

~~~ scala
messages.map(_.sender.?)
// res19: scala.slick.lifted.Query[
//   scala.slick.lifted.Column[Option[String]],
//   Option[String],
//   Seq
// ] = scala.slick.lifted.WrappingQuery@38e47d45
~~~

Veterans of database administration will be familiar with an interesting quirk of SQL: expressions involving `null` themselves evaluate to `null`. For example, the SQL expression `'Dave' = 'HAL'` evaluates to `true`, whereas the expression `'Dave' = null` evaluates to `null`.

Null comparison is a classic source of errors for inexperienced SQL developers. No value is actually equal to `null`---the equality check evaluates to `null`. To resolve this issue, SQL provides two operators: `IS NULL` and `IS NOT NULL`, which are provided in Slick by the methods `isEmpty` and `isDefined` defined on any `Column[Option[A]]`:

~~~ scala
messages.filter(_.sender.?.isEmpty).selectStatement
// res20: String = select ... where x2."sender" is null

messages.filter(_.sender.?.isDefined).selectStatement
// res21: String = select ... where x2."sender" is not null
~~~

--------------------------------------------------------------------------------------------------------
Scala Code              Operand Column Types               Result Type        SQL Equivalent
----------------------- ---------------------------------- ------------------ --------------------------
`col1.?`                `A`                                `A`                `col1`

`col1.isEmpty`          `Option[A]`                        `Boolean`          `col1 is null`

`col1.isDefined`        `Option[A]`                        `Boolean`          `col1 is not null`

--------------------------------------------------------------------------------------------------------

: Optional column methods.
  Operand and result types should be interpreted as parameters to `Column[_]`.

<div class="callout callout-danger">
TODO: The examplesfor `isEmpty` and `isDefined` above aren't great. We should have a table with a nullable column in it so we can use that instead of `_.sender.?`.
</div>

### Type Equivalence in Column Expressions

Slick type-checks our column expressions to make sure the operands are of compatible types. For example, we can compare `Strings` for equality but we can't compare a `String` and an `Int`:

~~~ scala
messages.filter(_.id === "foo")
// <console>:14: error: Cannot perform option-mapped operation
//       with type: (Long, String) => R
//   for base type: (Long, Long) => Boolean
//               messages.filter(_.id === "foo").selectStatement
//                                    ^
~~~

Interestingly, Slick is very finickity about numeric types. For example, comparing an `Int` to a `Long` is considered a type error:

~~~ scala
messages.filter(_.id === 123)
// <console>:14: error: Cannot perform option-mapped operation
//       with type: (Long, Int) => R
//   for base type: (Long, Long) => Boolean
//               messages.filter(_.id === 123).selectStatement
//                                    ^
~~~

On the flip side of the coin, Slick is clever about the equivalence of `Optional` and non-`Optional` columns. As long as the operands are some combination of the types `A` and `Option[A]` (for the same value of `A`), the query will normally compile:

~~~ scala
messages.filter(_.id === Option(123L)).selectStatement
// res16: String = select ... where x2."id" = 123
~~~

However, any `Optional` arguments must be strictly of type `Option`, not `Some` or `None`:

~~~ scala
messages.filter(_.id === Some(123L)).selectStatement
// <console>:14: error: type mismatch;
//  found   : Some[Long]
//  required: scala.slick.lifted.Column[?]
//               messages.filter(_.id === Some(123L)).selectStatement
//                                            ^
~~~

### TODO: Select Query Exercises (and Take Home Points?)

<div class="callout callout-danger">
**TODO: Select Query Exercises (and Take Home Points?)**
</div>

## Deleting Rows

In the last chapter we saw a query to select all the messages from HAL:

~~~ scala
val halSays = messages.filter(_.sender === "HAL")
~~~

We can use that query to delete all the messages from HAL:

~~~ scala
db.withSession {
  implicit session =>
    val rowCount = halSays.delete
}
~~~

Rather than `run`ing this query, we are `delete`ing the rows selected by the query. The result of `delete` is an `Int`. It's the number of rows deleted, and in this case it will be 2.

As you might expect the SQL from running this delete is:

~~~ sql
delete from "message" where "message"."sender" = 'HAL'
~~~

<div class="callout callout-info">
**Logging Queries and Results**

In the previous chapter we noted you can see the SQL Slick would use by calling `selectStatement` on a query. There's also `deleteStatement` and `updateStatement`.  These are useful to see the SQL that would be produced by a query, but sometimes you want to see all the queries _when Slick executes them_.  You can do that by configuring logging.

Slick uses a logging framework called [SLF4J][link-slf4j].  You can configure this to capture information about the queries being run.  The example GitHub project uses a logging back-end called [_Logback_][link-logback], which is configured in the file _src/main/resources/logback.xml_.  In that file we enable statement logging by turning up the logging to debug level. For example:

~~~ xml
<logger name="scala.slick.jdbc.JdbcBackend.statement" level="DEBUG"/>
~~~

When we next run a query, delete or update rows, and even modify the schema, each statement will be recorded on standard output or wherever you configure it to go:

~~~
DEBUG s.slick.jdbc.JdbcBackend.statement - Preparing statement:
  delete from "message" where "message"."sender" = 'HAL'
~~~

You can enable a variety of events to be logged:

* `scala.slick.jdbc.JdbcBackend.statement` --- which is for statement logging, as you've seen.
* `scala.slick.jdbc.StatementInvoker.result` --- which logs the results of a query.
* `scala.slick.session` --- for session information, such as connections being opened.
* `scala.slick` --- for everything!  This is usually too much.


The `StatementInvoker.result` logger is pretty cute:

~~~
SI.result - /--------+----------------------+----------------------+----\
SI.result - | sender | content              | ts                   | id |
SI.result - +--------+----------------------+----------------------+----+
SI.result - | HAL    | Affirmative, Dave... | 2001-02-17 10:22:... | 2  |
SI.result - | HAL    | I'm sorry, Dave. ... | 2001-02-17 10:22:... | 4  |
SI.result - \--------+----------------------+----------------------+----/
~~~
</div>

There's not a lot more to say about deleting data. If you have a query that selects a table, then you can use it to delete rows.

But to expand on that, consider this variation on the `halSays` query:

~~~ scala
val halText = halSays.map(_.content)
~~~

That's a valid query, and will select just the `content` column from the `messages` table.  You'll find you cannot use that query with `delete`, as it'll be a compile error. The method `delete` is not defined for this kind of query. `halText` is of type `Query[Column[String], String, Seq]`, whereas `halSays` is of type `Query[MessageTable, Message, Seq]`.

### `Column[T]`

What is this `Column[String]` and why can't we delete using it?

Recall we defined the column `content` as:

~~~ scala
def content = column[String]("content")
~~~

The method `column` evaluates, in this case, to a `Column[String]`. When we construct a query to return a column, the query will be in terms of a `Column[String]`.  When we count the number of rows in a table, the query will be in terms of `Column[Int]`.  More generally, a single value from the database will be a `Column[T]` in the context of a query.

All the operations you can perform on a column, such as `like` or `toLowerCase`, are added onto `Column[T]` via _extension methods_. These are implicit conversions provided by Slick.  If you're keen, you can go look at them all in the Slick source file [ExtensionMethods.scala][link-source-extmeth].

So `Column[T]` is for values, and deleting based on a value makes no sense in Slick or SQL. Imagine the query `SELECT 42`. You can represent this in Slick as `Query(42)`. You can `run` the query, but you cannot `delete` on it. But deleting on a table, like `MessageTable`, that makes more sense.


### Exercises

Experiment with the queries we discuss before trying the exercises in this chapter. The code for this chapter is in the [GitHub repository][link-example] in the _chapter-02_ folder.  As with chapter 1, you can use the `run` command in SBT to execute the code against a H2 database.

#### Delete All The Messages

How would you delete all messages?

<div class="solution">
~~~ scala
val deleted = messages.delete
~~~
</div>




## Inserting a Row

As we saw in chapter 1, adding new rows to a table also looks like a collections operation:

~~~ scala
val result =
  messages += Message("HAL", "I'm back", DateTime.now)
~~~

The `+=` method is an alias for `insert`, so if you prefer you can write:

~~~ scala
val result =
  messages insert Message("HAL", "I'm back", DateTime.now)
~~~

The `result` this will give is the number of rows inserted. However, it is often useful to return something else, such as the primary key or the case class with the primary key populated.

<div class="callout callout-info">
**Automatic Primary Key Generation**

In our example the `id` field of the `Message` case class maps to the primary key of the table. This value was filled in for us by Slick when we inserted the row.

Recall the definition of `Message`:

~~~ scala
final case class Message(sender: String, content: String, ts: DateTime, id: Long = 0L)
~~~

Putting the `id` at the end and giving it a default value is a trick that allows us to simply write `Message("HAL", "I'm back", DateTime.now)` and not mention `id`.  The [rules of named and default arguments][link-sip-named-default] would allow us to put `id` first, but then we'd need to name the other field values: `Message(sender="HAL", ...)`.

Note that there's nothing special about the `0L` for the `id`. It's _not_ a magic value meaning "this record has no `id`".  Instead, what is happening here is that Slick recognizes
that the column was defined as auto-incrementing:

~~~ scala
def id = column[Long]("id", O.PrimaryKey, O.AutoInc)
~~~~

Slick excludes `O.AutoInc` columns when inserting rows, allowing the database to step in an generate the value for us. (If you really do need to insert a value in place of an auto incrementing value, the method `forceInsert` is there for you.)

This is just one way of dealing with automatically generated primary keys. We will look at working with `Option[T]` values in chapter 3.
</div>

Let's modify the insert to give us back the primary key generated:

~~~ scala
val result =
  (messages returning messages.map(_.id)) += Message("HAL", "I'm back", DateTime.now)
~~~

The argument to `messages returning` is a `Query`, which is why `messages.map(_.id)` makes sense there.  Some databases allow you return values other than just the auto incremented value. For example, we could ask for the whole `Message` back:

~~~ scala
val result: Message =
  (messages returning messages) += Message("HAL", "I'm back", DateTime.now)
~~~

Unfortunately, H2 isn't one of the databases to support this. If you tried the above you'll be told:

~~~
This DBMS allows only a single AutoInc column to be returned from an INSERT
~~~

That's a shame, but getting the primary key is often all that's needed. However, typing `messages returning messages.map(_.id)` isn't exactly convenient. If this is something you need to do often, define a query that does it for you at the same point in the code where `messages` is defined:

~~~ scala
lazy val messagesInsert = messages returning messages.map(_.id)
~~~

This allows us to insert and get the primary key in one shorter expression:

~~~ scala
val id: Long = messagesInsert += Message("HAL", "I'm back", DateTime.now)
~~~

<div class="callout callout-info">
**Driver Capabilities**

You can find out the capabilities of different databases in the Slick manual page for [Driver Capabilities][link-ref-dbs].  For the example in this section it's the `jdbc.returnInsertOther` capability.

The Scala Doc for each driver also lists the capabilities the driver _does not_ have. For an example, take a look at the top of the [H2 Driver Scala Doc][link-ref-h2driver] page.
</div>

If we do want to get a populated `Message` back from an insert for any database, with the auto-generated `id` set, we can write a method to do that.  It would take a message as an argument, insert it returning the `id`, and then give back a copy the message setting the `id`. This would emulate the `jdbc.returnInsertOther` capability.

However, we don't need to write that method as Slick's `into` does the job:

~~~ scala
val messagesInsertWithId =
  messages returning messages.map(_.id) into { (m, i) => m.copy(id=i) }

val result: Message =
  messagesInsertWithId += Message("HAL", "I'm back", DateTime.now)
~~~

The `result` will be the message with the auto-generated `id` field correctly set.

That's one example, but `into` is a general purpose client-side transformation. That is, it runs in your Scala application and not the database. Any `returning` expression can have an `into`.  The `into` part is a function from the type being inserted and the type returned, to some other type. In the above example the type of the `into` function is:

~~~ scala
(Message, Long) => Message
~~~


## Inserting Multiple Rows

Let's say we have a number of messages we want to insert. You could just `+=` each one in turn, and that would work.  However, each one of those inserts will be sent to the database individually, and the result returned. This can be slow for large numbers of inserts.

As an alternative, Slick supports batch inserts, where all the inserts are sent to the database in one go. We've seen this already in the first chapter:

~~~ scala
val start = new DateTime(2001,2,17, 10,22,50)

messages ++= Seq(
  Message("Dave", "Hello, HAL. Do you read me, HAL?",             start),
  Message("HAL",  "Affirmative, Dave. I read you.",               start plusSeconds 2),
  Message("Dave", "Open the pod bay doors, HAL.",                 start plusSeconds 4),
  Message("HAL",  "I'm sorry, Dave. I'm afraid I can't do that.", start plusSeconds 6)
)
~~~

The above code will prepare one statement (the insert) and use that one statement for each row. In comparison, inserting each message individually will produce four statements.  It's a saving in time that's worth having.

You already know that with single inserts you can see the number of rows inserted and get at the auto incremented values, if you want to.  Let's see how that works for batch inserts because there are some differences.

The result of the above `messages ++= ...` code is an `Option[Int]`.  Specifically, it's `Some(4)`. It's optional because the underlying JDBC specifications permits the database to indicate that the number of rows is unknown for batch inserts. In that situation, Slick cannot give a count even though the insert will have succeeded.

The batch version of `messages returning...`, including `into`, is also available for batch inserts. We can use the `messagesInsert` query and write:

~~~ scala
val ids = messagesInsert ++= Seq(
  Message("Dave", "Hello, HAL. Do you read me, HAL?",             start),
  Message("HAL",  "Affirmative, Dave. I read you.",               start plusSeconds 2),
  Message("Dave", "Open the pod bay doors, HAL.",                 start plusSeconds 4),
  Message("HAL",  "I'm sorry, Dave. I'm afraid I can't do that.", start plusSeconds 6)
)
~~~

The result will be a list of the auto-incremented `id` fields, as a `List[Long]`. However, this will be executed as four separate statements, rather than one. This is because returning column values from a batch insert is not, on the whole, supported by databases.


<div class="callout callout-info">
**Invokers**

Queries don't directly expose the methods to execute a query. The execution methods are instead defined by a trait called `Invoker`.  There are query invokers, row counting insert invokers, returning insert invokers, update invokers, delete invokers... and others.  This is where you will find methods like `firstOption`, `list` or `delete`.

If you looked at the invoker for `messagesInsert`, which you can via `messagesInsert.insertInvoker`, you would see that it is a `ReturningInsertInvoker`.  It is there that Slick switches to turning the bulk insert into a useful sequence of individual inserts.

We don't generally talk about invokers as Slick provides them implicitly.
</div>


### Transactions

So far all the database interactions we've seen have run independently.
That is, each query, delete, or update succeeds or fails and is automatically committed to the database.

A transaction allows you to rollback changes to the database if later ones fail, or if you detect a situation where you want to manually rollback.  The scope of the transaction starts with a call to `session.withTransaction` and ends when the `withTransaction` block ends:

~~~ scala
session.withTransaction {
  // ...quries, updates, deletes ...
}
~~~

At the end of the transaction, providing there were no exceptions or calls to `session.rollback`, the changes are committed to the database.

You might always want a transaction. In that case, you can get a session with `db.withTransaction` in place of calls to `db.withSession`.


### Exercises


#### Insert New Messages Only

Messages sent over a network might fail, and might be resent.  Write a method that will insert a message for someone, but only if the message content hasn't already been stored. We want the `id` of the message as a result.

The signature of the method is:

~~~ scala
def insertOnce(sender: String, message: String): Long = ???
~~~

<div class="solution">
~~~ scala
def insertOnce(sender: String, text: String)(implicit session: Session): Long = {
  val query =
    messages.filter(m => m.content === text && m.sender === sender).map(_.id)

  query.firstOption getOrElse {
    (messages returning messages.map(_.id)) += Message(sender, text, DateTime.now)
  }
}
~~~
</div>


#### Rollback

Assuming you already have an `implicit session`, what is the state of the database after this code is run?

~~~ scala
session.withTransaction {
  messages.delete
  session.rollback()
  messages.delete
  println("Surprised?")
}
~~~

Is "Surprised?" printed?

<div class="solution">
The call to `rollback` only impacts Slick calls.

This means the two calls to `delete` will have no effect: the database will have the same message records it had before this block of code was run.

It also means the message "Surprised?" will be printed.
</div>


## Updating Rows

In all the rows we've created so far we've referred to "HAL". That's a computer from the film _2001: A Space Odyssey_, but the correct name is "HAL 9000".  Let's fix that:

~~~ scala
val rowsAffected: Int =
  messages.filter(_.sender === "HAL").map(_.sender).update("HAL 9000")
~~~

If we break this down it may be easier to see the same patterns we've used elsewhere:

~~~ scala
val queryForHAL  = messages.filter(_.sender === "HAL")
val selectSender = queryForHal.map(_.sender)
val rowsAffected: Int = selectSender.update("HAL 9000")
~~~

We're selecting the messages from HAL, and composing that query to just return the `sender` field. Then we can call `update` and supply a new value for the sender.

This update is equivalent to the SQL:

~~~ sql
UPDATE "message" SET "sender" = 'HAL 9000' WHERE "sender" = 'HAL'
~~~

We can also update multiple columns at the same time. We can fix HAL's name and change the timestamp on the message to "now":

~~~ scala
val rowsAffected =
  messages.filter(_.sender === "HAL").map(msg => (msg.sender, msg.ts)).update("HAL 9000", DateTime.now)
~~~

Now we are selecting a _tuple_ of `(sender, ts)`, which means `update` expects us to supply two values.  The SQL will be something like this:

~~~ sql
UPDATE  "message"
  SET   "sender" = 'HAL 9000', "ts" = '2015-01-29 15:02'
  WHERE "sender" = 'HAL'
~~~

### Exercises


#### Update Using a For Comprehension

Rewrite the update statement below to use a for comprehension.

~~~ scala
val rowsAffected =
  messages.filter(_.sender === "HAL").map(msg => (msg.sender, msg.ts)).update("HAL 9000", DateTime.now)
~~~

Which style do you prefer?

<div class="solution">
~~~ scala
val query = for {
  message <- messages
  if message.sender === "HAL"
} yield (message.sender, message.ts)

val rowsAffected = query.update("HAL 9000", DateTime.now)
~~~
</div>


#### Client-Side or Server-Side?

What does this do...

~~~ scala
messages.map(_.content + "!").list
~~~

...and why?

<div class="solution">
The query Slick generates looks something like this:

~~~ sql
select '(message Path @1413221682).content!' from "message"
~~~

That is, a select expression for a strange constant string.

The `_.content + "!"` expression converts `content` to a string and appends the exclamation point. What is `content`? It's a `Column[String]`, not a `String` of the content. The end result is that we're seeing something of the internal workings of Slick.

This is an unfortunate effect of Scala allowing automatic conversion to a `String`. If you are interested in disabling this Scala behaviour, tools like [WartRemover][link-wartremover] can help.

It is possible to do this mapping in the database with Slick.  We just need to remember to
work in terms of `Column[T]` classes:

~~~ scala
messages.map(m => m.content ++ LiteralColumn("!")).run
~~~

Here `LiteralColumn[T]` is type of `Column[T]` for holding a constant value to be inserted into the SQL.  The `++` method is one of the extension methods defined for any `Column[String]`.

This will produce the desired result:

~~~ sql
select "content"||'!' from "message"
~~~
</div>


## Updating with a Computed Value

Let's now turn to more interesting updates. How about converting every message to be all capitals. Or adding an exclamation mark to the end of each message.  Both of these examples need us to do something to each row in turn.  In SQL it might be something like:

~~~ sql
UPDATE "message" SET "content" = CONCAT("content", '!')
~~~

This is not currently supported by `update` in Slick. But there are ways to achieve the same result.

The way we'd recommend is to use plain SQL updates, which we turn to in [Chapter 5](#PlainSQL).  However, it's worth knowing that you can also solve this with a client side update.

### Client Side Update

Let's define a Scala function to capture how we want to change each row:

~~~ scala
def exclaim(msg: Message): Message =
  msg.copy(content = msg.content + "!")
~~~

This is a standard _copy constructor_ in Scala which will take a `Message` and return a copy, with only the `content` field modified.  The `id`, `ts`, `sender`, will all be unchanged.

Using this we can update the rows in the database:

~~~ scala
messages.list.map(exclaim).foreach {
  m => messages.filter(_.id === m.id).update(m)
}
~~~

The steps here are:

1. Select all the messages in the table (`messages.list`)
2. In Scala, create new `Message`s with the desired change (`map(exclaim)`)
3. For each row, update the row in the database (`foreach { ... }`)

This results in _N + 1_ queries, where _N_ is the number of rows selected.  That may be excessive, depending on what your needs are.



## Take Home Points

For modifying the rows in the database we have seen that:

* deletes are via a `delete` call to a query;
* updates are via an `update` call on a query, but are somewhat limited; and
* inserts are via an `insert` (or `+=`) call on a table.

Auto-incrementing values are not inserted by Slick, unless forced. The auto-incremented values can be returned from the insert by using `returning`.

Databases have different capabilities. The limitations of each driver is listed in the driver's Scala Doc page.

Rows can be inserted in batch. For simple situations this gives performance gains. However when additional information is required back (such as primary keys), there is no advantage.

The SQL statements executed and the result returned from the database can be monitored by configuring the logging system.

