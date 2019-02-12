# Selecting Data {#selecting}

The last chapter provided a shallow end-to-end overview of Slick. We saw how to model data, create queries, convert them to actions, and run those actions against a database. In the next two chapters we will look in more detail at the various types of query we can perform in Slick.

This chapter covers *selecting* data using Slick's rich type-safe Scala reflection of SQL. [Chapter 3](#Modifying) covers *modifying* data by inserting, updating, and deleting records.

Select queries are our main means of retrieving data.
In this chapter we'll limit ourselves to simple select queries that operate on a single table.
In [Chapter 6](#joins) we'll look at more complex queries involving joins, aggregates, and grouping clauses.

## Select All The Rows!

The simplest select query is the `TableQuery` generated from a `Table`. In the following example, `messages` is a `TableQuery` for `MessageTable`:

```tut:silent
import slick.jdbc.H2Profile.api._
```
```tut:book
final case class Message(
  sender:  String,
  content: String,
  id:      Long = 0L)

final class MessageTable(tag: Tag) extends Table[Message](tag, "message") {

  def id      = column[Long]("id", O.PrimaryKey, O.AutoInc)
  def sender  = column[String]("sender")
  def content = column[String]("content")

  def * = (sender, content, id).mapTo[Message]
}

lazy val messages = TableQuery[MessageTable]
```

The type of `messages` is `TableQuery[MessageTable]`, which is a subtype of a more general `Query` type that Slick uses to represent select, update, and delete queries. We'll discuss these types in the next section.

We can see the SQL of the select query by calling `result.statements`:

```tut:book
messages.result.statements.mkString
```

Our `TableQuery` is the equivalent of the SQL `select * from message`.

<div class="callout callout-warning">
**Query Extension Methods**

Like many of the methods discussed below, the `result` method is actually an extension method applied to `Query` via an implicit conversion.
You'll need to have everything from `H2Profile.api` in scope for this to work:

```tut:silent
import slick.jdbc.H2Profile.api._
```
</div>

## Filtering Results: The *filter* Method

We can create a query for a subset of rows using the `filter` method:

```tut:book
messages.filter(_.sender === "HAL")
```

The parameter to `filter` is a function from an instance of `MessageTable` to a value of type `Rep[Boolean]` representing a `WHERE` clause for our query:

```tut:book
messages.filter(_.sender === "HAL").result.statements.mkString
```

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

``` scala
trait TableQuery[T <: Table[_]] extends Query[T, T#TableElementType, Seq] {
  // ...
}
```

A `TableQuery` is actually a `Query` that uses a `Table` (e.g. `MessageTable`) as its mixed type and the table's element type (the type parameter in the constructor, e.g. `Message`) as its unpacked type.
In other words, the function we provide to `messages.filter` is actually passed a parameter of type `MessageTable`:

```tut:book
messages.filter { messageTable: MessageTable =>
  messageTable.sender === "HAL"
}
```

This makes sense: `messageTable.sender` is one of the columns we defined in `MessageTable` above,
and `messageTable.sender === "HAL"` creates a Scala value representing the SQL expression `message.sender = 'HAL'`.

This is the process that allows Slick to type-check our queries.
`Query`s have access to the type of the `Table` used to create them,
allowing us to directly reference the columns on the `Table` when we're using combinators like `map` and `filter`.
Every column knows its own data type, so Slick can ensure we only compare columns of compatible types.
If we try to compare `sender` to an `Int`, for example, we get a type error:

```tut:fail
messages.filter(_.sender === 123)
```

<div class="callout callout-info">
<a name="constantQueries"/>
**Constant Queries **

So far we've built up queries from a `TableQuery`,
and this is the common case we use in most of this book.
However you should know that you can also construct constant queries, such as `select 1`, that are not related to any table.

We can use the `Query` companion object for this. So...

```tut:silent
Query(1)
```

will produce this query:

```tut:book
Query(1).result.statements.mkString
```

The `apply` method of the `Query` object allows
us to lift a scalar value to a `Query`.

A constant query such as `select 1` can be used to confirm we have database connectivity.
This could be a useful thing to do as an application is starting up, or a heartbeat system check that will consume minimal resources.

We'll see another example of using a `from`-less query in [Chapter 3](#moreControlOverInserts).
</div>


## Transforming Results

<div class="callout callout-info">
**`exec`**

Just as we did in Chapter 1, we're using a helper method to run queries in the REPL:

```tut:silent
import scala.concurrent.{Await,Future}
import scala.concurrent.duration._
```

```tut:book
val db = Database.forConfig("chapter02")

def exec[T](action: DBIO[T]): T =
  Await.result(db.run(action), 2.seconds)
```

This is included in the example source code for this chapter, in the `main.scala` file. You can run these examples in the REPL to follow along with the text.

We have also set up the schema and sample data:

```tut:book
def freshTestData = Seq(
  Message("Dave", "Hello, HAL. Do you read me, HAL?"),
  Message("HAL",  "Affirmative, Dave. I read you."),
  Message("Dave", "Open the pod bay doors, HAL."),
  Message("HAL",  "I'm sorry, Dave. I'm afraid I can't do that.")
)

exec(messages.schema.create andThen (messages ++= freshTestData))
```
</div>

### The *map* Method

Sometimes we don't want to select all of the columns in a `Table`.
We can use the `map` method on a `Query` to select specific columns for inclusion in the results.
This changes both the mixed type and the unpacked type of the query:

```tut:book
messages.map(_.content)
```

Because the unpacked type (second type parameter) has changed to `String`,
we now have a query that selects `String`s when run.
If we run the query we see that only the `content` of each message is retrieved:

```tut:book
val query = messages.map(_.content)

exec(query.result)
```


Also notice that the generated SQL has changed.
Slick isn't cheating: it is actually telling the database to restrict the results to that column in the SQL:

```tut:book
messages.map(_.content).result.statements.mkString
```

Finally, notice that the mixed type (first type parameter) of our new query has changed to `Rep[String]`.
This means we are only passed the `content` column when we `filter` or `map` over this query:

```tut:book
val pods = messages.
  map(_.content).
  filter{content:Rep[String] => content like "%pod%"}

exec(pods.result)
```

This change of mixed type can complicate query composition with `map`.
We recommend calling `map` only as the final step in a sequence of transformations on a query,
after all other operations have been applied.

It is worth noting that we can `map` to anything that Slick can pass to the database as part of a `select` clause.
This includes individual `Rep`s and `Table`s,
as well as `Tuple`s of the above.
For example, we can use `map` to select the `id` and `content` columns of messages:

```tut:book
messages.map(t => (t.id, t.content))
```

The mixed and unpacked types change accordingly,
and the SQL is modified as we might expect:

```tut:book
messages.map(t => (t.id, t.content)).result.statements.mkString
```

We can even map sets of columns to Scala data structures using `mapTo`:

```tut:book
case class TextOnly(id: Long, content: String)

val contentQuery = messages.
  map(t => (t.id, t.content).mapTo[TextOnly])

exec(contentQuery.result)
```

We can also select column expressions as well as single columns:

```tut:book
messages.map(t => t.id * 1000L).result.statements.mkString
```

This all means that `map` is a powerful combinator for controling the `SELECT` part of your query.

<div class="callout callout-info">
**Query's *flatMap* Method**

`Query` also has a `flatMap` method with similar monadic semantics to that of `Option` or `Future`.
`flatMap` is mostly used for joins, so we'll cover it in [Chapter 6](#joins).
</div>

### *exists*

Sometimes we are less interested in the contents of a queries result than if results exist at all.
For this we have `exists`, which will return `true` if the result set is not empty and false otherwise.

Let's look at quick example to show how we can use an existing query with the `exists` keyword:

```tut:book
val containsBay = for {
  m <- messages
  if m.content like "%bay%"
} yield m

val bayMentioned: DBIO[Boolean] =
  containsBay.exists.result
```

The `containsBay` query returns all messages that mention "bay".
We can then use this query in the `bayMentioned` expression to determine what to execute.

The above will generate SQL which looks similar to this:

~~~ sql
select exists(
  select "sender", "content", "id"
  from "message"
  where "content" like '%bay%'
)
~~~

We will see a more useful example in [Chapter 3](#moreControlOverInserts).


## Converting Queries to Actions

Before running a query, we need to convert it to an *action*.
We typically do this by calling the `result` method on the query.
Actions represent sequences of queries. We start with actions
representing single queries and compose them to form multi-action sequences.

Actions have the type signature `DBIOAction[R, S, E]`. The three type parameters are:

- `R` is the type of data we expect to get back from the database (`Message`, `Person`, etc);

- `S` indicates whether the results are streamed (`Streaming[T]`) or not (`NoStream`); and

- `E` is the effect type and will be inferred.

In many cases we can simplify the representation of an action to just `DBIO[T]`, which is an alias for `DBIOAction[T, NoStream, Effect.All]`.

<div class="callout callout-info">
**Effects**

Effects are not part of Essential Slick, and we'll be working in terms of `DBIO[T]` for most of this text.

However, broadly speaking, an `Effect` is a way to annotate an action.
For example, you can write a method that will only accept queries marked as `Read` or `Write`, or a combination such as `Read with Transactional`.

The effects defined in Slick under the `Effect` object are:

- `Read` for queries that read from the database.
- `Write` for queries that have a write effect on the database.
- `Schema` for schema effects.
- `Transactional` for transaction effects.
- `All` for all of the above.

Slick will infer the effect for your queries. For example, `messages.result` will be:

~~~ scala
DBIOAction[Seq[String], NoStream, Effect.Read]
~~~

In the next chapter we will look at inserts and updates. The inferred effect for an update in this case is: `DBIOAction[Int, NoStream, Effect.Write]`.

You can also add your own `Effect` types by extending the existing types.
</div>

## Executing Actions

To execute an action, we pass it to one of two methods on our `db` object:

 - `db.run(...)` runs the action and returns all the results in a single collection.
   These are known as a _materalized_ result.

 - `db.stream(...)` runs the action and returns its results in a `Stream`,
   allowing us to process large datasets incrementally without consuming large amounts of memory.

In this book we will deal exclusively with materialized queries.
`db.run` returns a `Future` of the final result of our action.
We need to have an `ExecutionContext` in scope when we make the call:

```tut:book
import scala.concurrent.ExecutionContext.Implicits.global

val futureMessages = db.run(messages.result)
```

<div class="callout callout-info">
**Streaming**

In this book we will deal exclusively with materialized queries.
Let's take a quick look at streams now, so we are aware of the alternative.

Calling `db.stream` returns a [`DatabasePublisher`][link-source-dbPublisher]
object instead of a `Future`. This exposes three methods to interact with the stream:

- `subscribe` which allows integration with Akka;
- `mapResult` which creates a new `Publisher` that maps the supplied function on the result set from the original publisher; and
- `foreach`, to perform a side-effect with the results.

Streaming results can be used to feed [reactive streams][link-reactive-streams],
or [Akka streams or actors][link-akka-streams]. Alternatively,
we can do something simple like use `foreach` to `println` our results:

```scala
db.stream(messages.result).foreach(println)
```

...which will eventually print each row.

If you want to explore this area, start with the [Slick documentation on streaming][link-slick-streaming].
</div>

## Column Expressions

Methods like `filter` and `map` require us to build expressions based on columns in our tables.
The `Rep` type is used to represent expressions as well as individual columns.
Slick provides a variety of extension methods on `Rep` for building expressions.

We will cover the most common methods below.
You can find a complete list in [ExtensionMethods.scala][link-source-extmeth] in the Slick codebase.

### Equality and Inequality Methods

The `===` and `=!=` methods operate on any type of `Rep` and produce a `Rep[Boolean]`.
Here are some examples:

```tut:book
messages.filter(_.sender === "Dave").result.statements

messages.filter(_.sender =!= "Dave").result.statements.mkString
```

The `<`, `>`, `<=`, and `>=` methods can operate on any type of `Rep`
(not just numeric columns):

```tut:book
messages.filter(_.sender < "HAL").result.statements

messages.filter(m => m.sender >= m.content).result.statements
```

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

```tut:book
messages.map(m => m.sender ++ "> " ++ m.content).result.statements.mkString
```

and the `like` method for SQL's classic string pattern matching:

```tut:book
messages.filter(_.content like "%pod%").result.statements.mkString
```

Slick also provides methods such as `startsWith`, `length`, `toUpperCase`, `trim`, and so on.
These are implemented differently in different DBMSs---the examples below are purely for illustration:

---------------------------------------------------------------------
Scala Code              Result Type        SQL Equivalent
----------------------- ------------------ --------------------------
`col1.length`           `Int`              `char_length(col1)`

`col1 ++ col2`          `String`           `col1 || col2`

`c1 like c2`            `Boolean`          `c1 like c2`

`c1 startsWith c2`      `Boolean`          `c1 like (c2 || '%')`

`c1 endsWith c2`        `Boolean`          `c1 like ('%' || c2)`

`c1.toUpperCase`        `String`           `upper(c1)`

`c1.toLowerCase`        `String`           `lower(c1)`

`col1.trim`             `String`           `trim(col1)`

`col1.ltrim`            `String`           `ltrim(col1)`

`col1.rtrim`            `String`           `rtrim(col1)`

--------------------------------------------------------------------------------------------------------

: String column methods.
  Operand (e.g., `col1`, `col2`) must be `String` or `Option[String]`.
  Operand and result types should be interpreted as parameters to `Rep[_]`.

### Numeric Methods {#NumericColumnMethods}

Slick provides a comprehensive set of methods that operate on `Rep`s with numeric values: `Int`s, `Long`s, `Double`s, `Float`s, `Short`s, `Byte`s, and `BigDecimal`s.

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

### Date and Time Methods

Slick provides column mappings for: `Instant`, `LocalDate`, `LocalTime`, `LocalDateTime`, `OffsetTime`, `OffsetDateTime`, and `ZonedDateTime`.
That means you can use all of those types as columns in your table definitions.

How your columns are mapped will depend on the database you're using,
as different databases have different capabilities when it comes to time and date.
The table below shows the SQL types used for three common databases:

--------------------------------------------------------------------------
Scala Type           H2 Column Type   PostgreSQL         MySQL
-------------------- ---------------- ----------------- ------------------
`Instant`            `TIMESTAMP`      `TIMESTAMP`        `TEXT`

`LocalDate`          `DATE`           `DATE`             `DATE`

`LocalTime`          `VARCHAR`        `TIME`             `TEXT`

`LocalDateTime`      `TIMESTAMP`      `TIMESTAMP`        `TEXT`

`OffsetTime`         `VARCHAR`        `TIMETZ`           `TEXT`

`OffsetDateTime`     `VARCHAR`        `VARCHAR`          `TEXT`

`ZonedDateTime`      `VARCHAR`        `VARCHAR`          `TEXT`

--------------------------------------------------------------------------

: Mapping from `java.time` types to SQL column types for three databases.
  There's a full list as part of the The [Slick 3.3 Upgrade Guide][link-slick-ug-time].

Unlike the `String` and `Boolean` types, there are no special methods for the `java.time` types.
However, as all types have the equality methods, you can use `===`, `>`, `<=`, and so on with date and time types as you'd expect.

### Option Methods and Type Equivalence {#type_equivalence}

Slick models nullable columns in SQL as `Rep`s with `Option` types.
We'll discuss this in some depth in [Chapter 5](#Modelling).
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
For example, we can compare `String`s for equality but we can't compare a `String` and an `Int`:

```tut:fail
messages.filter(_.id === "foo")
```

Interestingly, Slick is very finickity about numeric types.
For example, comparing an `Int` to a `Long` is considered a type error:

```tut:fail
messages.filter(_.id === 123)
```

On the flip side of the coin,
Slick is clever about the equivalence of optional and non-optional columns.
As long as the operands are some combination of the types `A` and `Option[A]` (for the same value of `A`), the query will normally compile:

```tut:book
messages.filter(_.id === Option(123L)).result.statements
```

However, any optional arguments must be strictly of type `Option`, not `Some` or `None`:

```tut:fail
messages.filter(_.id === Some(123L)).result.statements
```

If you find yourself in this situation, remember you can always provide a type ascription to the value:

```tut:book
messages.filter(_.id === (Some(123L): Option[Long]) )
```


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

We'll look at each in turn, starting with an example of `sortBy`. Say we want want messages in order of the sender's name:

```tut:book
exec(messages.sortBy(_.sender).result).foreach(println)
```

Or the reverse order:

```tut:book
exec(messages.sortBy(_.sender.desc).result).foreach(println)
```



To sort by multiple columns, return a tuple of columns:

```tut:book
messages.sortBy(m => (m.sender, m.content)).result.statements
```

Now we know how to sort results, perhaps we want to show only the first five rows:

```tut:book
messages.sortBy(_.sender).take(5)
```

If we are presenting information in pages, we'd need a way to show the next page (rows 6 to 10):

```tut:book
messages.sortBy(_.sender).drop(5).take(5)
```

This is equivalent to:

~~~ sql
select "sender", "content", "id"
from "message"
order by "sender"
limit 5 offset 5
~~~~

<div class="callout callout-info">
**Sorting on Null columns**

We had a brief introduction to nullable columns earlier in the chapter when we looked at [Option Methods and Type Equivalence](#type_equivalence).
Slick offers three modifiers which can be used in conjunction with `desc` and `asc` when sorting on nullable columns: `nullFirst`, `nullsDefault` and `nullsLast`.
These do what you expect, by including nulls at the beginning or end of the result set.
The `nullsDefault` behaviour will use the SQL engines preference.

We don't have any nullable fields in our example yet.
But here's a look at what sorting a nullable column is like:

```scala
users.sortBy(_.name.nullsFirst)
```

The generated SQL for the above query would be:

~~~ sql
select "name", "email", "id"
from "user"
order by "name" nulls first
~~~

We cover nullable columns in [Chapter 5](#Modelling) and include an example of sorting on nullable columns in [example project][link-example] the code is in _nulls.scala_ in the folder _chapter-05_.
</div>


## Conditional Filtering

So far we've seen query operations such as  `map`, `filter`, and `take`,
and in later chapters we'll see joins and aggregations.
Much of your work with Slick will likely be with just these few operations.

There are two other methods, `filterOpt` and `filterIf`,
that help with dynamic queries, where you may (or may not) want to filter rows based on some condition.

For example, suppose we want to give our user the option to filter by crew member (message sender).
That is, if you don't specify a crew member, you'll get everyone's messages.

Our first attempt at this might be:

```tut:book
def query(name: Option[String]) =
  messages.filter(msg => msg.sender === name)
```

That's a valid query, but if you feed it `None`, you'll get no results, rather than all results.
We could add more checks to the query, such as also adding `|| name.isEmpty`.
But what we want to do is only filter when we have a value. And that's what `filterOpt` does:

```tut:book
def query(name: Option[String]) =
  messages.filterOpt(name)( (row, value) => row.sender === value )
```

You can read this query as: we're going to optionally filter on `name`,
and if `name` has a value, we can use the `value` to filter the `row`s in the query.

The upshot of that is, when there's no crew member provided, there's no condition on the SQL:

```tut:book
query(None).result.statements.mkString
```

And when there is, the condition applies:

```tut:book
query(Some("Dave")).result.statements.mkString
```

<div class="callout callout-info">
Once you're in the swing of using `filterOpt`, you may prefer to use a short-hand version:

```tut:book
def query(name: Option[String]) =
  messages.filterOpt(name)(_.sender === _)
```

The behaviour of `query` is the same if you use this short version or the longer version
we used in the main text.
</div>

`filterIf` is a similar capability, but turns a where condition on or off.
For example, we can give the user an option to exclude "old" messages:

```tut:book
val hideOldMessages = true
val query = messages.filterIf(hideOldMessages)(_.id > 100L)
query.result.statements.mkString
```

Here we see a condition of `ID > 100` added to the query because `hideOldMessages` is `true`.
If it where false, the query would not contain the where clause.

The great convenience of `filterIf` and `filterOpt` is that you can chain them one after another
to build up concise dynamic queries:

```tut:book
val person = Some("Dave")
val hideOldMessages = true

val queryToRun = messages.
  filterOpt(person)(_.sender === _).
  filterIf(hideOldMessages)(_.id > 100L)

queryToRun.result.statements.mkString
```


## Take Home Points

Starting with a `TableQuery` we can construct a wide range of queries with `filter` and `map`.
As we compose these queries, the types of the `Query` follow along to give type-safety throughout our application.

The expressions we use in queries are defined in extension methods,
and include `===`, `=!=`, `like`, `&&` and so on, depending on the type of the `Rep`.
Comparisons to `Option` types are made easy for us as Slick will compare `Rep[T]` and `Rep[Option[T]]` automatically.

We've seen that `map` acts like a SQL `select`, and `filter` is like a `WHERE`.
We'll see the Slick representation of `GROUP` and `JOIN` in [Chapter 6](#joins).

We introduced some new terminology:

* _unpacked_ type, which is the regular Scala types we work with, such as `String`; and

* _mixed_ type, which is Slick's column representation, such as `Rep[String]`.

We run queries by converting them to actions using the `result` method.
We run the actions against a database using `db.run`.

The database action type constructor `DBIOAction` takes three arguments that represent the result, streaming mode, and effect.
`DBIO[R]` simplifies this to just the result type.

What we've seen for composing queries will help us to modify data using `update` and `delete`.
That's the topic of the next chapter.

## Exercises

If you've not already done so, try out the above code.
In the [example project][link-example] the code is in _main.scala_ in the folder _chapter-02_.

Once you've done that, work through the exercises below.
An easy way to try things out is to use  _triggered execution_ with SBT:

~~~ bash
$ cd example-02
$ sbt
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
```tut:book
val results = exec(messages.length.result)
```

You could also use `size`, which is an alias for `length`.
```tut:invisible
messages.size
```
</div>

### Selecting a Message

Using a for comprehension,
select the message with the id of 1.
What happens if you try to find a message with an id of 999?

Hint: our IDs are `Long`s.
Adding `L` after a number in Scala, such as `99L`, makes it a long.

<div class="solution">
```tut:book
val query = for {
  message <- messages if message.id === 1L
} yield message

val results = exec(query.result)
```

Asking for `999`, when there is no row with that ID, will give back an empty collection.

```tut:invisible
{
  val nnn = messages.filter(_.id === 999L)
  val rows = exec(nnn.result)
  assert(rows.isEmpty, s"Expected empty rows for id 999 in ex2, not $rows")
}
```
</div>

### One Liners

Re-write the query from the last exercise to not use a for comprehension.
Which style do you prefer? Why?

<div class="solution">
```tut:book
val results = exec(messages.filter(_.id === 1L).result)
```
</div>

### Checking the SQL

Calling the `result.statements` methods on a query will give you the SQL to be executed.
Apply that to the last exercise.
What query is reported?
What does this tell you about the way `filter` has been mapped to SQL?

<div class="solution">
The code you need to run is:

```tut:book
val sql = messages.filter(_.id === 1L).result.statements
println(sql.head)
```

From this we see how `filter` corresponds to a SQL `where` clause.
</div>

### Is HAL Real?

Find if there are any messages by HAL in the database,
but only return a boolean value from the database.

<div class="solution">
That's right, we want to know if HAL `exists`:

```tut:book
val query = messages.filter(_.sender === "HAL").exists

exec(query.result)
```

```tut:invisible
{
val found = exec(query.result)
assert(found, s"Expected to find HAL, not: $found")
}
```

The query will return `true` as we do have records from HAL,
and Slick will generate the following SQL:

```tut:book
query.result.statements.head
```
</div>


### Selecting Columns

So far we have been returning `Message` classes, booleans, or counts.
Now we want to select all the messages in the database, but return just their `content` columns.

Hint: think of messages as a collection and what you would do to a collection to just get back a single field of a case class.

Check what SQL would be executed for this query.

<div class="solution">
```tut:book
val query = messages.map(_.content)
exec(query.result)
```

You could have also said:

```tut:book
val query = for { message <- messages } yield message.content
```

The query will return only the `content` column from the database:

```tut:book
query.result.statements.head
```
</div>


### First Result

The methods `head` and `headOption` are useful methods on a `result`.
Find the first message that HAL sent.

What happens if you use `head` to find a message from "Alice" (note that Alice has sent no messages).

<div class="solution">
```tut:book
val msg1 = messages.filter(_.sender === "HAL").map(_.content).result.head
```

You should get an action that produces "Affirmative, Dave. I read you."

For Alice, `head` will throw a run-time exception as we are trying to return the head of an empty collection. Using `headOption` will prevent the exception.

```tut:book
exec(messages.filter(_.sender === "Alice").result.headOption)
```
</div>

### Then the Rest

In the previous exercise you returned the first message HAL sent.
This time find the next five messages HAL sent.
What messages are returned?

What if we'd asked for HAL's tenth through to twentieth message?

<div class="solution">
It's `drop` and `take` to the rescue:

```tut:book
val msgs = messages.filter(_.sender === "HAL").drop(1).take(5).result
```

HAL has only two messages in total.
Therefore our result set should contain one messages

```scala
Message(HAL,I'm sorry, Dave. I'm afraid I can't do that.,4)
```

```tut:invisible
{
  val nextFive = exec(msgs)
  assert(nextFive.length == 1, s"Expected 1 msgs, not: $nextFive")
}
```

And asking for any more messages will result in an empty collection.

```tut:book
val msgs = exec(
            messages.
              filter(_.sender === "HAL").
              drop(10).
              take(10).
              result
          )
```

```tut:invisible
{
  assert(msgs.length == 0, s"Expected 0 msgs, not: $msgs")
}
```

</div>


### The Start of Something

The method `startsWith` on a `String` tests to see if the string starts with a particular sequence of characters.
Slick also implements this for string columns.
Find the message that starts with "Open".
How is that query implemented in SQL?

<div class="solution">
```tut:book
messages.filter(_.content startsWith "Open")
```

The query is implemented in terms of `LIKE`:

```tut:book
messages.filter(_.content startsWith "Open").result.statements.head
```
</div>

### Liking

Slick implements the method `like`.
Find all the messages with "do" in their content.

Can you make this case insensitive?

<div class="solution">
If you have familiarity with SQL `like` expressions, it probably wasn't too hard to find a case-sensitive version of this query:

```tut:book
messages.filter(_.content like "%do%")
```

To make it case sensitive you could use `toLowerCase` on the `content` field:

```tut:book
messages.filter(_.content.toLowerCase like "%do%")
```

We can do this because `content` is a `Rep[String]` and that `Rep` has implemented `toLowerCase`.
That means, the `toLowerCase` will be translated into meaningful SQL.

There will be three results: "_Do_ you read me", "Open the pod bay *do*ors", and "I'm afraid I can't _do_ that".
```tut:invisible
{
  val likeDo = exec( messages.filter(_.content.toLowerCase like "%do%").result )

  assert(likeDo.length == 3, s"Expected 3 results, not $likeDo")
}
```
</div>

### Client-Side or Server-Side?

What does this do and why?

```scala
exec(messages.map(_.content + "!").result)
```

<div class="solution">
The query Slick generates looks something like this:

```sql
select '(message Ref @421681221).content!' from "message"
```

```tut:invisible
{
  val weird = exec(messages.map(_.content + "!").result).head
  assert(weird contains "Ref", s"Expected 'Ref' inside $weird")
}
```

That is a select expression for a strange constant string.

The `_.content + "!"` expression converts `content` to a string and appends the exclamation point.
What is `content`? It's a `Rep[String]`, not a `String` of the content.
The end result is that we're seeing something of the internal workings of Slick.

This is an unfortunate effect of Scala allowing automatic conversion to a `String`.
If you are interested in disabling this Scala behaviour, tools like [WartRemover][link-wartremover] can help.

It is possible to do this mapping in the database with Slick.
We need to remember to work in terms of `Rep[T]` classes:

```tut:book
messages.map(m => m.content ++ LiteralColumn("!"))
```

Here `LiteralColumn[T]` is type of `Rep[T]` for holding a constant value to be inserted into the SQL.
The `++` method is one of the extension methods defined for any `Rep[String]`.

Using `++` will produce the desired query:

```sql
select "content"||'!' from "message"
```

You can also write:

```tut:book
messages.map(m => m.content ++ "!")
```

...as `"!"` will be lifted to a `Rep[String]`.

This exercise highlights that inside of a `map` or `filter` you are working in terms of `Rep[T]`.
You should become familiar with the operations available to you.
The tables we've included in this chapter should help with that.

</div>
