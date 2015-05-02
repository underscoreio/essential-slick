# Creating and Modifying Data {#Modifying}

In the last chapter we saw how to retrieve data from the database using select queries. In this chapter we will look at three other main types that modify the stored data: insert, update, and delete queries.

SQL veterans will know that update and delete queries, in particular, share many similarities with select queries. The same is in Slick, where we use the same `Query` monad and combinators to build all four kinds of query. Ensure you are familiar with the content of [Chapter 3]{#Selecting} before proceeding.

## Inserting Data

As we saw in [Chapter 1](#Basics}, adding new data a table looks like a destuctive append operation on a mutable collection. We can use the `+=` method to insert a single row into a table, and `++=` to insert multiple rows. We'll discuss both of these operations below.

### Inserting Single Rows

To insert a single row into a table we use the `+=` method, which is an alias for `insert`:

~~~ scala
messages += Message("HAL", "No. Seriously, Dave, I can't let you in.")
// res2: Int = 1

messages insert Message("Dave", "Ok, but you're off my Christmas card list for good!")
// res3: Int = 1
~~~

In each case the return value is the number of rows inserted. However, it is often useful to return something else, such as the primary key generated for the new row, or the entire row as a case class. As we will see below, we can get this information using a new method called `returning`.

### Primary Key Allocation

If we recall the definition of `Message`, we put the `id` field at the end of the case class and gave it a default value of `0L`:

~~~ scala
final case class Message(sender: String, content: String, ts: DateTime, id: Long = 0L)
~~~

Giving the `id` parameter a default value allows us to omit it when creating a new object. Placing the `id` at the end of the constructor allows us to omit it without having to pass the remaining arguments using keyword parameters:

~~~ scala
Message("HAL", "I'm a computer, Dave, what would I do with a Christmas card anyway?")
~~~

There's nothing special about our default value of `0L`---it's not a magic value meaning "this record has no `id`". In our running example the `id` field of `Message` is mapped to an auto-incrementing primary key (using the `O.AutoInc` option), which causes Slick to ignore the value of the field when generating an insert query and allows the database to step in an generate the value for us. Slick provides a `forceInsert` method that allows us to specify a primary key on insert, ignoring the value the database would allocate.

### Retrieving Primary Keys on Insert

Let's modify the insert to give us back the primary key generated:

~~~ scala
(messages returning messages.map(_.id)) += Message("Dave", "So... what do we do now?")
// res5: Long = 7
~~~

The argument to `messages returning` is a `Query`, which is why `messages.map(_.id)` makes sense here. We can provide that the return value is a primary key by looking up the record we just inserted:

~~~ scala
messages.filter(_.id === 7L).firstOption
// res6: Option[Example.MessageTable#TableElementType] =
//   Some(Message(Dave,So... what do we do now?,7))
~~~

H2 only allows us to retrieve the primary key from an insert. Some databases allow us to retrieve the complete inserted record. For example, we could ask for the whole `Message` back:

~~~ scala
(messages returning messages) += Message("HAL", "I don't know. I guess we wait.")
// res7: Message = ...
~~~

If we tried this with H2, we get a runtime error:

~~~ scala
(messages returning messages) += Message("HAL", "I don't know. I guess we wait.")
// scala.slick.SlickException: ↩
//   This DBMS allows only a single AutoInc column to be returned from an INSERT
//   at ...
~~~

This is a shame, but getting the primary key is often all we need. Typing `messages returning messages.map(_.id)` isn't exactly convenient, but we can easily define a query specifically for inserts:

~~~ scala
lazy val messagesInsert = messages returning messages.map(_.id)
// messagesInsert: slick.driver.H2Driver.ReturningInsertInvokerDef[
//   Example.MessageTable#TableElementType,
//   Long
// ] = <lazy>

messagesInsert += Message("Dave", "You're such a jerk.")
// res8: Long = 8
~~~

<div class="callout callout-info">
**Driver Capabilities**

The Slick manual contains a comprehensive table of the [capabilities for each database driver][link-ref-dbs]. The ability to return complete records from an insert query is referenced as the `jdbc.returnInsertOther` capability.

The API documentation for each driver also lists the capabilities that the driver *doesn't* have. For an example, the top of the [H2 Driver Scaladoc][link-ref-h2driver] page points out several of its shortcomings.
</div>

If we do want to get a populated `Message` back from an insert for any database, we can do it by retrieving the primary key and manually adding it to the inserted record. Slick simplifies this with another method, `into`:

~~~ scala
val messagesInsertWithId =
  messages returning messages.map(_.id) into { (message, id) =>
    message.copy(id = id)
  }
// messagesInsertWithId: slick.driver.H2Driver.IntoInsertInvokerDef[
//   Example.MessageTable#TableElementType,
//   Example.Message
// ] = ...

messagesInsertWithId += Message("Dave", "You're such a jerk.")
// res8: messagesInsertWithId.SingleInsertResult =
//   Message(Dave,You're such a jerk.,8)
~~~

The `into` method allows us to specify a function to combine the record and the new primary key. It's perfect for emulating the `jdbc.returnInsertOther` capability, although we can use it for any post-processing we care to imagine on the inserted data.

### Inserting Multiple Rows

Suppose we want to insert several `Messages` into the database. We could just use `+=` to insert each one in turn. However, this would result in a separate query being issued to the database for each record, which could be slow for large numbers of inserts.

As an alternative, Slick supports batch inserts, where all the inserts are sent to the database in one go. We've seen this already in the first chapter:

~~~ scala
val testMessages = Seq(
  Message("Dave", "Hello, HAL. Do you read me, HAL?"),
  Message("HAL",  "Affirmative, Dave. I read you."),
  Message("Dave", "Open the pod bay doors, HAL."),
  Message("HAL",  "I'm sorry, Dave. I'm afraid I can't do that.")
)
// testMessages: Seq[Message] = ...

messages ++= testMessages
// res9: Option[Int] = Some(4)
~~~

This code prepares one SQL statement and uses it for each row in the `Seq`. This can result in a significant boost in performance when inserting many records.

As we saw earlier this chapter, the default return value of a single insert is the number of rows inserted. The multi-row insert above is also returning the number of rows, except this time the type is `Option[Int]`. The reason for this is that the JDBC specification permits the underlying database driver to return to indicate that the number of rows inserted is unknown.

Slick also provides a batch version of `messages returning...`, including the `into` method. We can use the `messagesInsertWithId` query we defined last section and write:

~~~ scala
messagesInsertWithId ++= testMessages
// res9: messagesInsertWithId.MultiInsertResult = List(
//   Message(Dave,Hello, HAL. Do you read me, HAL?,13),
//   ...)
~~~

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

The way we'd recommend is to use plain SQL updates, which we turn to in [Chapter 6](#PlainSQL).  However, it's worth knowing that you can also solve this with a client side update.

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

