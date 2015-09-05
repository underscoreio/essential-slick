# Creating and Modifying Data {#Modifying}

In the last chapter we saw how to retrieve data from the database using select queries. In this chapter we will look modifying stored data using insert, update, and delete queries.

SQL veterans will know that update and delete queries, in particular, share many similarities with select queries. The same is true in Slick, where we use the `Query` monad and combinators to build the different kinds of query. Ensure you are familiar with the content of [Chapter 2](#Selecting) before proceeding.

## Inserting Data

As we saw in [Chapter 1](#Basics), adding new data a table looks like a destructive append operation on a mutable collection. We can use the `+=` method to insert a single row into a table, and `++=` to insert multiple rows. We'll discuss both of these operations below.

### Inserting Single Rows

To insert a single row into a table we use the `+=` method.

~~~ scala
val action: DBIO[Int] =
  messages += Message("HAL", "No. Seriously, Dave, I can't let you in.")

exec(action)
// res1: Int = 1
~~~

The return value is the number of rows inserted. However, it is often useful to return something else, such as the primary key generated for the new row. We can get this information using a method called `returning`. Before we get to that, we first need to understand where the primary key comes from.

### Primary Key Allocation

If we recall the definition of `Message`, we put the `id` field at the end of the case class and gave it a default value of `0L`:

~~~ scala
final case class Message(
   sender:  String,
   content: String,
   id:      Long = 0L
)
~~~

Giving the `id` parameter a default value allows us to omit it when creating a new object. Placing the `id` at the end of the constructor allows us to omit it without having to pass the remaining arguments using keyword parameters:

~~~ scala
Message("Dave", "You're off my Christmas card list.")
~~~

There's nothing special about our default value of `0L`---it's not a magic value meaning "this record has no `id`". In our running example the `id` field of `Message` is mapped to an auto-incrementing primary key (using the `O.AutoInc` option), causing Slick to ignore the value of the field when generating an insert query. The database will step in an generate the value for us. We can see the SQL we're executing using the `insertStatement` method:

~~~ scala
messages.insertStatement
// res2: String =
//   insert into "message" ("sender","content")
//   values (?,?)
~~~

Slick provides a `forceInsert` method that allows us to specify a primary key on insert, ignoring the database's suggestion:

~~~ scala
exec(
   messages forceInsert Message("HAL",
     "I'm a computer, what would I do with a Christmas card anyway?",
     1000L)
)
// res3: Int = 1

exec(
  messages.filter(_.id === 1000L).result
)
// res4: Seq[Example.MessageTable#TableElementType] =
//   Vector(Message(HAL,I'm a computer, what would I do with a Christmas card anyway?,1000))
~~~

Notice that our explicit `id` value of 1000 has been accepted by the database.

### Retrieving Primary Keys on Insert

Let's modify the insert to give us back the primary key generated:

~~~ scala
val insert: DBIO[Long] =
  messages returning messages.map(_.id) += Message("Dave", "Point taken.")

exec(insert)
// res5: Long = 1001
~~~

The argument to `messages returning` is a `Query`, which is why `messages.map(_.id)` makes sense here. We can show that the return value is a primary key by looking up the record we just inserted:

~~~ scala
exec(messages.filter(_.id === 1001L).result.headOption)
// res6: Option[Example.Message] =
//   Some(Message(Dave,Point taken.,1001))
~~~

### Retrieving Rows on Insert

H2 only allows us to retrieve the primary key from an insert. Some databases allow us to retrieve the complete inserted record. For example, we could ask for the whole `Message` back:

~~~ scala
exec(messages returning messages +=
 Message("Dave", "So... what do we do now?" ))

// res7: Message = ...
~~~

If we tried this with H2, we get a runtime error:

~~~ scala
exec(messages returning messages +=
      Message("Dave", "So... what do we do now?" ))
// scala.slick.SlickException:
//   This DBMS allows only a single AutoInc column ↩
//     to be returned from an INSERT
//   at ...
~~~

This is a shame, but getting the primary key is often all we need.

Typing `messages returning messages.map(_.id)` isn't exactly convenient, but we can easily define a query specifically for inserts:

~~~ scala
lazy val messagesReturningId = messages returning messages.map(_.id)
// messagesReturningId: slick.driver.H2Driver.ReturningInsertActionComposer[
//    Example.MessageTable#TableElementType,
//    Long
//  ] = <lazy>

exec(messagesReturningId += Message("HAL", "I don't know. I guess we wait."))
// res8: Long = 1002
~~~

Using `messagesReturningId` will return us the `id`, rather than the count of the number of rows inserted.


<div class="callout callout-info">
**Driver Capabilities**

The Slick manual contains a comprehensive table of the [capabilities for each database driver][link-ref-dbs]. The ability to return complete records from an insert query is referenced as the `jdbc.returnInsertOther` capability.

The API documentation for each driver also lists the capabilities that the driver *doesn't* have. For an example, the top of the [H2 Driver Scaladoc][link-ref-h2driver] page points out several of its shortcomings.
</div>

If we do want to get a populated `Message` back from an insert for any database, we can do it by retrieving the primary key and manually adding it to the inserted record. Slick simplifies this with another method, `into`:

~~~ scala
val messagesReturningRow =
  messages returning messages.map(_.id) into { (message, id) =>
    message.copy(id = id)
  }
// messagesReturningRow: slick.driver.H2Driver.IntoInsertActionComposer[
//   Example.MessageTable#TableElementType,
//   Example.Message
// ] = ...

val insert: DBIO[Message] =
  messagesReturningRow += Message("Dave", "You're such a jerk.")

exec(insert)
// res9: messagesReturningRow.SingleInsertResult =
//   Message(Dave,You're such a jerk.,1004)
~~~

The `into` method allows us to specify a function to combine the record and the new primary key. It's perfect for emulating the `jdbc.returnInsertOther` capability, although we can use it for any post-processing we care to imagine on the inserted data.

### Inserting Specific Columns

If our database table contains a lot of columns with default values, it is sometimes useful to specify a subset of columns in our insert queries. We can do this by `mapping` over a query before calling `insert`:

~~~ scala
messages.map(_.sender).insertStatement
// res10: String =
//   insert into "message" ("sender")
//   values (?)
~~~

The parameter type of the `+=` method is matched to the *unpacked* type of the query:

~~~ scala
messages.map(_.sender)
// res11: slick.lifted.Query[slick.lifted.Rep[String],String,Seq] = Rep(Bind)
~~~

... so we execute this query by passing it a `String` for the `sender`:

~~~ scala
exec(messages.map(_.sender) += "HAL")
// org.h2.jdbc.JdbcSQLException:
//   NULL not allowed for column "content"; SQL statement:
// insert into "message" ("sender")  values (?) [23502-185]
//   at ...
~~~

The query fails at runtime because the `sender` column is non-nullable in our schema. No matter. We'll cover nullable columns when discussing schemas in [Chapter 4](#Modelling).


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

exec(messages ++= testMessages)
// res11: Option[Int] = Some(4)
~~~

This code prepares one SQL statement and uses it for each row in the `Seq`. This can result in a significant boost in performance when inserting many records.

As we saw earlier this chapter, the default return value of a single insert is the number of rows inserted. The multi-row insert above is also returning the number of rows, except this time the type is `Option[Int]`. The reason for this is that the JDBC specification permits the underlying database driver to indicate that the number of rows inserted is unknown.

Slick also provides a batch version of `messages returning...`, including the `into` method. We can use the `messagesReturningRow` query we defined last section and write:

~~~ scala
exec(messagesReturningRow ++= testMessages)
// res12: messagesReturningRow.MultiInsertResult = List(
//   Message(Dave,Hello, HAL. Do you read me, HAL?,13),
//   ...)
~~~

## Updating Rows {#UpdatingRows}

So far we've only looked at inserting new data into the database, but what if we want to update records that are already in the database? Slick lets us create SQL `UPDATE` queries using the same `Query` objects we saw in [Chapter 2](#Selecting).

### Updating a Single Field

In the `Messages` we've created so far we've referred to the computer from *2001: A Space Odyssey* as `"HAL"`, but the correct name is "HAL 9000".  Let's fix that:

~~~ scala
exec(messages.filter(_.sender === "HAL").
  map(_.sender).update("HAL 9000"))
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
// ] = Rep(Filter)
~~~

We only want to update the `sender` column, so we use `map` to reduce the query to just that column:

~~~ scala
val halSenderCol  = messagesByHal.map(_.sender)
// halSenderCol: slick.lifted.Query[
//   slick.lifted.Rep[String],
//   String,
//   Seq
// ] = Rep(Bind)
~~~

Finally we call the `update` method, which takes a parameter of the *unpacked* type (in this case `String`), runs the query, and returns the number of affected rows:

~~~ scala
val action: DBIO[Int] = halSenderCol.update("HAL 9000")

val rowsAffected = exec(action)
// rowsAffected: Int = 4
~~~

### Updating Multiple Fields

We can update more than one field at the same time by `mapping` the query down to a tuple of the columns we care about...

~~~ scala
val query = messages.
    filter(_.id === 4L).
    map(message => (message.sender, message.content))
// query: slick.lifted.Query[
//  (slick.lifted.Rep[String], slick.lifted.Rep[String]),
//  (String, String),
//  Seq] = Rep(Bind)
~~~

...and then supplying the tuple values we want to used in the update:

~~~ scala
val action: DBIO[Int] =
  query.update(("HAL 9000", "Sure, Dave. Come right in."))

exec(action)
// res3: Int = 1

exec(messages.filter(_.sender === "HAL 9000").result)
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
update "message" set "content" = CONCAT("content", '!')
~~~

This is not currently supported by `update` in Slick, but there are ways to achieve the same result. One such way is to use Plain SQL queries, which we cover in [Chapter 6](#PlainSQL). Another is to perform a *client side update* by defining a Scala function to capture the change to each row:

~~~ scala
def exclaim(msg: Message): Message =
  msg.copy(content = msg.content + "!")
// exclaim: (msg: Example.Message)Example.Message
~~~

We can update rows by selecting the relevant data from the database, applying this function, and writing the results back individually. Note that approach can be quite inefficient for large datasets---it takes `N + 1` queries to apply an update to `N` results.

You may be tempted to write something like this:

~~~ scala
def modify(msg: Message): DBIO[Int] =
  messages.filter(_.id === msg.id).update(exclaim(msg))

for {
  msg <- exec(messages.result)
} yield exec(modify(msg))
~~~

That will produce the desired effect, but with some cost.  What we have done is use our own `exec` method which will wait for results.  We use it to fetch all rows, and then we use it on each row to modify the row. That's a lot of waiting.

A better (but not the best) approach is to try to find a way to turn our logic into a single `DBIO` action. Here's one way we can do that:

~~~ scala
val action: DBIO[Seq[Int]] =
  messages.result.flatMap { msgs => DBIO.sequence(msgs.map(modify)) }

val rowCounts: Seq[Int] = exec(action)
// rowCounts: List(1, 1, 1, 1, 1)
~~~

To make sense of this we need to take `action` apart.

To start with we know that `messages.result` is all the messages in the database, as a `DBIO[Seq[Message]]`.
The `flatMap` method, expects a function from our `Seq[Message]` to another `DBIO`.
Our problem here is that we're updating many rows, via many actions, so how can we get a single `DBIO` from that?
Slick provides `DIO.sequence` for that purpose: it takes a sequence of `DBIO`s and gives back a `DBIO` of a sequence.

The end result is a single action we can run, which turns into many SQL statements. In fact the action will result in:

~~~ sql
select x2."sender", x2."content", x2."id" from "message" x2
update "message" set "sender" = ?, "content" = ?, "id" = ? where "message"."id" = 1
update "message" set "sender" = ?, "content" = ?, "id" = ? where "message"."id" = 2
update "message" set "sender" = ?, "content" = ?, "id" = ? where "message"."id" = 3
update "message" set "sender" = ?, "content" = ?, "id" = ? where "message"."id" = 4
update "message" set "sender" = ?, "content" = ?, "id" = ? where "message"."id" = 5
~~~

We'll turn to other ways to combine actions in the next section.

However, for this particular example, we recommend using Plain SQL ([Chapter 6](#PlainSQL)) instead of client-side updates.


## Combining Actions

Actions can be combined via a set of combinator functions that Slick provides.  


----------------------------------------------------------------------------------------------------
Method              Arguments                       Result Type      Notes
------------------- -----------------------------   ---------------- ------------------------------
`map`               `T => R`                        `DBIO[R]`        Execution context required

`flatMap`           `T => DBIO[R]`                  `DBIO[R]`        _ditto_

`filter`            `R => Boolean`                  `DBIO[T]`        _ditto_

`named`             `String`                        `DBIO[T]`        

`zip`               `DBIO[R]`                       `DBIO[(T,R)]`    

`asTry`                                             `DBIO[Try[T]]`    

`andThen` or `>>`   `DBIO[R]`                       `DBIO[Unit]`     Example in Chapter 1.

`andFinally`        `DBIO[_]`                       `DBIO[T]`        

`cleanUp`           `Option[Throwable]=>DBIO[_]`    `DBIO[T]`        Execution context required

`failed`                                            `DBIO[Throwable]`
----------------------------------------------------------------------------------------------------

: Combinators on action instances of `DBIOAction`, specifically a `DBIO[T]`.
  Types simplified.



----------------------------------------------------------------------------------------------------------
Method       Arguments                       Result Type                    Notes
------------ ------------------------------- ------------------------------ ------------------------------
`sequence`   `TraversableOnce[DBIO[T]]`      `DBIO[TraversableOnce[T]]`     Example in the previous section

`seq`        `DBIO[_]*`                      `DBIO[Unit]`                   Combines actions with `andThen`

`from`       `Future[T]`                     `DBIO[T]`                       

`successful` `V`                             `DBIO[V]`                      

`failed`     `Throwable`                     `DBIO[Nothing]`                

`fold`       `(Seq[DBIO[T]], T)  (T,T)=>T`   `DBIO[T]`                      Execution context required
----------------------------------------------------------------------------------------------------------

: Combinators on `DBIO` object, with types simplified.


TODO

- table of methods on Actions

- material from blog post on upsert? Maybe ignoring talking about upsert for some future update unless we have the enegery to add it now. If so, suggest separate section just befoe "Combining action"


## Deleting Rows

Deleting rows is very similar to updating them. We specify which rows to delete using the `filter` method and call `delete`:

~~~ scala
exec(messages.filter(_.sender === "HAL").delete)
// res6: Int = 2
~~~

As usual, the return value is the number of rows affected, and as usual, Slick provides a method that allows us to view the generated SQL:

~~~ scala
messages.filter(_.sender === "HAL").delete.statements
// res7: Iterable[String] = List(
//   delete from "message"
//   where "message"."sender" = 'HAL')
~~~

Note that it is an error to use `delete` in combination with `map`. We can only call `delete` on a `TableQuery`:

~~~ scala
messages.map(_.content).delete
// <console>:14: error: value delete is not a member of ↩
//   slick.lifted.Query[slick.lifted.Column[String],String,Seq]
//          messages.map(_.content).delete
//                                  ^
~~~

## Transactions

So far, each of the changes we've made to the database have run independently of the others. That is, each insert, update, or delete query, we run can succeed or fail independently of the rest.

We often want to tie sets of modifications together in a *transaction* so that they either *all* succeed or *all* fail. We can do this in Slick using the `transactionally` method:

~~~ scala
def updateContent(id: Long) =
  messages.filter(_.id === id).map(_.content)

exec {
    (updateContent(2L).update("Wanna come in?") andThen
     updateContent(3L).update("Pretty please!") andThen
     updateContent(4L).update("Opening now.")).transactionally
  }

  exec(messages.result)
}
// res1: Seq[Example.MessageTable#TableElementType] = Vector(
//   Message(Dave,Hello, HAL. Do you read me, HAL?,1),
//   Message(HAL,Wanna come in?,2),
//   Message(Dave,Pretty please!,3),
//   Message(HAL,Opening now.,4))
~~~

The changes we make in the `transactionally` block are temporary until the block completes, at which point they are *committed* and become permanent.

To manually force a rollback you need to call `DBIO.failed` with an appropriate exception.

~~~ scala
try {
  exec {
    (
    updateContent(2L).update("Blue Mooon")                          andThen
    updateContent(3L).update("Please, anything but your singing ")  andThen
    messages.result.map(_.foreach { println })                      andThen
    DBIO.failed(new Exception("agggh my ears"))                     andThen
    updateContent(4L).update("That's incredibly hurtful")
    ).transactionally
  }

} catch {
  case weKnow: Throwable => println("expected")
}
~~~
Note:
  - `transactionally` is applied to the  parentheses surrounding the combined actions and not applied to the last action,
  - we need to catch the exception,
  - we can see the updates temporarily applied before `DBIO.failed` is called.

Due to a [bug][link-scala-type-alias-bug] in Scala we can not investigate this within the repl, although it is looking
good to be fixed in [Slick 3.1][link-slick-type-alias-pr].

## Logging Queries and Results

We've seen how to retrieve the SQL of a query using the `result.statements`, `insertStatement`, `update(???).statements`, and `delete.statements` queries. These are useful for exprimenting with Slick, but sometimes we want to see all the queries, fully populated with parameter data, *when Slick executes them*. We can do that by configuring logging.

Slick uses a logging interface called [SLF4J][link-slf4j]. We can configure this to capture information about the queries being run. The SBT builds in the exercises use an SLF4J-compatible logging back-end called [Logback][link-logback], which is configured in the file *src/main/resources/logback.xml*. In that file we can enable statement logging by turning up the logging to debug level:

~~~ xml
<logger name="slick.jdbc.JdbcBackend.statement" level="DEBUG"/>
~~~

This causes Slick to log every query, even modifications to the schema:

~~~
DEBUG slick.jdbc.JdbcBackend.statement - Preparing statement: ↩
  delete from "message" where "message"."sender" = 'HAL'
~~~

We can modify the level of various loggers, as shown in table 3.1.

-------------------------------------------------------------------------------------------------------------------
Logger                                 Effect
-------------------------------------  ----------------------------------------------------------
`slick.jdbc.JdbcBackend.statement`     Logs SQL sent to the database as described above.

`slick.jdbc.StatementInvoker.result`   Logs the results of each query.

`slick.session`                        Logs session events such as opening/closing connections.

`slick`                                Logs everything! Equivalent to changing all of the above.
-------------------------------------  ----------------------------------------------------------

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

For modifying the rows in the database we have seen that:

* inserts are via a  `+=` or `++=` call on a table.
* updates are via an `update` call on a query, but are somewhat limited when you need to update using the existing row value; and
* deletes are via a  `delete` call to a query;

Auto-incrementing values are inserted by Slick, unless forced. The auto-incremented values can be returned from the insert by using `returning`.

Databases have different capabilities. The limitations of each driver is listed in the driver's Scala Doc page.

The SQL statements executed and the result returned from the database can be monitored by configuring the logging system.

## Exercises

The code for this chapter is in the [GitHub repository][link-example] in the _chapter-03_ folder.  As with chapter 1 and 2, you can use the `run` command in SBT to execute the code against a H2 database.


### Insert New Messages Only

Messages sent to our application might fail, and might be resent to us.  Write a method that will insert a message for someone, but only if the message content hasn't already been stored. We want the `id` of the message as a result.

The signature of the method is:

~~~ scala
def insertOnce(sender: String, message: String): Long = ???
~~~

<div class="solution">
~~~ scala
def insertOnce(sender: String, text: String): Long = {
  val exists =
    exec(messages.filter(m => m.content === text &&
      m.sender === sender).map(_.id).result.headOption)

  lazy val insert = exec((messages returning messages.map(_.id)) +=
    Message(sender, text))

  exists getOrElse insert
}
~~~
</div>
<!-- This is no longer applicable
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
-->
### Update Using a For Comprehension

Rewrite the update statement below to use a for comprehension.

~~~ scala
val rowsAffected = messages.
                    filter(_.sender === "HAL").
                    map(msg => (msg.sender, msg.ts)).
                    update("HAL 9000", DateTime.now)
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
