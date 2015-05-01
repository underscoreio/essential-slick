# Selecting Data {#Selecting}

The last chapter provided a shallow end-to-end overview of Slick. We saw how to model data, create queries, connect to a database, and run those queries. In the next two chapters we will look in more detail at the various types of query we can perform in Slick.

This chapter covers *selecting* data using Slick's rich type-safe Scala reflection of SQL. [Chapter 3](#Modifying) covers *modifying* data by inserting, updating, and deleting records. Later on, in [Chapter 4](#joins), we cover advanced select queries such as joins and aggregates.

Select queries are our main means of retrieving data. In this section we'll look at simple select queries that operate on a single table. In [Chapter 5](#joins) we'll look at more complex queries involving joins, agregates, and grouping clauses.

## Selecting All The Rows

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

## The *filter* Method

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

## The Query and TableQuery Types

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

## The *map* Method

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

## Column Expressions

Methods like `filter` and `map` require us to build expressions based on columns in our tables. The `Column` type is used to represent expressions as well as individual columns. Slick provides a variety of extension methods on `Column` for building expressions. Here are the most important ones:

### Equality and Inequality Methods

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

### String Methods

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

### Numeric Methods

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

### Boolean Methods

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

### Option Methods

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

## Type Equivalence in Column Expressions

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

## Query Invokers

<div class="callout callout-danger">
TODO: Put this somewhere better in the content above.
</div>

Each database product (H2, Oracle, PostgresSQL, and so on) has a different take on how queries should be constructed, how data should be represented, and what capabilities are implemented. This is abstracted by the Slick *driver*.  We import the right driver for the database we are using.

With that import done we set up our database connection, `db`, by providing `Database` with a JDBC connection string, and the class name of the JDBC driver being used.  Yes, there are two kinds of *driver* being used: Slick's abstraction is called a driver; and it uses a JDBC driver too.

From our database connection we can obtain a session. Sessions are required by Slick methods that need to actually go and communicate with the database.  Typically the session parameter is marked as `implicit`, meaning you do not have to manually supply the parameter.  We're doing this
in the code sample above as `run` requires a session, and the session it uses is the one we defined as implicit.

With a session we can execute our query. There are a number of calls you can make on a query, as listed in the table below.

==================================================================
Method          Executes the query and will:
===========     ==================================================
 `execute`      Ignore the result.

 `first`        Return the first result, or throw an exception if there is no result.

 `firstOption`  Return `Some[T]` for the first result; `None` if there is no result.

 `list`         Return a fully populated `List[T]` of the results.

 `iterator`     Provides an iterator over the results.

 `run`          Acts like `first` for queries for a value, but something like `list` for a collection
                of values.
===========     ==================================================

: A Selection of Statement Invokers

For now we're using `run`, which will return the results of the query as a collection.

## Take Home Points

<div class="callout callout-danger">
TODO: Take Home Points
</div>

## Exercises

We want to make sure you have your environment set up, and can experiment with Slick.  If you've not already done so, try out the above code.  In the [example project][link-example] the code is in _main.scala_ in the folder _chapter-01_.

Once you've done that, work through the exercises below.  An easy way to try things out is to use  _triggered execution_ with SBT:

~~~ bash
$ cd example-01
$ sbt
> ~run
~~~

That `~run` will monitor the project for changes, and when a change is seen, the _main.scala_ program will be compiled and run. This means you can edit _main.scala_ and then look in your terminal window to see the output.

### Count the Messages

How would you count the number of messages? Hint: in the Scala collections the method `length` gives you the size of the collection.

<div class="solution">
~~~ scala
val results = halSays.length.run
~~~

You could also use `size`, which is an alias for `length`.
</div>

### Selecting a Message

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

### One Liners

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


### Selecting Columns

So far we have been returning `Message` classes or counts.  Select all the messages in the database, but return just their contents.  Hint: think of messages as a collection and what you would do to a collection to just get back a single field of a case class.

Check what SQL would be executed for this query.

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

### First Result

The methods `first` and `firstOption` are useful alternatives to `run`. Find the first message that HAL sent.  What happens if you use `first` to find a message from "Alice" (note that Alice has sent no messages).

<div class="solution">
~~~ scala
val msg1 = messages.filter(_.sender === "HAL").map(_.content).first
println(msg1)
~~~

You should get "Affirmative, Dave. I read you."

For Alice, `first` will throw a run-time exception. Use `firstOption` instead.
</div>


### The Start of Something

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


### Liking

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

There are three results: "_Do_ you read me", "Open the pod bay *do*ors", and "I'm afraid I can't _do_ that".
</div>
