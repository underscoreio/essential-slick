# Creating and Modifying Data {#Modifying}

In the last chapter we saw how to retrieve data from the database using select queries. In this chapter we will look modifying stored data using insert, update, and delete queries.

SQL veterans will know that update and delete queries, in particular, share many similarities with select queries. The same is true in Slick, where we use the `Query` monad and combinators to build the different kinds of query. Ensure you are familiar with the content of [Chapter 2](#Selecting) before proceeding.

This chapter also introduces the important concept of _action combinators_.
These combinators, such as `flatMap`, enable us to combine actions into a single action.
The result is an action that can be made up of multiple updates, selects, deletes, or other actions.

## Inserting Rows

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

### More Control over Inserts {#moreControlOverInserts}

At this point we've inserted fixed data into the database.
Sometimes you need more flexibility, including inserting data based on another query.
Slick supports this via `forceInsertQuery`.

The argument to `forceInsertQuery` is a query.  So the form is:

~~~ scala
 insertExpression.forceInsertQuery(selectExpression)
~~~

Our `selectExpression` can be pretty much anything.
But it needs to match the columns needed by our `insertExpression`.

As an example, our query could check to see if a particular row of data already exists, and insert it if it doesn't.
That is, an "insert if doesn't exist" function.

Let's say we only want the director to be able to say "Cut!" once. The SQL would end up like this:

~~~ sql
insert into "messages" ("sender", "content")
  select 'Stanley', 'Cut!'
where
  not exists(
    select
      "id", "sender", "content"
    from
      "messages" where "name" = 'Stanley'
                 and   "content" = 'Cut!')
~~~

That looks quite involved, but we can build it up gradually.

The tricky part of this is the `select 'Stanley', 'Cut!'` part, as there is no `FROM` clause there.
We saw an example of how to create that in Chapter 2, with `Query.apply`.

For this situation it would be:

~~~ scala
val data = Query("Stanley" -> "Cut!")

// data: slick.lifted.Query[
//  (slick.lifted.ConstColumn[String], slick.lifted.ConstColumn[String]),
//  (String, String),
//  Seq] = Rep(Pure $@1413606951)
~~~

That's a tuple of two columns. That's one part of the what we need.

We also need to be able to test to see if the data already exists. That's straight-forward:

~~~ scala
val exists =
  messages
   .filter(m => m.sender === "Stanley" && m.content === "Cut!")
   .exists

// exists: slick.lifted.Rep[Boolean] = Rep(Apply Function exists)
~~~

We want to use the `data` when the row _doesn't_ exists, so combine the `data` and `exists` with `filterNot` rather than `filter`:

~~~ scala
val selectExpression = data.filterNot(_ => exists)

// selectExpression: slick.lifted.Query[
//  (slick.lifted.ConstColumn[String], slick.lifted.ConstColumn[String]),
//  (String, String),Seq] = Rep(Filter)
~~~

Finally, we need to apply this query with `forceInsertQuery`.
But remember the column types for the insert and select need to match up.
So we `map` on `messages` to make sure that's the case:

~~~ scala
val action =
  messages
    .map(m => m.sender -> m.content)
    .forceInsertQuery(selectExpression)

exec(action)
// res13: Int = 1

exec(action)
//  res14: Int = 0  
~~~

The first time we run the query, the message is inserted.
The second time, no rows are affected.

In summary, `forceInsertQuery` provides a way to build-up more complicated inserts.
If you find situations beyond the power of this method,
you can always make use of Plain SQL inserts, described in [Chapter 6](#PlainSQL).


## Deleting Rows

Slick lets us delete rows using the same `Query` objects we saw in [Chapter 2](#Selecting).
That is, we specify which rows to delete using the `filter` method, and then call `delete`:

~~~ scala
val removeHal: DBIO[Int] =
  messages.filter(_.sender === "HAL").delete

exec(removeHal)
// res1: Int = 2
~~~

The return value is the number of rows affected.  

The SQL generated for the action can be seen by calling `delete.statements`:

~~~ scala
messages.filter(_.sender === "HAL").delete.statements
// res2: Iterable[String] = List(
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


## Updating Rows {#UpdatingRows}

So far we've only looked at inserting new data into the database, and deleting existing data. But what if we want to update records that are already in the database? Slick lets us create SQL `UPDATE` actions via the kinds of `Query` values we've been using for selecting and deleting rows.

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

// Not the best way, avoid:
for {
  msg <- exec(messages.result)
} yield exec(modify(msg))
~~~

There's nothing wrong with this, and it will produce the desired effect, but at some cost.
What we have done there is use our own `exec` method which will wait for results.
We use it to fetch all rows, and then we use it on each row to modify the row.
That's a lot of waiting.

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
Slick provides `DBIO.sequence` for that purpose: it takes a sequence of `DBIO`s and gives back a `DBIO` of a sequence.

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

At some point you'll find yourself writing a piece of functionality made up of multiple actions.
The temptation, as we have seen above, is to run each action, use the result, and run another action.
This will require you to deal with multiple `Future`s. We recommend you avoid that whenever you can.

Instead, focus on the actions and how they combine together, not on the messy details of running them.
Slick provides a set of combinators to make this possible.

This is a key concept in Slick. Make sure you spend time getting comfortable with combining actions.

### Combinators Summary

There are two tables in this section. They list out the key methods available on an action,
and the combinators available on `DBIO`.

Some, such as `map`, `fold`, and `zip`, will be familiar from the Scala collections library.
We will give examples of how to use many of them in this section.

----------------------------------------------------------------------------------------------------
Method              Arguments                       Result Type      Notes
------------------- -----------------------------   ---------------- ------------------------------
`map`               `T => R`                        `DBIO[R]`        Execution context required

`flatMap`           `T => DBIO[R]`                  `DBIO[R]`        _ditto_

`filter`            `T => Boolean`                  `DBIO[T]`        _ditto_

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

`seq`        `DBIO[_]*`                      `DBIO[Unit]`                   Combines actions, ignores results

`from`       `Future[T]`                     `DBIO[T]`                       

`successful` `V`                             `DBIO[V]`                      

`failed`     `Throwable`                     `DBIO[Nothing]`                

`fold`       `(Seq[DBIO[T]], T)  (T,T)=>T`   `DBIO[T]`                      Execution context required
----------------------------------------------------------------------------------------------------------

: Combinators on `DBIO` object, with types simplified.


### `andThen` (or `>>`)

The simplest way to run one action after another is perhaps `andThen`.
The combined actions are both run, but only the result of the second is returned:

~~~ scala
val reset: DBIO[Int] =
  messages.delete andThen messages.size.result

exec(reset)
// res1: Int = 0
~~~

The result of the first query is ignored, so we cannot use.
Later we will see how `flatMap` allows us to use the result to make choices about which action to run next.

### `DBIO.seq`

If you have a bunch of actions you want to run, you can use `DBIO.seq` to combine them:

~~~ scala
val reset: DBIO[Unit] =
  DBIO.seq(messages.delete, messages.size.result)
~~~

This is rather like combining the actions with `andThen`, but even the last value is discarded.

### `map`

Mapping over an action is a way to set up a transformation of a value from the database.
The transformation will run when the result is available from the database.

As an example, we can create an action to return the text of a message from the database:

~~~ scala
val text: DBIO[Option[String]] =
  messages.map(_.content).result.headOption
~~~

This is the regular kind of Slick code you've seen many times. There's nothing new there.

We can now take this action and transform it so the text is obfuscated:

~~~ scala
import scala.concurrent.ExecutionContext.Implicits.global

// From: http://rosettacode.org/wiki/Rot-13#Scala
def rot13(s: String) = s map {
  case c if 'a' <= c.toLower && c.toLower <= 'm' => c + 13 toChar
  case c if 'n' <= c.toLower && c.toLower <= 'z' => c - 13 toChar
  case c => c
}

val action: DBIO[Option[String]] =
  text.map{ optionText => optionText.map(rot13) }

exec(action)
// res1: Option[String] =
//  Some(Uryyb, UNY. Qb lbh ernq zr, UNY?!)
~~~

What we _didn't_ do is run the query and then `rot13` the result.
That would have involved us dealing with `Future[Option[String]]`.
Instead we used a much cleaner way of writing code:
we created an action that when run would ensure our `rot13` function is applied to the result.

Note that we have made four uses of `map` in this example:

- `String`'s `map` to obfuscate text in `rot13`;
- an `Option` `map` to apply `rot13` to our `Option[String]` result;
- a `map` on a query to select just the `content` column; and
- `map` on our action so that the result will be transform when the action is run.

Combinators everywhere!

This example transformed an `Option[String]` to another `Option[String]`.
As you may expect if `map` changes the type of a value, the type of `DBIO` changes too:

~~~ scala
text.map(os => os.map(_.length))// res2: slick.dbio.DBIOAction[
//   Option[Int],
//   slick.dbio.NoStream,
//   slick.dbio.Effect.All
// ]
~~~

<div class="callout callout-info">
**Execution Context Required**

Some methods require an execution context and some don't. For example, `map` does, but `andThen` does not.

The reason for this is that `map` allows you to call arbitrary code when joining the actions together.
Slick cannot allow that code to be run on its own execution context,
because it has no way to know if you are going to tie up Slicks threads for a long time.

In contrast, methods such as `andThen` which combine actions without custom code can be run on Slick's own execution context.
Therefore, you do not need an execution context available for `andThen`.

You'll know if you need an execution context, because the compiler will tell you:

~~~
error: Cannot find an implicit ExecutionContext. You might pass
  an (implicit ec: ExecutionContext) parameter to your method
  or import scala.concurrent.ExecutionContext.Implicits.global.
~~~

The Slick manual discusses this in the section on [Database I/O Actions][link-ref-actions].
</div>


### `filter`

As with `map`, `filter` is something you'll be familiar with, but there is a twist with Slick.

Just like `filter` in the Scala collections library or on `Option`, `filter` takes a predicate function as an argument.

~~~ scala
val text: DBIO[String] =
  messages.map(_.content).result.head

val longMsgAction: DBIO[String] =
  text.filter(s => s.length > 10)
~~~

So `filter` on an action gives us another action.
When we run the `longMsgAction` we get a result if the value from the database is longer than 10 characters.

~~~ scala
exec(longMsgAction)
// res1: Hello, HAL. Do you read me, HAL?!
~~~

The surprise comes if our predicate evaluates to `false`.
When working with `Option`, if the predicate is `false` the result is `None`.
But for actions, the result is an exception:

~~~
java.util.NoSuchElementException: Action.withFilter failed
~~~

That makes `filter` tricky to work with, but you have some tools to help.
First, if you want different behaviour from a filter-like function, you can implement it pretty easily with `flatMap`.
We will get to `flatMap` shortly.

Another option is to wrap the filter with a try, via `asTry`.

<div class="callout callout-info">
**Which `filter`?**

Why would you even use `filter` on an action?
One situation would be a test you want to apply which you cannot implement in the database.
However, if you can implement the test via a `WHERE` clause,
you'll probably be better off performing the `filter` on the _query_, not the _action_.
</div>

### `asTry`

Calling `asTry` on an action changes the action's type from a `DBIO[T]` to a `DBIO[Try[T]]`.
This means you can work in terms of Scala's `Success[T]` and `Failure` instead of exceptions.

Continuing with the example from `filter`, we can deal with a failure:

~~~ scala
val text: DBIO[String] =
  messages.map(_.content).result.head

val willFail: DBIO[Try[String]] =
  text.filter(s => s.length > 10000).asTry

exec(willFail)
// res1: Failure(java.util.NoSuchElementException: Action.withFilter failed)  
~~~


### `DBIO.successful` and `DBIO.failed`

When combining actions you will sometimes need to create an action that represents a simple value.
Slick provides `DBIO.successful` for that purpose:

~~~ scala
val v: DBIO[Int] = DBIO.successful(100)
// v: slick.dbio.DBIO[Int] = SuccessAction(100)
~~~

We'll see an example of this when we discuss `flatMap`.

And for failures, the value is a `Throwable`:

~~~ scala
val v: DBIO[Nothing] =
  DBIO.failed(new RuntimeException("pod bay door unexpectedly locked"))
// v: slick.dbio.DBIO[Nothing] = FailureAction(
//  java.lang.RuntimeException: pod bay door unexpectedly locked)
~~~

This has a particular role to play inside transactions, which we cover later in this chapter.


<div class="callout callout-info">
**Error: value successful is not a member of object slick.dbio.DBIO**

Due to a [bug][link-scala-type-alias-bug] in Scala you may experience something like the above error when using `DBIO` methods on the REPL with Slick 3.0. This is resolved in Slick 3.1.

If you do encounter it, and have to stay with Slick 3.0,
you can carry on by writing your code in a `.scala` source file and running it from SBT.
</div>


### `flatMap`

Ahh, `flatMap`. Wonderful `flatMap`.
This method gives us the power to sequence actions and decide what we want to do at each step.

The signature of `flatMap` should feel similar to the `flatMap` you see elsewhere:

~~~ scala
// Simplified:
def flatMap[S](f: R => DBIO[S])(implicit e: ExecutionContext): DBIO[S]
~~~

That is, we give `flatMap` a function that depends on the value from an action, and evaluates to another action.

As an example, let's write a method to remove all the crew's messages, and post a message saying how many messages were removed.
This will involve an `INSERT` and a `DELETE`, both of which we're familiar with:

~~~ scala
val delete: DBIO[Int] =
  messages.delete

def insert(count: Int) =
  messages += Message("NOBODY", s"I removed ${count} messages")
~~~

The first thing `flatMap` allows us to do is run these actions in order:

~~~ scala
import scala.concurrent.ExecutionContext.Implicits.global

val resetMessagesAction: DBIO[Int] =
  delete.flatMap{ count => insert(count) }

exec(resetMessagesAction)
// res1: Int = 1
~~~

This single action produces the two SQL expressions you'd expect:

~~~ sql
delete from "message"
insert into "message" ("sender","content")  values ('NOBODY', 'I removed 4 messages')
~~~


Beyond sequencing, `flatMap` also gives us control over which actions are run.
To illustrate this we will change `resetMessagesAction` to not insert a message if no messages were removed in the first step:

~~~ scala
val resetMessagesAction: DBIO[Int] =
  delete.flatMap{
    case 0 => DBIO.successful(0)
    case n => insert(n)
  }
~~~

We've decided a result of `0` is right if no message was inserted.
But the point here is that `flatMap` gives us arbitrary control over how actions can be combined.

Occasionally the compiler will complain about a `flatMap` and need your help to figuring out the types.
Recall that `DBIO[T]` is an alias for `DBIOAction[T,S,E]`, encoding streaming and effects.
When mixing effects, such as inserts and selects, you may need to explicitly specify the types:

~~~ scala
query.flatMap[Int, dbio.NoStream, dbio.Effect.All] { .... etc ... }
~~~

...but for many cases the compiler will figures these out for you.


<div class="callout callout-info">
**Do it the database if you can**

Combining actions to sequence queries is a powerful feature of Slick.
However, you may be able to reduce multiple queries into a single database query.
If you can do that, you're probably better off doing it.

As an example, you could implement "insert if not exists" like this:

~~~ scala
// Not the best way:
def insertIfNotExists(m: Message): DBIO[Int] = {
  val query =
    messages.filter(_.content === m.content).result.headOption
  query.flatMap {
    case Some(m) => DBIO.successful(0)
    case None    => messages += m
  }
}
~~~

...but as we saw earlier in ["More Control over Inserts"](#moreControlOverInserts) you can achieve the same effect with a single SQL statement.
And one query can often be better than sequencing multiple queries.
</div>

### `DBIO.fold`

Recall that the Scala collections supports `fold` as a way to combine values:

~~~ scala
List(3,5,7).fold(1) { (a,b) => a * b }
// res1: Int = 105
~~~

You can do the same kind of thing in Slick:
when you need to run a sequence of actions, and reduce the results down to a value, you use `fold`.

As an example, let's suppose we have a complicated way of measuring the sentiment of the crews' messages:

~~~ scala
// Feel free to implement a more realistic measure!
def sentiment(m: Message): Int =
  scala.util.Random.nextInt(100)
~~~

Let's start measuring the sentiment of each crew member, but just gather the happy messages.
Let's say any score above 50 is happy:

~~~ scala
def isHappy(message: Message): Boolean =
  sentiment(message) > 50
~~~

We're going to ask for each crew members mesages in turn:

~~~ scala
def sayingsOf(crewName: String): DBIO[Seq[Message]] =
  messages.filter(_.sender === crewName).result

// An action for each crew member:
val actions: List[DBIO[Seq[Message]]] =
  sayingsOf("Dave") :: sayingsOf("HAL") :: Nil
~~~

To find the happy messages we `fold` those `actions` with a function.

But we also need to consider our starting position.
There might be no happy messages:

~~~ scala
val default: Seq[Message] = Seq.empty
~~~

Finally we can produce an action to give us just the happy crew messages:

~~~ scala
val roseTinted: DBIO[Seq[Message]] =
  DBIO.fold(actions, default) {
    (happy, crewMessages) => crewMessages.filter(isHappy) ++ happy
}
~~~

`DBIO.fold` is a way to combine actions, such that the results are combined by a function you supply.
As with other combinators, your function isn't run until we execute the `roseTinged` action itself.


### `zip`

We've seen how `DBIO.seq` will combine actions and ignore the results.
We've also seen that `andThen` combines actions and keeps one result.
If you want to keep both results, `zip` is for you:

~~~ scala
val countAndHal: DBIO[(Int, Seq[Message])] =
  messages.size.result zip messages.filter(_.sender === "HAL").result

exec(countAndHall)
// res1: (Int, Seq[Example.Message]) =
//  (4,
//   Vector(
//    Message(HAL,Affirmative, Dave. I read you.,8),
//    Message(HAL,I'm sorry, Dave. I'm afraid I can't do that.,10)
//   )
// )
~~~

Notice the action is a tuple, representing the values we'll receive from both queries.


### `andFinally` and `cleanUp`

The two methods `cleanUp` and `andFinally` act a little like Scala's `catch` and `finally`.

`cleanUp` runs after an action completes, and has access to any error information (if any) as an `Option[Throwable]`:

~~~ scala
// Let's record problems we encounter:
def log(err: Throwable): DBIO[Int] =
  messages += Message("SYSTEM", err.getMessage)

// Pretend this is important work which might fail:
val work =
  DBIO.failed(new RuntimeException("Boom!"))

val action =
  work.cleanUp {
    case Some(err) => log(err)
    case None      => DBIO.successful(0)
  }

exec(action)
// java.lang.RuntimeException: Boom!
//  ... 45 elided

exec(messages.filter(_.sender === "SYSTEM").result)
// res1: Seq[Example.MessageTable#TableElementType] =
//  Vector(Message(SYSTEM,Boom!,11))
~~~

Notice the result is still the original exception, but `cleanUp` has produced a side-effect for us.

Both `cleanUp` and `andFinally` run after an action, regardless of whether it succeeds or fails.
The difference with `andFinally` is that it just runs, and has no access to the `Option[Throwable]`
that `cleanUp` sees.


## Transactions

So far, each of the changes we've made to the database have run independently of the others. That is, each insert, update, or delete query, we run can succeed or fail independently of the rest.

We often want to tie sets of modifications together in a *transaction* so that they either *all* succeed or *all* fail. We can do this in Slick using the `transactionally` method.

As an example, we can re-write the story. We want to make sure the script changes all complete or nothing changes:

~~~ scala
def updateContent(id: Long) =
  messages.filter(_.id === id).map(_.content)

exec {
  (updateContent(2L).update("Wanna come in?") andThen
   updateContent(3L).update("Pretty please!") andThen
   updateContent(4L).update("Opening now.") ).transactionally
}

exec(messages.result)
// res1: Seq[Example.MessageTable#TableElementType] = Vector(
//   Message(Dave,Hello, HAL. Do you read me, HAL?,1),
//   Message(HAL,Wanna come in?,2),
//   Message(Dave,Pretty please!,3),
//   Message(HAL,Opening now.,4))
~~~

The changes we make in the `transactionally` block are temporary until the block completes, at which point they are *committed* and become permanent.

To manually force a rollback you need to call `DBIO.failed` with an appropriate exception.

~~~ scala
val willRollback = (
  (messages += Message("HAL",  "Daisy, Daisy..."))                   >>
  (messages += Message("Dave", "Please, anything but your singing")) >>
  DBIO.failed(new Exception("agggh my ears"))                        >>
  (messages += Message("HAL", "Give me your answer do"))
  ).transactionally

exec(willRollback.asTry)
// scala.util.Try[Int] =
//  Failure(java.lang.Exception: agggh my ears)
~~~

The result of running `willRollback` is that the database won't have changed.
Inside of transactional block, you would see the inserts until `DBIO.failed` is called.

If we removed the `.transactionally` that is wrapping our combined actions, the first two inserts would succeed,
even though the combined action failed.


## Logging Queries and Results

With actions combined together, it's useful to see the queries that are being exectured.

We've seen how to retrieve the SQL of a query using the `insertStatement`, `delete.statements`, and similar methods.
These are useful for experimenting with Slick, but sometimes we want to see all the queries, fully populated with parameter data, *when Slick executes them*. We can do that by configuring logging.

Slick uses a logging interface called [SLF4J][link-slf4j]. We can configure this to capture information about the queries being run. The SBT builds in the exercises use an SLF4J-compatible logging back-end called [Logback][link-logback], which is configured in the file *src/main/resources/logback.xml*. In that file we can enable statement logging by turning up the logging to debug level:

~~~ xml
<logger name="slick.jdbc.JdbcBackend.statement" level="DEBUG"/>
~~~

This causes Slick to log every query, even modifications to the schema:

~~~
DEBUG slick.jdbc.JdbcBackend.statement - Preparing statement: ↩
  delete from "message" where "message"."sender" = 'HAL'
~~~

We can change the level of various loggers, as shown in the table below:

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

Inserts, selects, deletes and other forms of Database Action can be combined using `flatMap` and other combinators.
These can be executed in a transaction.

Finally, we saw that the SQL statements executed and the result returned from the database can be monitored by configuring the logging system.

## Exercises

The code for this chapter is in the [GitHub repository][link-example] in the _chapter-03_ folder.  As with chapter 1 and 2, you can use the `run` command in SBT to execute the code against a H2 database.

### First!

Create a method that will insert a message, but if it is the first message in the database,
automatically insert the message "First!" before it.

Use your knowledge of action combinators to achieve this.

<div class="solution">
~~~ scala
TODO
~~~
</div>

### Duped

Messages that a repeated are just noise.
Write a delete expression that will remove all repeated messages.

For example, if the database contains the messages...

* Hello
* Morning
* Morning

...then regardless of who sent them, after the delete we just expect to have "Hello" in the database.

<div class="solution">
~~~ scala
TODO
~~~
</div>

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

### Filter Revisited

In this chapter we noted that `DBIO`'s `filter` method produces a run-time exception if the filter predicate is false.  We commented that you could write your own `filter` if that wasn't what you wanted.

Create your own version of `filter` which will take some other action when the filter predicate fails.  The signature could be:

TODO TODO TODO TODO


### Unfolding

We saw that `fold` can take a number of actions and reduce them using a function you supply.
Now imagine the opposite: unfolding an initial value into a sequence of values via a function.
In this exercise we want you to write an `unfold` method that will do just that.

Why would you need to do something like this?
One example would be when you have a tree structure represented in a database and need to search it.
You can follow a link between rows, possibly recording what you find as you follow those links.

As an example, let's pretend the crew's ship is just a set of rooms, one connected to just one other:

~~~ scala
final case class Room(name: String, connectsTo: String)

final class FloorPlan(tag: Tag) extends Table[Room](tag, "floorplan") {
  def name       = column[String]("name")
  def connectsTo = column[String]("next")
  def * = (name, next) <> (Room.tupled, Room.unapply)
}

lazy val floorplan = TableQuery[FloorPlan]

exec {
  (floorplan.schema.create) >>
  (floorplan += Room("Outside",     "Podbay Door")) >>
  (floorplan += Room("Podbay Door", "Podbay"))      >>
  (floorplan += Room("Podbay",      "Galley"))      >>
  (floorplan += Room("Galley",      "Computer"))    >>
  (floorplan += Room("Computer",    "Engine Room"))
}
~~~

For any given room it's easy to find the next room. For example:

~~~ sql
SELECT
  "connectsTo"
FROM
  "foorplan"
WHERE
  "name" = 'Podbay'

-- Returns 'Galley'
~~~

Write a method `unfold` that will take any room name as a starting point, and a query to find the next room, and will follow all the connections until there are no more connecting rooms.

The signature of `unfold` could be:

~~~ scala
def unfold(
  z: String,
  f: String => DBIO[Option[String]]
  ): DBIO[Seq[String]]
~~~

... where `z` is the starting ("zero") room, and `f` will lookup the connecting room.

If `unfold` is given `"Podbay"` as a starting point it should return an action which, when run, will produce: `Seq("Galley", "Computer", "Engine Room")`.

<div class="solution">

The trick here is to recognise that:

1. this is a recursive problem, so we need to define a stopping condition.

2. we need to find a combinator for actions that will pass a value long. That job can be handled by `flatMap`.  

TODO ... explain more steps.


The solution below is generalized with `T` rather than having a hard-coded `String` type.

TODO .... This isn't quite right: the results are in the wrong order, doesn't quite follow the suggested signature....

~~~ scala
def unfold[T]
  (z: T, acc: Seq[T] = Seq.empty)
  (f: T => DBIO[Option[T]]): DBIO[Seq[T]] =
  f(z).flatMap {
    case None    => DBIO.successful(acc)
    case Some(t) => unfold(t, z +: acc)(f)
  }

println("\nRoom path:")
val path: DBIO[Seq[String]] =
  unfold("Podbay") {
     r => floorplan.filter(_.name === r).map(_.connectsTo).result.headOption
   }
println( exec(path) )
// ??? TODO
~~~
</div>

