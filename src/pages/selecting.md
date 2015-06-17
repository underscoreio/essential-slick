# Selecting Data {#Selecting}

The last chapter provided a shallow end-to-end overview of Slick. We saw how to model data, create queries, connect to a database, and run those queries. In the next two chapters we will look in more detail at the various types of query we can perform in Slick.

This chapter covers *selecting* data using Slick's rich type-safe Scala reflection of SQL. [Chapter 3](#Modifying) covers *modifying* data by inserting, updating, and deleting records.

Select queries are our main means of retrieving data. In this chapter we'll limit ourselves to simple select queries that operate on a single table. In [Chapter 5](#joins) we'll look at more complex queries involving joins, aggregates, and grouping clauses

## Select All The Rows!

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
// messages: slick.lifted.TableQuery[Example.MessageTable] = <lazy>
~~~

The type of `messages` is `TableQuery[MessageTable]`, which is a subtype of a more general `Query` type that Slick uses to represent select, update, and delete queries. We'll discuss these types in the next section.

We can see the SQL of the select query by calling `result.statements`:

~~~ scala
messages.result.statements
// res12: Iterable[String] = List(select x2."sender", x2."content", x2."id" from "message" x2)
~~~

Our `TableQuery` is the equivalent of the SQL `SELECT * from message`.

<div class="callout callout-warning">
**Query Extension Methods**

Like many of the methods discussed below, the `result` method is actually an extension method applied to `Query` via an implicit conversion.
You'll need to have everything from `H2Driver.simple` in scope for this to work:

~~~ scala
import slick.driver.H2Driver.api._
~~~
</div>

## Filtering Results: The *filter* Method

We can create a query for a subset of rows using the `filter` method:

~~~ scala
messages.filter(_.sender === "HAL")
// res13: slick.lifted.Query[
//   MessageTable,
//   MessageTable#TableElementType,
//   Seq
// ] = Rep(Filter)
~~~


The parameter to `filter` is a function from an instance of `MessageTable` to a value of type `Rep[Boolean]` representing a `WHERE` clause for our query:

~~~ scala
messages.filter(_.sender === "HAL").result.statements
// res13: Iterable[String] = List(select x2."sender", x2."content", x2."id" from "message" x2 where x2."sender" = 'HAL')
~~~

Slick uses the `Rep` type to represent expressions over columns as well as individual columns.
A `Rep[Boolean]` can either be a `Boolean`-valued column in a table,
or a `Boolean` expression involving multiple columns.
Slick can automatically promote a value of type `A` to a constant `Rep[A]`,
and provides a suite of methods for building expressions as we shall see below.

## The Query and TableQuery Types {#queryTypes}

The types in our `filter` expression deserve some deeper explanation.
Slick represents all queries using a trait `Query[M, U, C]` that has three type parameters:

 - `M` is called the *mixed* type. This is the function parameter type we see when calling methods like `map` and `filter`.
 - `U` is called the *unpacked* type. This is the type we collect in our results.
 - `C` is called the *collection* type. This is the type of collection we accumulate results into.

In the examples above, `messages` is of a subtype of `Query` called `TableQuery`.
Here's a simplified version of the definition in the Slick codebase:

~~~ scala
trait TableQuery[T <: Table[_]] extends Query[T, T#TableElementType, Seq] {
  // ...
}
~~~

A `TableQuery` is actually a `Query` that uses a `Table` (e.g. `MessageTable`) as its mixed type and the table's element type (the type parameter in the constructor, e.g. `Message`) as its unpacked type.
In other words, the function we provide to `messages.filter` is actually passed a parameter of type `MessageTable`:

~~~ scala
messages.filter { messageTable: MessageTable =>
  messageTable.sender === "HAL"
}
~~~

This makes sense. `messageTable.sender` is one of the `columns` we defined in `MessageTable` above,
and `messageTable.sender === "HAL"` creates a Scala value representing the SQL expression `message.sender = 'HAL'`.

This is the process that allows Slick to type-check our queries.
`Queries` have access to the type of the `Table` used to create them,
which allows us to directly reference the `Columns` on the `Table` when we're using combinators like `map` and `filter`.
Every `Column` knows its own data type, so Slick can ensure we only compare columns of compatible types.
If we try to compare `sender` to an `Int`, for example, we get a type error:

~~~ scala
messages.filter(_.sender === 123)
// <console>:16: error: Cannot perform option-mapped operation
//       with type: (String, Int) => R
//   for base type: (String, String) => Boolean
//               messages.filter(_.sender === 123)
//                                        ^
~~~

## Transforming Results: The *map* Method

Sometimes we don't want to select all of the data in a `Table`.
We can use the `map` method on a `Query` to select specific columns for inclusion in the results.
This changes both the mixed type and the unpacked type of the query:

~~~ scala
messages.map(_.content)
// res1: slick.lifted.Query[
//   slick.lifted.Rep[String],
//   String,
//   Seq
// ] = slick.lifted.Query
~~~

Because the unpacked type has changed to `String`,
we now have a query that selects `Strings` when run.
If we run the query we see that only the `content` of each message is retrieved:

~~~ scala
exec(messages.map(_.content).result)
// res2: Seq[String] = Vector(
//   Hello, HAL. Do you read me, HAL?,
//   Affirmative, Dave. I read you.,
//   Open the pod bay doors, HAL.,
//   I'm sorry, Dave. I'm afraid I can't do that.,
//   What if I say 'Pretty please'?)
~~~

Also notice that the generated SQL has changed.
The revised query isn't just selecting a single column from the query results---it is actually telling the database to restrict the results to that column in the SQL:

~~~ scala
messages.map(_.sender).result.statements
// res14: Iterable[String] = List(select x2."sender" from "message" x2)
~~~

Finally, notice that the mixed type of our new query has changed to `Rep[String]`.
This means we are only passed the `content` column if we `filter` or `map` over this query:

~~~ scala
val seekBeauty = messages.
  map(_.content).
  filter{content:Rep[String] => content like "%Pretty%" }

// seekBeauty: slick.lifted.Query[
//   slick.lifted.Rep[String],
//   String,
//   Seq
// ] = Rep(Filter)

 exec(seekBeauty.result)
// res4: Seq[String] = Vector(What if I say 'Pretty please'?)
~~~


This change of mixed type can complicate query composition with `map`.
We recommend calling `map` only as the final step in a sequence of transformations on a query,
after all other operations have been applied.

It is worth noting that we can `map` to anything that Slick can pass to the database as part of a `SELECT` clause.
This includes individual `Rep`s and `Table`s,
as well as `Tuples` of the above.
For example, we can use `map` to select the `id` and `content` columns of messages:

~~~ scala
messages.map(t => (t.id, t.content))
// res10: slick.lifted.Query[
//    (slick.lifted.Rep[Long], slick.lifted.Rep[String]),
//    (Long, String),
//     Seq
// ] = Rep(Bind)
~~~

The mixed and unpacked types change accordingly,
and the SQL is modified as we might expect:

~~~ scala
messages.map(t => (t.id, t.content)).result.statements
res11: Iterable[String] = List(select x2."id", x2."content" from "message" x2)
~~~

We can also select column expressions as well as single `Columns`:

~~~ scala
messages.map(t => t.id * 1000L).result.statements
// res7: Iterable[String] = List(select x2."id" * 1000 from "message" x2)
~~~

<!--
<div class="callout callout-info">
**Query's *flatMap* method**

`Query` also has a `flatMap` method with similar monadic semantics to that of `Option` or `Future`. `flatMap` is mostly used for joins, so we'll cover it in [Chapter 5](#joins).
</div>
-->

## Running queries

<!-- This needs more work than Joan Rivers has had -->
Once we've built a query, we need to run it.
There are two ways to do this, we have seen the first already, Materialized.
Materalized queries are the *normal* way of running a query, execute the query return all the results.
The other way to run queries is by streaming back the results.
This, as you can imagine this is great for returning huge datasets without consuming large amounts of memory.
To stream results we call `stream` on the database object, it returns a [`DatabasePublisher`][link-source-dbPublisher].
`DatabasePublisher` exposes 3 methods to interact with the stream.
`subscribe` which allows integration with Akka,
`mapResult` which creates a new `Publisher` that maps the supplied function on the result set from the original publisher.
Finally, there is the convenience method `foreach`.


## Column Expressions

Methods like `filter` and `map` require us to build expressions based on columns in our tables.
The `Rep` type is used to represent expressions as well as individual columns.
Slick provides a variety of extension methods on `Rep` for building expressions.

We will cover the most common methods below.
You can find a complete list in [ExtensionMethods.scala][link-source-extmeth] in the Slick codebase.

### Equality and Inequality Methods

The `===` and `=!=` methods operate on any type of `Rep` and produce a `Rep[Boolean]`.
Here are some examples:

~~~ scala
messages.filter{_.sender === "Dave"}.result.statements
//res1: Iterable[String] = List(select x2."sender", x2."content", x2."id" from "message" x2 where x2."sender" = 'Dave')

messages.filter(_.sender =!= "Dave").result.statements
// res4: Iterable[String] = List(select x2."sender", x2."content", x2."id" from "message" x2 where not (x2."sender" = 'Dave'))
~~~

The `<`, `>`, `<=`, and `>=` methods also operate on any type of `Rep` (not just numeric columns):

~~~ scala
messages.filter(_.sender < "HAL").result.statements
// res7: Iterable[String] = List(select x2."sender", x2."content", x2."id" from "message" x2 where x2."sender" < 'HAL')


messages.filter(m => m.sender >= m.content).result.statements
// res8: Iterable[String] = List(select x2."sender", x2."content", x2."id" from "message" x2 where x2."sender" >= x2."content"
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

: Rep comparison methods.
  Operand and result types should be interpreted as parameters to `Rep[_]`.

### String Methods

Slick provides the `++` method for string concatenation (SQL's `||` operator):

~~~ scala
messages.map(m => m.sender ++ "> " + m.content).result.statements
// res9: Iterable[String] = List(select (x2."sender"||'> ')||x2."content" from "message" x2)
~~~

and the `like` method for SQL's classic string pattern matching:

~~~ scala
messages.filter(_.content like "%Pretty%").result.statements
// res10:  Iterable[String] = List(... where x2."content" like '%Pretty%')

~~~

Slick also provides methods such as `startsWith`, `length`, `toUpperCase`, `trim`, and so on.
These are implemented differently in different DBMSs---the examples below are purely for illustration:

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
  Operand and result types should be interpreted as parameters to `Rep[_]`.

### Numeric Methods {#NumericColumnMethods}

Slick provides a comprehensive set of methods that operate on `Rep`s with numeric values: `Ints`, `Longs`, `Doubles`, `Floats`, `Shorts`, `Bytes`, and `BigDecimals`.

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
  Operand and result types should be interpreted as parameters to `Rep[_]`.

### Boolean Methods

Slick also provides a set of methods that operate on boolean `Rep`s:

--------------------------------------------------------------------------------------------------------
Scala Code              Operand Column Types               Result Type        SQL Equivalent
----------------------- ---------------------------------- ------------------ --------------------------
`col1 && col2`           `Boolean` or `Option[Boolean]`    `Boolean`          `col1 and col2`

`col1 || col2`           `Boolean` or `Option[Boolean]`    `Boolean`          `col1 or col2`

`!col1`                  `Boolean` or `Option[Boolean]`    `Boolean`          `not col1`

--------------------------------------------------------------------------------------------------------

: Boolean column methods.
  Operand and result types should be interpreted as parameters to `Rep[_]`.

### Option Methods and Type Equivalence

Slick models nullable columns in SQL as `Rep`s with `Option` types.  We'll discuss this in some depth in [Chapter 4](#Modelling).
However, as a preview, know that if we have a nullable column in our database, we declare it as optional in our `Table`:

~~~ scala
final class PersonTable(tag: Tag) /* ... */ {
  // ...
  def nickname = column[Option[String]]("nickname")
  // ...
}
~~~

When it comes to querying on optional values,
Slick is pretty smart about type equivalence.

What do we mean by type equivalence?
Slick type-checks our column expressions to make sure the operands are of compatible types.
For example, we can compare `Strings` for equality but we can't compare a `String` and an `Int`:



~~~ scala
messages.filter(_.id === "foo")
//<console>:14: error: Cannot perform option-mapped operation
//      with type: (Long, String) => R
//  for base type: (Long, Long) => Boolean
//              messages.filter(_.id === "foo")
//                                   ^
~~~

Interestingly, Slick is very finickity about numeric types.
For example, comparing an `Int` to a `Long` is considered a type error:

~~~ scala
messages.filter(_.id === 123)
// <console>:14: error: Cannot perform option-mapped operation
//       with type: (Long, Int) => R
//   for base type: (Long, Long) => Boolean
//               messages.filter(_.id === 123)
//                                    ^
~~~

On the flip side of the coin,
Slick is clever about the equivalence of `Optional` and non-`Optional` columns.
As long as the operands are some combination of the types `A` and `Option[A]` (for the same value of `A`), the query will normally compile:

~~~ scala

messages.filter(_.id === Option(123L)).result.statements
// res16: Iterable[String] = List(select x2."sender", x2."content", x2."id" from "message" x2 where x2."id" = 123)
~~~

However, any `Optional` arguments must be strictly of type `Option`, not `Some` or `None`:

~~~ scala
messages.filter(_.id === Some(123L)).result.statements
// <console>:14: error: type mismatch;
//  found   : Some[Long]
//  required: slick.lifted.Rep[?]
//               messages.filter(_.id === Some(123L)).result.statements
//                                            ^
~~~


## Controlling Queries: Sort, Take, and Drop

There are a trio of functions used to control the order and number of results returned from a query.
This is great for pagination of a result set, but the methods listed in the table below can be used independently.

-------------------------------------------
Scala Code             SQL Equivalent
---------------- --------------------------
`sortBy`         `ORDER BY`

`take`           `LIMIT`

`drop`           `OFFSET`

-------------------------------------------------

:  Methods for ordering, skipping, and limiting the results of a query.

We'll look at each in term, starting with an example of `sortBy`:

~~~ scala
exec(messages.sortBy(_.sender).result)
// res17: Seq[Example.MessageTable#TableElementType] =
//  Vector(Message(Dave,Hello, HAL. Do you read me, HAL?,1),
//  Message(Dave,Open the pod bay doors, HAL.,3),
//  Message(HAL,Affirmative, Dave. I read you.,2),
//  Message(HAL,I'm sorry, Dave. I'm afraid I can't do that.,4))
~~~

To sort by multiple columns, return a tuple of columns:

~~~ scala
messages.sortBy(m => (m.sender, m.content)).result.statements
// res18: Iterable[String] = List(select x2."sender", x2."content", x2."id" from "message" x2 order by x2."sender", x2."content")
~~~

Now we know how to sort results, perhaps we want to show only the first five rows:

~~~ scala
messages.sortBy(_.sender).take(5)
~~~

If we are presenting information in pages, we'd need a way to show the next page (rows 6 to 10):

~~~ scala
messages.sortBy(_.sender).drop(5).take(5)
~~~

This is equivalent to:

~~~ sql
select "sender", "content", "id" from "message" order by "sender" limit 5 offset 5
~~~~


## Take Home Points

Starting with a `TableQuery` we can construct a wide range of queries with `filter` and `map`.
As we compose these queries, the types of the `Query` follow along to give type-safety throughout our application.

The expressions we use in queries are defined in extension methods,
and include `===`, `=!=`, `like`, `&&` and so on, depending on the type of the `Rep`.
Comparisons to `Option` types are made easy for us as Slick will compare `Rep[T]` and `Rep[Option[T]]` automatically.

Finally, we introduced some new terminology:

* _unpacked_ type, which is the regular Scala types we work with, such as `String`; and
* _mixed_ type, which is Slick's column representation, such as `Rep[String]`.


## Exercises

If you've not already done so, try out the above code.
In the [example project][link-example] the code is in _main.scala_ in the folder _chapter-02_.

Once you've done that, work through the exercises below.
An easy way to try things out is to use  _triggered execution_ with SBT:

~~~ bash
$ cd example-02
$ ./sbt.sh
> ~run
~~~

That `~run` will monitor the project for changes,
and when a change is seen,
the _main.scala_ program will be compiled and run.
This means you can edit _main.scala_ and then look in your terminal window to see the output.

### Count the Messages

How would you count the number of messages?
Hint: in the Scala collections the method `length` gives you the size of the collection.

<div class="solution">
~~~ scala
val results = exec(halSays.length.result)
~~~

You could also use `size`, which is an alias for `length`.
</div>

### Selecting a Message

Using a for comprehension,
select the message with the id of 1.
What happens if you try to find a message with an id of 999?

Hint: our IDs are `Long`s.
Adding `L` after a number in Scala, such as `99L`, makes it a long.

<div class="solution">
~~~ scala
val query = for {
  message <- messages if message.id === 1L
} yield message

val results = exec(query.result)
~~~

Asking for `999`, when there is no row with that ID, will give back an empty collection.
</div>

### One Liners

Re-write the query from the last exercise to not use a for comprehension.
Which style do you prefer? Why?

<div class="solution">
~~~ scala
val results = exec(messages.filter(_.id === 1L).result)
~~~
</div>

#### Checking the SQL

Calling the `result.statements` methods on a query will give you the SQL to be executed.
Apply that to the last exercise.
What query is reported?
What does this tell you about the way `filter` has been mapped to SQL?

<div class="solution">
The code you need to run is:

~~~ scala
val sql = messages.filter(_.id === 1L).result.statements
println(sql)
~~~

The result will be something like:

~~~ SQL
select x2."id", x2."sender", x2."content", x2."ts" from "message" x2  ↩
where x2."id" = 1
~~~

From this we see how `filter` corresponds to a SQL `where` clause.
</div>

### Selecting Columns

So far we have been returning `Message` classes or counts.
Select all the messages in the database, but return just their contents.
Hint: think of messages as a collection and what you would do to a collection to just get back a single field of a case class.

Check what SQL would be executed for this query.

<div class="solution">
~~~ scala
val query = messages.map(_.content)
println(s"The query is:  ${query.result.statements}")
println(s"The result is: ${exec(query.result)}")
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

The methods `first` and `firstOption` are useful alternatives to `run`.
Find the first message that HAL sent.
What happens if you use `first` to find a message from "Alice" (note that Alice has sent no messages).

<div class="solution">
~~~ scala
val msg1 = messages.filter(_.sender === "HAL").map(_.content).first
println(msg1)
~~~

You should get "Affirmative, Dave. I read you."

For Alice, `first` will throw a run-time exception. Use `firstOption` instead.
</div>

### The Start of Something

The method `startsWith` on a `String` tests to see if the string starts with a particular sequence of characters.
Slick also implements this for string columns.
Find the message that starts with "Open".
How is that query implemented in SQL?

<div class="solution">
~~~ scala
messages.filter(_.content startsWith "Open")
~~~

The query is implemented in terms of `LIKE`:

~~~ SQL
select x2."id", x2."sender", x2."content", x2."ts" from "message" x2  ↩
where x2."content" like 'Open%' escape '^'
~~~
</div>

### Liking

Slick implements the method `like`.
Find all the messages with "do" in their content.
Can you make this case insensitive?

<div class="solution">
The query is:

~~~ scala
messages.filter(_.content.toLowerCase like "%do%")
~~~

The SQL will turn out as:

~~~ SQL
select x2."id", x2."sender", x2."content", x2."ts" from "message" x2  ↩
where lower(x2."content") like '%do%'
~~~

There are three results: "_Do_ you read me", "Open the pod bay *do*ors", and "I'm afraid I can't _do_ that".
</div>

### Client-Side or Server-Side?

What does this do and why?

~~~ scala
exec(messages.map(_.content + "!").result)
~~~

<div class="solution">
The query Slick generates looks something like this:

~~~ sql
select '(message Ref @421681221).content!' from "message" x2
~~~

That is, a select expression for a strange constant string.

The `_.content + "!"` expression converts `content` to a string and appends the exclamation point.
What is `content`? It's a `Rep[String]`, not a `String` of the content.
The end result is that we're seeing something of the internal workings of Slick.

This is an unfortunate effect of Scala allowing automatic conversion to a `String`.
If you are interested in disabling this Scala behaviour, tools like [WartRemover][link-wartremover] can help.

It is possible to do this mapping in the database with Slick.
We just need to remember to work in terms of `Rep[T]` classes:

~~~ scala
messages.map(m => m.content ++ LiteralColumn("!"))
~~~

Here `LiteralColumn[T]` is type of `Rep[T]` for holding a constant value to be inserted into the SQL.
The `++` method is one of the extension methods defined for any `Rep[String]`.

This will produce the desired result:

~~~ sql
select "content"||'!' from "message"
~~~
</div>
