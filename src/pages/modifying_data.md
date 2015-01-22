# Creating and Modifying Rows

Now that we know how to construct a query, connect to a database, and run a query, we can use that knowledge to start modifying the data in the database.

In this chapter we will:

- see how deleting rows is almost identical to selecting rows;
- learn to insert data
- understand how automatically created keys work with out case classes; and
- discover how rows can be updated.


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
**Logging Queries**

In the previous chapter we noted you can see the SQL SLick would use by calling `selectStatement` on a query. There's also `deleteStatement` and `updateStatement`.  These are useful to see the SQL that would be produced by a query, but sometimes you want to see all the queries _when Slick executes them_.  You can do that by configuring logging.

Slick uses a logging framework called [SLFJ][link-slf4j].  You can configure this to capture information about the queries being run.  The "essential-slick-example" project uses a logging back-end called [_Logback_][link-logback], which is configured in the file _src/main/resources/logback.xml_.  In that file we enable statement logging by turning up the logging to debug level:

~~~ xml
<logger name="scala.slick.jdbc.JdbcBackend.statement" level="DEBUG"/>
~~~

When we next run a query, delete or update rows, and even modify the schema, each statement will be recorded on standard output or wherever you configure it to go:

~~~
DEBUG s.slick.jdbc.JdbcBackend.statement - Preparing statement:
  delete from "message" where "message"."sender" = 'HAL'
~~~

You can enable a variety of events to be logged:

* `scala.slick.jdbc.JdbcBackend.statement` - which is for statement logging, as you've seen.
* `scala.slick.session` - for session information, such as connections being opened.
* `scala.slick` - for everything!  This is usually too much.
</div>

There's not a lot more to say about deleting data. If you have a query that selects a table, then you can use it to delete rows.

But to expand on that, consider this variation on the `halSays` query:

~~~ scala
val halText = halSays.map(_.content)
~~~

That's a valid query, and will select just the `content` column from the `messages` table. You'll find you cannot use that query with `delete`. It'll be a compile error as `delete` is not defined for this kind of query: `halText` is of type `Query[Column[String], String, Seq]`, where as the `halSays` query is of type `Query[MessageTable, Message, Seq]`.

### `Column[T]`

What is this `Column[String]` and why can't we delete using it?

Recall we defined the column `content` as:

~~~ scala
def content = column[String]("content")
~~~

The method `column` evaluates, in this case, to a `Column[String]`. When we construct a query to return a column, the query will be in terms of a `Column[String]`.  When we count the number of rows in a table, the query will be in terms of `Column[Int]`.  More generally, a single value from the database will be a `Column[T]` in the context of a query.

All the operations you can perform on a column, such as `like` or `toLowerCase`, are added onto `Column[T]` via _extension methods_. These are implicit conversions provided by Slick.  If you're keen, you can go look at them all in the Slick source file [ExtensionMethods.scala][link-source-extmeth].

So `Column[T]` is for values, and deleting based on a value makes no sense in Slick or SQL. Imagine the query `SELECT 42`. You can represent this in Slick as `Query(42)`. You can `run` the query, but you cannot `delete` on it. But deleting on a table, like `MessageTable`, that makes more sense.


## Inserting a Row

Adding new rows to a table also looks like a collections operation:

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

This is one way of dealing with automatically generated primary keys. We will look at other ways, including custom projections and `Option[T]` values, in chapter **TODO**.
</div>

If we want to Slick to give us back the `Message` with a populated primary key we can ask for that:

~~~ scala
val result =
  (messages returning messages.map(_.id)) += Message("HAL", "Affirmative, Dave. I read you.", new DateTime(982405324L))
~~~





## Updating Rows


## Exercises


## Take Home Points



