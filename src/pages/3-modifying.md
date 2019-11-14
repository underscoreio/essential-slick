```scala mdoc:invisible
import slick.jdbc.H2Profile.api._

case class Message(
  sender:  String,
  content: String,
  id:      Long = 0L)

class MessageTable(tag: Tag) extends Table[Message](tag, "message") {

  def id      = column[Long]("id", O.PrimaryKey, O.AutoInc)
  def sender  = column[String]("sender")
  def content = column[String]("content")

  def * = (sender, content, id).mapTo[Message]
}

lazy val messages = TableQuery[MessageTable]

import scala.concurrent.{Await,Future}
import scala.concurrent.duration._

val db = Database.forConfig("chapter03")

def exec[T](action: DBIO[T]): T = Await.result(db.run(action), 2.seconds)

def freshTestData = Seq(
  Message("Dave", "Hello, HAL. Do you read me, HAL?"),
  Message("HAL",  "Affirmative, Dave. I read you."),
  Message("Dave", "Open the pod bay doors, HAL."),
  Message("HAL",  "I'm sorry, Dave. I'm afraid I can't do that.")
)

exec(messages.schema.create andThen (messages ++= freshTestData))
```

# Creating and Modifying Data {#Modifying}

In the last chapter we saw how to retrieve data from the database using select queries. In this chapter we will look at modifying stored data using insert, update, and delete queries.

SQL veterans will know that update and delete queries share many similarities with select queries. The same is true in Slick, where we use the `Query` monad and combinators to build the different kinds of query. Ensure you are familiar with the content of [Chapter 2](#selecting) before proceeding.

## Inserting Rows

As we saw in [Chapter 1](#Basics), adding new data looks like an append operation on a mutable collection. We can use the `+=` method to insert a single row into a table, and `++=` to insert multiple rows. We'll discuss both of these operations below.

### Inserting Single Rows

To insert a single row into a table we use the `+=` method. Note that, unlike the select queries we've seen, this creates a `DBIOAction` immediately without an intermediate `Query`:

```scala mdoc
val insertAction =
  messages += Message("HAL", "No. Seriously, Dave, I can't let you in.")

exec(insertAction)
```

We've left the `DBIO[Int]` type annotation off of `action`, so you'll see the specific type Slick is using.
It's not important for this discussion, but worth knowing that Slick has a number of different kinds of `DBIOAction` classes in use under the hood.

The result of the action is the number of rows inserted. However, it is often useful to return something else, such as the primary key generated for the new row. We can get this information using a method called `returning`. Before we get to that, we first need to understand where the primary key comes from.

### Primary Key Allocation

When inserting data, we need to tell the database whether or not to allocate primary keys for the new rows. It is common practice to declare auto-incrementing primary keys, allowing the database to allocate values automatically if we don't manually specify them in the SQL.

Slick allows us to allocate auto-incrementing primary keys via an option on the column definition. Recall the definition of `MessageTable` from Chapter 1, which looked like this:

```scala
class MessageTable(tag: Tag) extends Table[Message](tag, "message") {

  def id      = column[Long]("id", O.PrimaryKey, O.AutoInc)
  def sender  = column[String]("sender")
  def content = column[String]("content")

  def * = (sender, content, id).mapTo[Message]
}
```

The `O.AutoInc` option specifies that the `id` column is auto-incrementing, meaning that Slick can omit the column in the corresponding SQL:

```scala mdoc
insertAction.statements.head
```

As a convenience, in our example code we put the `id` field at the end of the case class and gave it a default value of `0L`.
This allows us to skip the field when creating new objects of type `Message`:

```scala
case class Message(
  sender:  String,
  content: String,
  id:      Long = 0L
)
```

```scala mdoc
Message("Dave", "You're off my Christmas card list.")
```

There is nothing special about our default value of `0L`---it doesn't signify anything in particular.
It is the `O.AutoInc` option that determines the behaviour of `+=`.

Sometimes we want to override the database's default auto-incrementing behaviour and specify our own primary key. Slick provides a `forceInsert` method that does just this:

```scala mdoc:silent
val forceInsertAction = messages forceInsert Message(
   "HAL",
   "I'm a computer, what would I do with a Christmas card anyway?",
   1000L)
```

Notice that the SQL generated for this action includes a manually specified ID,
and that running the action results in a record with the ID being inserted:

```scala mdoc
forceInsertAction.statements.head

exec(forceInsertAction)

exec(messages.filter(_.id === 1000L).result)
```

### Retrieving Primary Keys on Insert

When the database allocates primary keys for us it's often the case that we want get the key back after an insert.
Slick supports this via the `returning` method:

```scala mdoc
val insertDave: DBIO[Long] =
  messages returning messages.map(_.id) += Message("Dave", "Point taken.")

val pk: Long = exec(insertDave)
```

```scala mdoc:invisible
assert(pk == 1001L, "Text below expects PK of 1001L")
```

The argument to `messages returning` is a `Query` over the same table, which is why `messages.map(_.id)` makes sense here.
The query specifies what data we'd like the database to return once the insert has finished.

We can demonstrate that the return value is a primary key by looking up the record we just inserted:

```scala mdoc
exec(messages.filter(_.id === 1001L).result.headOption)
```

For convenience, we can save a few keystrokes and define an insert query that always returns the primary key:

```scala mdoc
lazy val messagesReturningId = messages returning messages.map(_.id)

exec(messagesReturningId += Message("HAL", "Humans, eh."))
```

Using `messagesReturningId` will return the `id` value, rather than the count of the number of rows inserted.

### Retrieving Rows on Insert {#retrievingRowsOnInsert}

Some databases allow us to retrieve the complete inserted record, not just the primary key.
For example, we could ask for the whole `Message` back:

```scala
exec(messages returning messages +=
  Message("Dave", "So... what do we do now?"))
```

Not all databases provide complete support for the `returning` method.
H2 only allows us to retrieve the primary key from an insert.

If we tried this with H2, we get a runtime error:

```scala mdoc:crash
exec(messages returning messages +=
  Message("Dave", "So... what do we do now?"))
```

This is a shame, but getting the primary key is often all we need.

<div class="callout callout-info">
**Profile Capabilities**

The Slick manual contains a comprehensive table of the [capabilities for each database profile][link-ref-dbs]. The ability to return complete records from an insert query is referenced as the `jdbc.returnInsertOther` capability.

The API documentation for each profile also lists the capabilities that the profile *doesn't* have. For an example, the top of the [H2 Profile Scaladoc][link-ref-h2driver] page points out several of its shortcomings.
</div>

If we want to get a complete populated `Message` back from a database without `jdbc.returnInsertOther` support, we retrieve the primary key and manually add it to the inserted record. Slick simplifies this with another method, `into`:

```scala mdoc
val messagesReturningRow =
  messages returning messages.map(_.id) into { (message, id) =>
    message.copy(id = id)
  }

val insertMessage: DBIO[Message] =
  messagesReturningRow += Message("Dave", "You're such a jerk.")

exec(insertMessage)
```

The `into` method allows us to specify a function to combine the record and the new primary key. It's perfect for emulating the `jdbc.returnInsertOther` capability, although we can use it for any post-processing we care to imagine on the inserted data.

### Inserting Specific Columns {#insertingSpecificColumns}

If our database table contains a lot of columns with default values,
it is sometimes useful to specify a subset of columns in our insert queries.
We can do this by `mapping` over a query before calling `insert`:

```scala mdoc
messages.map(_.sender).insertStatement
```

The parameter type of the `+=` method is matched to the *unpacked* type of the query:

```scala mdoc
messages.map(_.sender)
```

... so we execute this query by passing it a `String` for the `sender`:

```scala mdoc:silent:crash
exec(messages.map(_.sender) += "HAL")
```

The query fails at runtime because the `content` column is non-nullable in our schema.
No matter. We'll cover nullable columns when discussing schemas in [Chapter 5](#Modelling).


### Inserting Multiple Rows

Suppose we want to insert several `Message`s at the same time. We could just use `+=` to insert each one in turn. However, this would result in a separate query being issued to the database for each record, which could be slow for large numbers of inserts.

As an alternative, Slick supports *batch inserts*, where all the inserts are sent to the database in one go. We've seen this already in the first chapter:

```scala mdoc
val testMessages = Seq(
  Message("Dave", "Hello, HAL. Do you read me, HAL?"),
  Message("HAL",  "Affirmative, Dave. I read you."),
  Message("Dave", "Open the pod bay doors, HAL."),
  Message("HAL",  "I'm sorry, Dave. I'm afraid I can't do that.")
)

exec(messages ++= testMessages)
```

This code prepares one SQL statement and uses it for each row in the `Seq`.
In principle Slick could optimize this insert further using database-specific features.
This can result in a significant boost in performance when inserting many records.

As we saw earlier this chapter, the default return value of a single insert is the number of rows inserted. The multi-row insert above is also returning the number of rows, except this time the type is `Option[Int]`. The reason for this is that the JDBC specification permits the underlying database driver to indicate that the number of rows inserted is unknown.

Slick also provides a batch version of `messages returning...`, including the `into` method. We can use the `messagesReturningRow` query we defined last section and write:

```scala mdoc
exec(messagesReturningRow ++= testMessages)
```

### More Control over Inserts {#moreControlOverInserts}

At this point we've inserted fixed data into the database.
Sometimes you need more flexibility, including inserting data based on another query.
Slick supports this via `forceInsertQuery`.


The argument to `forceInsertQuery` is a query.  So the form is:

```scala
 insertExpression.forceInsertQuery(selectExpression)
```

Our `selectExpression` can be pretty much anything, but it needs to match the columns required by our `insertExpression`.

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
      "messages" where "sender" = 'Stanley'
                 and   "content" = 'Cut!')
~~~

That looks quite involved, but we can build it up gradually.

The tricky part of this is the `select 'Stanley', 'Cut!'` part, as there is no `FROM` clause there.
We saw an example of how to create that in [Chapter 2](#constantQueries), with `Query.apply`. For this situation it would be:

```scala mdoc
val data = Query(("Stanley", "Cut!"))
```

`data` is a constant query that returns a fixed value---a tuple of two columns. It's the equivalent of running `SELECT 'Stanley', 'Cut!';` against the database, which is one part of the query we need.

We also need to be able to test to see if the data already exists. That's straightforward:

```scala mdoc:silent
val exists =
  messages.
   filter(m => m.sender === "Stanley" && m.content === "Cut!").
   exists
```

We want to use the `data` when the row _doesn't_ exist, so combine the `data` and `exists` with `filterNot` rather than `filter`:

```scala mdoc:silent
val selectExpression = data.filterNot(_ => exists)
```

Finally, we need to apply this query with `forceInsertQuery`.
But remember the column types for the insert and select need to match up.
So we `map` on `messages` to make sure that's the case:

```scala mdoc
val forceAction =
  messages.
    map(m => m.sender -> m.content).
    forceInsertQuery(selectExpression)

exec(forceAction)

exec(forceAction)
```

The first time we run the query, the message is inserted.
The second time, no rows are affected.

In summary, `forceInsertQuery` provides a way to build-up more complicated inserts.
If you find situations beyond the power of this method,
you can always make use of Plain SQL inserts, described in [Chapter 7](#PlainSQL).


## Deleting Rows

Slick lets us delete rows using the same `Query` objects we saw in [Chapter 2](#selecting).
That is, we specify which rows to delete using the `filter` method, and then call `delete`:

```scala mdoc
val removeHal: DBIO[Int] =
  messages.filter(_.sender === "HAL").delete

exec(removeHal)
```

The return value is the number of rows affected.

The SQL generated for the action can be seen by calling `delete.statements`:

```scala mdoc
messages.filter(_.sender === "HAL").delete.statements.head
```

Note that it is an error to use `delete` in combination with `map`. We can only call `delete` on a `TableQuery`:

```scala mdoc:fail
messages.map(_.content).delete
```


## Updating Rows {#UpdatingRows}

So far we've only looked at inserting new data and deleting existing data. But what if we want to update existing data without deleting it first? Slick lets us create SQL `UPDATE` actions via the kinds of `Query` values we've been using for selecting and deleting rows.


<div class="callout callout-info">
**Restoring Data**

In the last section we removed all the rows for HAL. Before continuing with updating rows, we should put them back:

```scala mdoc
exec(messages.delete andThen (messages ++= freshTestData) andThen messages.result)
```

_Action combinators_, such as `andThen`, are the subject of the next chapter.
</div>

### Updating a Single Field

In the `Messages` we've created so far we've referred to the computer from *2001: A Space Odyssey* as "`HAL`", but the correct name is "`HAL 9000`". 
Let's fix that.

We start by creating a query to select the rows to modify, and the columns to change:

```scala mdoc
val updateQuery =
  messages.filter(_.sender === "HAL").map(_.sender)
```

We can use `update` to turn this into an action to run.
Update requires the new values for the column we want to change:

```scala mdoc
exec(updateQuery.update("HAL 9000"))
```

We can retrieve the SQL for this query by calling `updateStatment` instead of `update`:

```scala mdoc
updateQuery.updateStatement
```

Let's break down the code in the Scala expression.
By building our update query from the `messages` `TableQuery`, we specify that we want to update records in the `message` table in the database:

```scala mdoc
val messagesByHal = messages.filter(_.sender === "HAL")
```

We only want to update the `sender` column, so we use `map` to reduce the query to just that column:

```scala mdoc
val halSenderCol = messagesByHal.map(_.sender)
```

Finally we call the `update` method, which takes a parameter of the *unpacked* type (in this case `String`):

```scala mdoc
val action: DBIO[Int] = halSenderCol.update("HAL 9000")
```

Running that action would return the number of rows changed.

### Updating Multiple Fields

We can update more than one field at the same time by mapping the query to a tuple of the columns we care about...

```scala mdoc:invisible
val assurance_10167 = exec(messages.filter(_.content like "I'm sorry, Dave%").result)  
assert(assurance_10167.map(_.id) == Seq(1016L), s"Text below assumes ID 1016 exists: found $assurance_10167")
```

```scala mdoc
// 1016 is "I'm sorry, Dave...."
val query = messages.
    filter(_.id === 1016L).
    map(message => (message.sender, message.content))
```

...and then supplying the tuple values we want to used in the update:

```scala mdoc
val updateAction: DBIO[Int] =
  query.update(("HAL 9000", "Sure, Dave. Come right in."))

exec(updateAction)

exec(messages.filter(_.sender === "HAL 9000").result)
```

Again, we can see the SQL we're running using the `updateStatement` method. The returned SQL contains two `?` placeholders, one for each field as expected:

```scala mdoc
messages.
  filter(_.id === 1016L).
  map(message => (message.sender, message.content)).
  updateStatement
```

We can even use `mapTo` to use case classes as the parameter to `update`:

```scala mdoc
case class NameText(name: String, text: String)

val newValue = NameText("Dave", "Now I totally don't trust you.")

messages.
  filter(_.id === 1016L).
  map(m => (m.sender, m.content).mapTo[NameText]).
  update(newValue)
```

### Updating with a Computed Value

Let's now turn to more interesting updates. How about converting every message to be all capitals? Or adding an exclamation mark to the end of each message? Both of these queries involve expressing the desired result in terms of the current value in the database. In SQL we might write something like:

~~~ sql
update "message" set "content" = CONCAT("content", '!')
~~~

This is not currently supported by `update` in Slick, but there are ways to achieve the same result.
One such way is to use Plain SQL queries, which we cover in [Chapter 7](#PlainSQL).
Another is to perform a *client-side update* by defining a Scala function to capture the change to each row:

```scala mdoc
def exclaim(msg: Message): Message =
  msg.copy(content = msg.content + "!")
```

We can update rows by selecting the relevant data from the database, applying this function, and writing the results back individually. Note that approach can be quite inefficient for large datasets---it takes `N + 1` queries to apply an update to `N` results.

You may be tempted to write something like this:

```scala mdoc
def modify(msg: Message): DBIO[Int] =
  messages.filter(_.id === msg.id).update(exclaim(msg))

// Don't do it this way:
for {
  msg <- exec(messages.result)
} yield exec(modify(msg))
```

This will have the desired effect, but at some cost.
What we have done there is use our own `exec` method which will wait for results.
We use it to fetch all rows, and then we use it on each row to modify the row.
That's a lot of waiting.
There is also no support for transactions as we `db.run` each action separately.

A better approach is to turn our logic into a single `DBIO` action using _action combinators_.
This, together with transactions, is the topic of the next chapter.

However, for this particular example, we recommend using Plain SQL ([Chapter 7](#PlainSQL)) instead of client-side updates.


## Take Home Points

For modifying the rows in the database we have seen that:

* inserts are via a  `+=` or `++=` call on a table;

* updates are via an `update` call on a query, but are somewhat limited when you need to update using the existing row value; and

* deletes are via a  `delete` call to a query.

Auto-incrementing values are inserted by Slick, unless forced. The auto-incremented values can be returned from the insert by using `returning`.

Databases have different capabilities. The limitations of each profile is listed in the profile's Scala Doc page.


## Exercises

The code for this chapter is in the [GitHub repository][link-example] in the _chapter-03_ folder.  As with chapter 1 and 2, you can use the `run` command in SBT to execute the code against a H2 database.


<div class="callout callout-info">
**Where Did My Data Go?**

Several of the exercises in this chapter require you to delete or update  content from the database.
We've shown you above how to restore you data,
but if you want to explore and change the schema you might want to completely reset the schema.

In the example code we provide a `populate` method you can use:

``` scala
exec(populate)
```

This will drop, create, and populate the `messages` table with known values.

Populate is defined as:

```scala mdoc
import scala.concurrent.ExecutionContext.Implicits.global

def populate: DBIOAction[Option[Int], NoStream, Effect.All] =
  for {    
    // Drop table if it already exists, then create the table:
    _  <- messages.schema.drop.asTry andThen messages.schema.create
    // Add some data:
    count <- messages ++= freshTestData
  } yield count
```

We'll meet `asTry` and `andThen` in the next chapter.
</div>


### Get to the Specifics

In [Inserting Specific Columns](#insertingSpecificColumns) we looked at only inserting the sender column:

```scala mdoc:silent
messages.map(_.sender) += "HAL"
```

This failed when we tried to use it as we didn't meet the requirements of the `message` table schema.
For this to succeed we need to include `content` as well as `sender`.

Rewrite the above query to include the `content` column.

<div class="solution">
The requirements of the `messages` table is `sender` and `content` can not be null.
Given this, we can correct our query:

```scala mdoc
val senderAndContent = messages.map { m => (m.sender, m.content) }
val insertSenderContent = senderAndContent += ( ("HAL","Helllllo Dave") )
exec(insertSenderContent)
```

We have used `map` to create a query that works on the two columns we care about.
To insert using that query, we supply the two field values.

In case you're wondering, we've out the extra parentheses around the column values
to be clear it is a single value which is a tuple of two values.
</div>

### Bulk All the Inserts

Insert the conversation below between Alice and Bob, returning the messages populated with `id`s.

```scala mdoc:silent
val conversation = List(
  Message("Bob",  "Hi Alice"),
  Message("Alice","Hi Bob"),
  Message("Bob",  "Are you sure this is secure?"),
  Message("Alice","Totally, why do you ask?"),
  Message("Bob",  "Oh, nothing, just wondering."),
  Message("Alice","Ten was too many messages"),
  Message("Bob",  "I could do with a sleep"),
  Message("Alice","Let's just to to the point"),
  Message("Bob",  "Okay okay, no need to be tetchy."),
  Message("Alice","Humph!"))
```

<div class="solution">
For this we need to use a batch insert (`++=`) and `into`:

```scala mdoc
val messageRows =
  messages returning messages.map(_.id) into { (message, id) =>
    message.copy(id = id)
  }

exec(messageRows ++= conversation).foreach(println)
```
</div>

### No Apologies

Write a query to delete messages that contain "sorry".

<div class="solution">
The pattern is to fine a query to select the data, and then use it with `delete`:

```scala mdoc
messages.filter(_.content like "%sorry%").delete
```
</div>


### Update Using a For Comprehension

Rewrite the update statement below to use a for comprehension.

```scala mdoc
val rebootLoop = messages.
  filter(_.sender === "HAL").
  map(msg => (msg.sender, msg.content)).
  update(("HAL 9000", "Rebooting, please wait..."))
```

Which style do you prefer?

<div class="solution">
We've split this into a `query` and then an `update`:

```scala mdoc
val halMessages = for {
  message <- messages if message.sender === "HAL"
} yield (message.sender, message.content)

val rebootLoopUpdate = halMessages.update(("HAL 9000", "Rebooting, please wait..."))
```
</div>

### Selective Memory

Delete `HAL`s first two messages. This is a more difficult exercise.

You don't know the IDs of the messages, or the content of them.
But you do know the IDs increase. 

Hints: 

- First write a query to select the two messages. Then see if you can find a way to use it as a subquery.

- You can use `in` in a query to see if a value is in a set of values returned from a query.

<div class="solution">
We've selected HAL's message IDs, sorted by the ID, and used this query inside a filter:

```scala mdoc
val selectiveMemory =
  messages.filter{
   _.id in messages.
      filter { _.sender === "HAL" }.
      sortBy { _.id.asc }.
      map    {_.id}.
      take(2)
  }.delete

selectiveMemory.statements.head
```

</div>
