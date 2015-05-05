# Creating and Modifying Data {#Modifying}

In the last chapter we saw how to retrieve data from the database using select queries. In this chapter we will look at three other main types that modify the stored data: insert, update, and delete queries.

SQL veterans will know that update and delete queries, in particular, share many similarities with select queries. The same is in Slick, where we use the same `Query` monad and combinators to build all four kinds of query. Ensure you are familiar with the content of [Chapter 3]{#Selecting} before proceeding.

## Inserting Data

As we saw in [Chapter 1](#Basics), adding new data a table looks like a destructive append operation on a mutable collection. We can use the `+=` method to insert a single row into a table, and `++=` to insert multiple rows. We'll discuss both of these operations below.

### Inserting Single Rows

To insert a single row into a table we use the `+=` method, which is an alias for `insert`:

~~~ scala
messages += Message("HAL", "No. Seriously, Dave, I can't let you in.")
// res2: Int = 1

messages insert Message("Dave", "You're off my Christmas card list.")
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

There's nothing special about our default value of `0L`---it's not a magic value meaning "this record has no `id`". In our running example the `id` field of `Message` is mapped to an auto-incrementing primary key (using the `O.AutoInc` option), causing Slick to ignore the value of the field when generating an insert query and allows the database to step in an generate the value for us. We can see the SQL we're executing using the `insertStatement` method:

~~~ scala
messages.insertStatement
// res4: String =
//   insert into "message" ("sender","content")
//   values (?,?)
~~~

Slick provides a `forceInsert` method that allows us to specify a primary key on insert, ignoring the database's suggestion:

~~~ scala
messages forceInsert Message("Dave", "Point taken.", 1000)
// res5: Int = 1

messages.filter(_.id === 1000L).run
// res6: Seq[Example.MessageTable#TableElementType] =
//   Vector(Message(Dave,Point taken.,1000))
~~~

### Inserting Specific Columns

If we our database table contains a lot of columns with default values, it is sometimes useful to specify a subset of columns in our insert queries. We can do this by `mapping` over a query before calling `insert`:

~~~ scala
messages.map(_.sender).insertStatement
// res7: String =
//   insert into "message" ("sender")
//   values (?)
~~~

The parameter type of the `+=` method is matched to the *unpacked* type of the query, so we execute thisquery by passing it a `String` for the `sender`:

~~~ scala
messages.map(_.sender) += "HAL"
// org.h2.jdbc.JdbcSQLException:
//   NULL not allowed for column "content"; SQL statement:
// insert into "message" ("sender")  values (?) [23502-185]
//   at ...
~~~

The query fails at runtime because the `content` column is non-nullable in our schema. No matter. We'll cover nullable columns when discussing schemas in [Chapter 4](#Modelling).

### Retrieving Primary Keys on Insert

Let's modify the insert to give us back the primary key generated:

~~~ scala
(messages returning messages.map(_.id)) +=
  Message("Dave", "So... what do we do now?")
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
(messages returning messages) +=
  Message("HAL", "I don't know. I guess we wait.")
// res7: Message = ...
~~~

If we tried this with H2, we get a runtime error:

~~~ scala
(messages returning messages) +=
  Message("HAL", "I don't know. I guess we wait.")
// scala.slick.SlickException: ↩
//   This DBMS allows only a single AutoInc column ↩
//     to be returned from an INSERT
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

## Updating Rows

So far we've only looked at inserting new data into the database, but what if we want to update records that are already in the database? Slick lets us create SQL `UPDATE` queries using the same `Query` objects we saw in [Chapter 2](#Selecting).

### Updating a Single Field

In the `Messages` we've created so far we've referred to the computer from *2001: A Space Odyssey* as `"HAL"`, but the correct name is "HAL 9000".  Let's fix that:

~~~ scala
messages.filter(_.sender === "HAL").
  map(_.sender).update("HAL 9000")
// res1: Int = 2
~~~

We can retrieve the SQL for this query by calling `updateStatment` instead of `update`:

~~~ scala
messages.filter(_.sender === "HAL").
  map(_.sender).updateStatement
// res2: String =
//   update "message"
//   set "sender" = ?
//   where "message"."sender" = 'HAL'
~~~

Let's break down the code in the Scala expression. By building our update query from the `messages` `TableQuery`, we specify that we want to update records in the `message` table in the database:

~~~ scala
val messagesByHal = messages.filter(_.sender === "HAL")
// messagesByHal: scala.slick.lifted.Query[
//   Example.MessageTable,
//   Example.MessageTable#TableElementType,
//   Seq
// ] = scala.slick.lifted.WrappingQuery@537c3243
~~~

We only want to update the `sender` column, so we use `map` to reduce the query to just that column:

~~~ scala
val halSenderCol  = messagesByHal.map(_.sender)
// halSenderCol: scala.slick.lifted.Query[
//   scala.slick.lifted.Column[String],
//   String,
//   Seq
// ] = scala.slick.lifted.WrappingQuery@509f9e50
~~~

Finally we call the `update` method, which takes a parameter of the *unpacked* type (in this case `String`), runs the query, and returns the number of affected rows:

~~~ scala
val rowsAffected = halSenderCol.update("HAL 9000")
// rowsAffected: Int = 4
~~~

### Updating Multiple Fields

We can update more than one field at the same time by `mapping` the query down to a tuple of the columns we care about:

~~~ scala
messages.
  filter(_.id === 4L).
  map(message => (message.sender, message.content)).
  update("HAL 9000", "Sure, Dave. Come right in.")
// res3: Int = 1

messages.filter(_.sender === "HAL 9000").run
// res4: Seq[Example.MessageTable#TableElementType] = Vector(
//   Message(HAL 9000,Affirmative, Dave. I read you.,2),
//   Message(HAL 9000,Sure, Dave. Come right in.,4))
~~~

Again, we can see the SQL we're running using the `updateStatement` method. The returned SQL contains two `?` placeholders, one for each field as expected:

~~~ scala
messages.
  filter(_.id === 4L).
  map(message => (message.sender, message.content)).
  updateStatement
// res5: String =
//   update "message"
//   set "sender" = ?, "content" = ?
//   where "message"."id" = 4
~~~

### Updating with a Computed Value

Let's now turn to more interesting updates. How about converting every message to be all capitals? Or adding an exclamation mark to the end of each message? Both of these queries involve expressing the desired result in terms of the current value in the database. In SQL we might write something like:

~~~ sql
update "message" set "content" = "content" || '!'
~~~

This is not currently supported by `update` in Slick, but there are ways to achieve the same result. One such way is to use plain SQL queries, which we cover in [Chapter 6](#PlainSQL). Another is to perform a *client side update* by defining a Scala function to capture the change to each row:

~~~ scala
def exclaim(msg: Message): Message =
  msg.copy(content = msg.content + "!")
exclaim: Message => Message = <function1>
~~~

We can update rows by selecting the relevant data from the database, applying this function, and writing the results back individually. Note that approach can be quite inefficient for large datasets---it takes `N + 1` queries to apply an update to `N` results:

~~~ scala
messages.iterator.foreach { message =>
  messages.filter(_.id === message.id).update(exclaim(message))
}
~~~

We recommend plain SQL queries over this approach if you can use them. See [Chapter 6](#PlainSQL) for details.

## Deleting Rows

Deleting rows is very similar to updating them. We specify which rows to delete using the `filter` method and call `delete`:

~~~ scala
messages.filter(_.sender === "HAL").delete
// res6: Int = 2
~~~

As usual, the return value is the number of rows affected, and as usual, Slick provides a method that allows us to view the generated SQL:

~~~ scala
messages.filter(_.sender === "HAL").delete
// res7: String =
//   delete from "message"
//   where "message"."sender" = 'HAL'
~~~

Note that it is an error to use `delete` in combination with `map`. We can only call `delete` on a `TableQuery`:

~~~ scala
messages.map(_.content).delete
// <console>:14: error: value delete is not a member of ↩
//   scala.slick.lifted.Query[scala.slick.lifted.Column[String],String,Seq]
//               messages.map(_.content).delete
//                                       ^
~~~

## Transactions

So far, each of the changes we've made to the database has run independently of the others. That is, each insert, update, or delete query, we run can succeed or fail independently of the rest.

We often want to tie sets of modifications together in a *transaction* so that they either *all* succeed or *all* fail. We can do this in Slick using the `session.withTransaction` method:

~~~ scala
def updateContent(id: Long) =
  messages.filter(_.id === id).map(_.content)

db.withSession { implicit session =>
  session.withTransaction {
    updateContent(2L).update("Wanna come in?")
    updateContent(3L).update("Pretty please!")
    updateContent(4L).update("Opening now.")
  }

  messages.run
}
// res1: Seq[Example.MessageTable#TableElementType] = Vector(
//   Message(Dave,Hello, HAL. Do you read me, HAL?,1),
//   Message(HAL,Wanna come in?,2),
//   Message(Dave,Pretty please!,3),
//   Message(HAL,Opening now.,4))
~~~

The changes we make in the `withTransaction` block are temporary until the block completes, at which point they are *committed* and become permanent. We can alternatively *roll back* the transaction mid-stream by calling `session.rollback`, which causes all changes to be reverted:

~~~ scala
db.withSession { implicit session =>
  session.withTransaction {
    updateContent(2L).update("Wanna come in?")
    updateContent(3L).update("Pretty please!")
    updateContent(4L).update("Opening now.")
    session.rollback
  }

  messages.run
}
// res1: Seq[Example.MessageTable#TableElementType] = Vector(
//   Message(Dave,Hello, HAL. Do you read me, HAL?,1),
//   Message(HAL,Affirmative, Dave. I read you.,2),
//   Message(Dave,Open the pod bay doors, HAL.,3),
//   Message(HAL,I'm sorry, Dave. I'm afraid I can't do that.,4))
~~~

Note that the rollback doesn't happen until the `withTransaction` block ends. If we run queries *within* the block, before the rollback actually occurs, they will still see the modified state:

~~~ scala
db.withSession { implicit session =>
  session.withTransaction {
    session.rollback
    updateContent(2L).update("Wanna come in?")
    updateContent(3L).update("Pretty please!")
    updateContent(4L).update("Opening now.")
    messages.run
  }
}
// res1: Seq[Example.MessageTable#TableElementType] = Vector(
//   Message(Dave,Hello, HAL. Do you read me, HAL?,1),
//   Message(HAL,Wanna come in?,2),
//   Message(Dave,Pretty please!,3),
//   Message(HAL,Opening now.,4))
~~~

## Logging Queries and Results

We've seen how to retrieve the SQL of a query using the `selectStatement`, `insertStatement`, `updateStatement`, and `deleteStatement` queries. These are useful for exprimenting with Slick, but sometimes we want to see all the queries, fully populated with parameter data, *when Slick executes them*. We can do that by configuring logging.

Slick uses a logging interface called [SLF4J][link-slf4j]. We can configure this to capture information about the queries being run. The SBT builds in the exercises use an SLF4J-compatible logging back-end called [Logback][link-logback], which is configured in the file *src/main/resources/logback.xml*. In that file we can enable statement logging by turning up the logging to debug level:

~~~ xml
<logger name="scala.slick.jdbc.JdbcBackend.statement" level="DEBUG"/>
~~~

This causes Slick to log every query, even modifications to the schema:

~~~
DEBUG s.slick.jdbc.JdbcBackend.statement - Preparing statement: ↩
  delete from "message" where "message"."sender" = 'HAL'
~~~

We can modify the level of various loggers to log additional information:

-------------------------------------------------------------------------------------------------------------
Logger                                     Level   Effect
------------------------------------------ ------- ----------------------------------------------------------
`scala.slick.jdbc.JdbcBackend.statement`   `DEBUG` Logs SQL sent to the database as described above.

`scala.slick.jdbc.StatementInvoker.result` `DEBUG` Logs the results of each query.

`scala.slick.session`                      `DEBUG` Logs session events such as opening/closing connections.

`scala.slick`                              `DEBUG` Logs everything! Equivalent to changing all of the above.

------------------------------------------ ------- ----------------------------------------------------------

: Slick loggers and their effects.

The `StatementInvoker.result` logger, in particular, is pretty cute:

~~~
SI.result - /--------+----------------------+----------------------+----\
SI.result - | sender | content              | ts                   | id |
SI.result - +--------+----------------------+----------------------+----+
SI.result - | HAL    | Affirmative, Dave... | 2001-02-17 10:22:... | 2  |
SI.result - | HAL    | I'm sorry, Dave. ... | 2001-02-17 10:22:... | 4  |
SI.result - \--------+----------------------+----------------------+----/
~~~

## Take Home Points

<div class="callout callout-danger">
TODO: Take home points
</div>

<!--
For modifying the rows in the database we have seen that:

* deletes are via a `delete` call to a query;
* updates are via an `update` call on a query, but are somewhat limited; and
* inserts are via an `insert` (or `+=`) call on a table.

Auto-incrementing values are not inserted by Slick, unless forced. The auto-incremented values can be returned from the insert by using `returning`.

Databases have different capabilities. The limitations of each driver is listed in the driver's Scala Doc page.

Rows can be inserted in batch. For simple situations this gives performance gains. However when additional information is required back (such as primary keys), there is no advantage.

The SQL statements executed and the result returned from the database can be monitored by configuring the logging system.
-->

## Exercises

<div class="callout callout-danger">
TODO: Fix up these exercises
</div>

<!--
Experiment with the queries we discuss before trying the exercises in this chapter. The code for this chapter is in the [GitHub repository][link-example] in the _chapter-02_ folder.  As with chapter 1, you can use the `run` command in SBT to execute the code against a H2 database.
-->

### Insert New Messages Only

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

### Rollback

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

### Update Using a For Comprehension

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

### Delete All The Messages

How would you delete all messages?

<div class="solution">
~~~ scala
val deleted = messages.delete
~~~
</div>
