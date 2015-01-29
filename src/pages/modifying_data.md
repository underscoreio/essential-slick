# Creating and Modifying Rows

Now that we know how to construct a query, connect to a database, and run a query, we can use that knowledge to start modifying the data in the database.

In this chapter we will:

- see how deleting rows is similar to selecting rows;
- learn more about inserting data;
- understand how we've used automatically created primary key values; and
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
**Logging Queries and Results**

In the previous chapter we noted you can see the SQL Slick would use by calling `selectStatement` on a query. There's also `deleteStatement` and `updateStatement`.  These are useful to see the SQL that would be produced by a query, but sometimes you want to see all the queries _when Slick executes them_.  You can do that by configuring logging.

Slick uses a logging framework called [SLFJ][link-slf4j].  You can configure this to capture information about the queries being run.  The "essential-slick-example" project uses a logging back-end called [_Logback_][link-logback], which is configured in the file _src/main/resources/logback.xml_.  In that file we enable statement logging by turning up the logging to debug level. For example:

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
* `scala.slick.jdbc.StatementInvoker.result` - which logs the results of a query.
* `scala.slick.session` - for session information, such as connections being opened.
* `scala.slick` - for everything!  This is usually too much.


The `StatementInvoker.result` logger is pretty cute:

~~~
StatementInvoker.result - /--------+----------------------+----------------------+----\
StatementInvoker.result - | sender | content              | ts                   | id |
StatementInvoker.result - +--------+----------------------+----------------------+----+
StatementInvoker.result - | HAL    | Affirmative, Dave... | 2001-02-17 10:22:... | 2  |
StatementInvoker.result - | HAL    | I'm sorry, Dave. ... | 2001-02-17 10:22:... | 4  |
StatementInvoker.result - \--------+----------------------+----------------------+----/
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

This is just one way of dealing with automatically generated primary keys. We will look at other ways, including custom projections (**TODO: Will we?**) and `Option[T]` values, in chapter **TODO**.
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

You can find out the capabilities of different databases in the Slick manual page for [Driver Capabilities][link-ref-dbs].  For the example in this section it's the `` capability.

The Scala Doc for each driver also lists the capabilities the driver _does not_ have. For an example, take a look at the top of the [H2 Driver Scala Doc][link-ref-h2driver] page.
</div>

If we do want to get a populated `Message` back from an insert for any database, with the auto-generated `id` set, we can write a method to do that.  It would take a message as an argument, insert it returning the `id`, and then give back a copy the message setting the `id`. This would emulate the `jdbc.returnInsertOther` capability.

We don't need to write that method as Slick supports it via `into`:

~~~ scala
val messagesInsertWithId =
  messages returning messages.map(_.id) into { (m, i) => m.copy(id=i) }

val result: Message =
  messagesInsertWithId += Message("HAL", "I'm back", DateTime.now)
~~~

The `result` will be the message with the auto-generated `id` field correctly set.

This is a general purpose client-side transformation. That is, it runs in your Scala application and not the database.

Any `returning` expression can have an `into`.  The `into` part is a function from the type being inserted and the type returned, to some other type. In the above example the type of the `into` function is:

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


## Updating Rows

In all the rows we've created so far we've referred to "HAL". That's a computer from the film _2001: A Space Odyssey_, but the correct name is "HAL 9000".  Let's fix that:

~~~ scala
val rowsAffected: Int =
  messages.filter(_.sender === "HAL").map(_.sender).update("HAL 9000")
~~~

If we break this down it may be easier to see the same patterns we've seen elsewhere:

~~~ scala
val queryForHAL  = messages.filter(_.sender === "HAL")
val selectSender = queryForHal.map(_.sender)
val rowsAffected: Int = selectSender.update("HAL 9000")
~~~

We're selecting the messages from HAL, and composing that query to just return the `sender` field. Then we can call `update` and supply a new value for the sender.

This update is equivalent to this SQL:

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

## Updating with a Computed Value

Let's now turn to more interesting updates. How about converting every message to be all capitals. Or adding an exclamation mark to the end of each message.  Both of these examples need us to do something to each row in turn.  In SQL it might be something like:

~~~ sql
UPDATE "messages" SET "content" = "content" + "!"
~~~

This is not currently supported by `update` in Slick. But there are ways to achieve the same result.

### Client Side Update

The first way is to perform this action on the client side.  We'll define a Scala function to capture how we want to change each row:

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
3. For each row, update the row (`foreach { ... }`)

This results in _N + 1 queries_, where _N_ is the number of rows selected.  That may be excessive, depending on what your needs are.

### Plain SQL

The alternative is to simply use the SQL we original wrote.  Slick supports _plain SQL queries_ as an alternative to the collectons-like style we've seen up to this point:

~~~ scala
sqlu"""UPDATE messages SET content = content + "!" """
~~~


_TODO_ round this example off.




## Exercises

- Delete all the messages

- Client/server: What does this do, and why? messages.map(_.content + "!").list


## Take Home Points

For modifying the rows in the database we have seen that:

* deletes are via a `delete` call to a query;
* updates are via an `update` call on a query, but are somewhat limited; and
* inserts are via an `insert` (or `+=`) call on a table.

Auto-incrementing values are not inserted by Slick, unless forced. The auto-incremented values can be returned from the insert by using `returning`.

Databases have different capabilities. The limitations of each driver is listed in the driver's Scala Doc page.

Rows can be inserted in batch. For simple situations this gives performance gains. However when additional information is required back (such as primary keys), there is not performance advantage.


The SQL statements executed and the result returned from the database can be monitored by configuring the logging system.
