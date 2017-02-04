# Joins and Aggregates {#joins}

Wrangling data with [joins][link-wikipedia-joins] and aggregates can be painful.
In this chapter we'll try to ease that pain by exploring:

* different styles of join (monadic and applicative);

* different ways to join (inner, outer and zip); and

* aggregate functions and grouping.

## Two Kinds of Join

There are two styles of join in Slick.
One, called _applicative_, is based on an explicit `join` method.
It's a lot like the SQL `JOIN` ... `ON` syntax.

The second style of join, _monadic_,
makes use of `flatMap` as a way to join tables.

These two styles of join are not mutually exclusive.
We can mix and match them in our queries.
It's often convenient to create an applicative join
and use it in a monadic join.

## Chapter Schema

To demonstrate joins we will need at least two tables.
We'll start this chapter with `User`...

```tut:book
import slick.driver.H2Driver.api._
import scala.concurrent.ExecutionContext.Implicits.global

case class User(name: String, id: Long = 0L)

class UserTable(tag: Tag) extends Table[User](tag, "user") {
  def id    = column[Long]("id", O.PrimaryKey, O.AutoInc)
  def name  = column[String]("name")

  def * = (name, id) <> (User.tupled, User.unapply)
}

lazy val users = TableQuery[UserTable]
lazy val insertUser = users returning users.map(_.id)
```

...and `Message`:

```tut:book
final case class Message(
  senderId : Long,
  content  : String,
  id       : Long = 0L)

class MessageTable(tag: Tag) extends Table[Message](tag, "message") {
  def id       = column[Long]("id", O.PrimaryKey, O.AutoInc)
  def senderId = column[Long]("senderId")
  def content  = column[String]("content")

  def sender = foreignKey("sender_fk", senderId, users)(_.id)
  def * = (senderId, content, id) <> (Message.tupled, Message.unapply)
}

lazy val messages = TableQuery[MessageTable]
lazy val insertMessages = messages returning messages.map(_.id)
```

```tut:invisible
import scala.concurrent.{Await,Future}
import scala.concurrent.duration._

val db = Database.forConfig("chapter06")

def exec[T](action: DBIO[T]): T = Await.result(db.run(action), 2.seconds)
```

We'll populate the database with the usual movie script:

```tut:book
def freshTestData(daveId: Long, halId: Long) = Seq(
  Message(daveId, "Hello, HAL. Do you read me, HAL?"),
  Message(halId,  "Affirmative, Dave. I read you."),
  Message(daveId, "Open the pod bay doors, HAL."),
  Message(halId,  "I'm sorry, Dave. I'm afraid I can't do that.")
)

val setup = for {
  _         <- (users.schema ++ messages.schema).create
  daveId    <- insertUser += User("Dave")
  halId     <- insertUser += User("HAL")
  rowsAdded <- messages ++= freshTestData(daveId, halId)
} yield rowsAdded

exec(setup)
```

Later in this chapter we'll add more tables for more complex joins.

## Monadic Joins

We have seen an example of monadic joins in the previous chapter:

```tut:book
val q = for {
  msg <- messages
  usr <- msg.sender
} yield (usr.name, msg.content)
```

Notice how we are using `msg.sender` which is defined as a foreign key in the `MessageTable` definition.
(See [Foreign Keys](#fks) in Chapter 5 to recap this topic.)


We can express the same query without using a for comprehension:

```tut:book
val q =
  messages flatMap { msg =>
    msg.sender.map { usr =>
      (usr.name, msg.content)
    }
  }
```

Either way, when we run the query Slick generates something like the following SQL:

``` sql
select
  u."name", m."content"
from
  "message" m, "user" u
where
  u."id" = m."sender"
```

That's the monadic style of query, using foreign key relationships.

<div class="callout callout-info">
**Run the Code**

You'll find the example queries for this section in the file `joins.sql` over at [the associated GitHub repository][link-example].

From the `chapter-06` folder start SBT and at the SBT `>` prompt run:

~~~
runMain JoinsExample
~~~
</div>


Even if we don't have a foreign key, we can use the same style
and control the join ourselves:

```tut:book
val q = for {
  msg <- messages
  usr <- users if usr.id === msg.senderId
} yield (usr.name, msg.content)
```

Note how this time we're using `msg.senderId`, not the foreign key `sender`.
This produces the same query when we joined using `sender`.

You'll see plenty of examples of this style of join.
They look straight-forward to read, and are natural to write.
The cost is that Slick has to translate the monadic expression down
to something that SQL is capable of running.

## Applicative Joins

An applicative join is where we explicitly write the join in code.
In SQL this is via the `JOIN` and `ON` keywords,
which are mirrored in Slick with the following methods:

  * `join`      --- an inner join,

  * `joinLeft`  --- a left outer join,
  
  * `joinRight` --- a right outer join,

  * `joinFull`  --- a full outer join.

We will work through examples of each of these methods.
But as a quick taste of the syntax,
here's how we can join the `messages` table
to the `users` on the `senderId`:

```tut:book
val q: Query[(MessageTable, UserTable), (Message, User), Seq] =
  messages join users on (_.senderId === _.id)
```

As you can see, this code produces be a query of `(MessageTable, UserTable)`.
If we want to, we can be more explicit about the values used in the `on` part:

```tut:book
val q: Query[(MessageTable, UserTable), (Message, User), Seq] =
  messages join users on ( (m: MessageTable, u: UserTable) =>
    m.senderId === u.id
   )
```


We can also write the join condition using pattern matching:

```tut:book
val q: Query[(MessageTable, UserTable), (Message, User), Seq] =
  messages join users on { case (m, u) =>  m.senderId === u.id }
```

Joins like this form queries that we convert to actions the usual way:

```tut:book
val action: DBIO[Seq[(Message, User)]] = q.result

exec(action)
```

The end result of `Seq[(Message, User)]` is each message paired with the corresponding user.

### More Tables, Longer Joins

In the rest of this section we'll work through a variety of more involved joins.
You may find it useful to refer to figure 6.1, which sketches the schema we're using in this chapter.

![
The database schema for this chapter.
Find this code in the _chat-schema.scala_ file of the example project on GitHub.
A _message_ can have a _sender_, which is a join to the _user_ table.
Also, a _message_ can be in a _room_, which is a join to the _room_ table.
](src/img/Schema.png)

For now we will add one more table.
This is be a `Room` that a `User` can be in, giving us channels for our chat conversations:

```tut:book
case class Room(title: String, id: Long = 0L)

class RoomTable(tag: Tag) extends Table[Room](tag, "room") {
  def id    = column[Long]("id", O.PrimaryKey, O.AutoInc)
  def title = column[String]("title")
  def * = (title, id) <> (Room.tupled, Room.unapply)
}

lazy val rooms = TableQuery[RoomTable]
lazy val insertRoom = rooms returning rooms.map(_.id)
```

And we'll modify a message so it can optionally be attached to a room:

```tut:book
final case class Message(
  senderId : Long,
  content  : String,
  roomId   : Option[Long] = None,
  id       : Long = 0L)

class MessageTable(tag: Tag) extends Table[Message](tag, "message") {
  def id       = column[Long]("id", O.PrimaryKey, O.AutoInc)
  def senderId = column[Long]("senderId")
  def content  = column[String]("content")
  def roomId   = column[Option[Long]]("roomId")

  def sender = foreignKey("sender_fk", senderId, users)(_.id)
  def * = (senderId, content, roomId, id) <> (Message.tupled, Message.unapply)
}

lazy val messages = TableQuery[MessageTable]
lazy val insertMessages = messages returning messages.map(_.id)
```

We'll reset our database and populate it with some messages happening in the "Air Lock" room:

```tut:book
exec(messages.schema.drop)

val daveId = 1L
val halId  = 2L

val setup = for {

  // Create the modified and new tables:
  _ <- (messages.schema ++ rooms.schema).create

  // Create one room:
  airLockId <- insertRoom += Room("Air Lock")

  // Half the messages will be in the air lock room...
  _ <- insertMessages += Message(daveId, "Hello, HAL. Do you read me, HAL?", Some(airLockId))
  _ <- insertMessages += Message(halId, "Affirmative, Dave. I read you.",   Some(airLockId))

  // ...and half will not be in room:
  _ <- insertMessages += Message(daveId, "Open the pod bay doors, HAL.")
  _ <- insertMessages += Message(halId, "I'm sorry, Dave. I'm afraid I can't do that.")

  // See what we end up with:
  msgs <- messages.result
} yield (msgs)

exec(setup)
```

Now let's get to work and join across all these tables.

### Inner Join

An inner join selects data from multiple tables, where the rows in each table match up in some way.
Typically the matching up is by comparing primary keys.
If there are rows that don't match up, they won't appear in the join results.

Let's lookup messages that have a sender in the user table, and a room in the rooms table:

```tut:book
val usersAndRooms =
  messages.
  join(users).on(_.senderId === _.id).
  join(rooms).on{ case ((msg,user), room) => msg.roomId === room.id }
```

We're joining `messages` to `users`, and `messages` to `rooms`.
We need two `join`s---if you are joining _n_ tables you'll need _n-1_ join expressions.

Notice that we're supplying a binary function to the first call to `on`
and a pattern matching function on our second call.
Because each join results in a query of a tuple,
successive joins result in nested tuples.

Pattern matching is our preferred syntax for unpacking these tuples
because it explicitly clarifies the structure of the query.
However, you may see this more concisely expressed as a binary function:

```tut:book
val usersAndRooms =
  messages.
  join(users).on(_.senderId  === _.id).
  join(rooms).on(_._1.roomId === _.id)
```

#### Mapping Joins

We can turn this query into an action as it stands:

```tut:book
val action: DBIO[Seq[((Message, User), Room)]] =
  usersAndRooms.result
```

...but our results will contain nested tuples.
That's OK, if that's what you want.
But typically we want to `map` over the query to flatten the results and
select the columns we want.

Rather than returning the table classes, we can pick out just the information we want.
Perhaps the message, the name of the sender, and the title of the room:

```tut:book
val usersAndRooms =
  messages.
  join(users).on(_.senderId  === _.id).
  join(rooms).on { case ((msg,user), room) => msg.roomId === room.id }.
  map { case ((msg, user), room) => (msg.content, user.name, room.title) }

val action: DBIO[Seq[(String, String, String)]] =
  usersAndRooms.result

exec(action)
```

#### Filter with Joins

As joins are queries, we can transform them
using the combinators we learned in previous chapters.
We've already seen an example of the `map` combinator.
Another example would be the `filter` method.

As an example, we can use our `usersAndRooms` query and
modify it to focus on a particular room.
Perhaps we want to use our join for the Air Lock room:

```tut:book
// The query we've already seen...
val usersAndRooms =
  messages.
  join(users).on(_.senderId === _.id).
  join(rooms).on { case ((msg,user), room) => msg.roomId === room.id }

// ...modified to focus on one room:
val airLockMsgs =
  usersAndRooms.
  filter { case (_, room) => room.title === "Air Lock" }
```

As with other queries, the filter become a `WHERE` clause in SQL.
Something like this:

~~~ SQL
SELECT
  "message"."content", "user"."name", "room"."title"
FROM
  "message"
  INNER JOIN "user" ON "message"."sender" = "user"."id"
  INNER JOIN "room" ON "message"."room"   = "room"."id"
WHERE
  "room"."title" = 'Air Lock';
~~~

### Left Join

A left join (a.k.a. left outer join), adds an extra twist.
Now we are selecting _all_ the records from a table,
and matching records from another table _if they exist_.
If we find no matching record on the left,
we will end up with `NULL` values in our results.

For an example from our chat schema,
observe that messages can optionally in be a room.
Let's suppose we want a list of all the messages and the room they are sent to.
Visually the left outer join is as shown below:

![
A visualization of the left outer join example. Selecting messages and associated rooms. For similar diagrams, see [A Visual Explanation of SQL Joins][link-visual-joins], _Coding Horror_, 11 Oct 2007.
](src/img/left-outer.png)

That is, we are going to select all the data from the messages table,
plus data from the rooms table for those messages that are in a room.

The join would be:

```tut:book
val left = messages.joinLeft(rooms).on(_.roomId === _.id)
```

This query, `left`, is going to fetch messages
and look up their corresponding room from the room table.
Not all messages are in a room, so in that case the `roomId` column will be `NULL`.

Slick will lift those possibly null value into
something more comfortable: `Option`.
The full type of `left` is:

```scala
Query[
  (MessageTable, Rep[Option[RoomTable]]),
  (MessageTable#TableElementType, Option[Room]),
  Seq]
~~~

The results of this query are of type `(Message, Option[Room])`---Slick
has made the `Room` side optional for us automatically.

If we want to just pick out the message content and the room title,
we can `map` over the query:

```tut:book
val left =
  messages.
  joinLeft(rooms).on(_.roomId === _.id).
  map { case (msg, room) => (msg.content, room.map(_.title)) }
```

Because the `room` element is optional,
we naturally extract the `title` element using `Option.map`:
`room.map(_.title)`.

The type of this query then becomes:

```scala
Query[
  (Rep[String], Rep[Option[String]]),
  (String, Option[String]),
  Seq]
```

The types `String` and `Option[String]` correspond to
the message content and room title:

```tut:book
exec(left.result).foreach(println)
```

### Right Join

In the previous section, we saw that a left join selects
all the records from the left hand side of the join,
with possibly `NULL` values from the right.

Right joins (or right outer joins) reverse the situation,
selecting all records from the right side of the join,
with possibly `NULL` values from the left.

We can demonstrate this by reversing our left join example.
We'll ask for all rooms together with private messages have they received.
We'll use for comprehension syntax this time for variety:

```tut:book
val right = for {
  (msg, room) <- messages joinRight (rooms) on (_.roomId === _.id)
} yield (room.title, msg.map(_.content))
```

Let's create another room and see how the query works out:

```tut:book
exec(rooms += Room("Pod Bay"))

exec(right.result).foreach(println)
```


### Full Outer Join {#fullouterjoin}

Full outer joins mean either side can be `NULL`.

From our schema an example would be the title of all rooms and messages in those rooms.
Either side could be `NULL` because messages don't have to be in rooms,
and rooms don't have to have any messages.

```tut:book
val outer = for {
  (room, msg) <- rooms joinFull messages on (_.id === _.roomId)
} yield (room.map(_.title), msg.map(_.content))
```

The type of this query has options on either side:

```scala
Query[
  (Rep[Option[String]], Rep[Option[String]]),
  (Option[String], Option[String]),
  Seq]
```

As you can see from the results...

```tut:book
exec(outer.result).foreach(println)
```
...some rooms have many messages, some none, some messages have rooms, and some do not.

<div class="callout callout-info">
At the time of writing H2 does not support full outer joins.
Whereas earlier versions of Slick would throw a runtime exception,
Slick 3 compiles the query into to something that will run,
emulating a full outer join.
</div>

### Cross Joins

In the examples above, whenever we've used `join`
we've also used an `on` to constrain the join.
This is optional.

If we omit the `on` condition for any `join`, `joinLeft`, or `joinRight`,
we end up with a *cross join*.

Cross joins include every row from the left table
with every row from the right table.
If we have 10 rows in the first table and 5 in the second,
the cross join produces 50 rows.

An example:

```tut:book
val cross = messages joinLeft users
```


## Zip Joins

Zip joins are equivalent to `zip` on a Scala collection.
Recall that the `zip` in the collections library operates on two lists and
returns a list of pairs:

```tut:book
val xs = List(1, 2, 3)

xs zip xs.drop(1)
```

Slick provides the equivalent `zip` method for queries, plus two variations.
Let's say we want to pair up adjacent messages into what we'll call a "conversation":

```tut:book
// Select message content, ordered by id:
val msgs = messages.sortBy(_.id.asc).map(_.content)

// Pair up adjacent messages:
val conversations = msgs zip msgs.drop(1)
```

This will turn into an inner join, producing output like:

```tut:book
exec(conversations.result).foreach(println)
```

A second variation, `zipWith`, lets us
provide a mapping function along with the join.
We can provide a function to upper-case the first part of a conversation,
and lower-case the second part:

```tut:book
def combiner(c1: Rep[String], c2: Rep[String]) =
  (c1.toUpperCase, c2.toLowerCase)

val query = msgs.zipWith(msgs.drop(1), combiner)

exec(query.result).foreach(println)
```

The final variant is `zipWithIndex`,
which is as per the Scala collections method of the same name.
Let's number each message:

```tut:book
val query = messages.map(_.content).zipWithIndex

val action: DBIO[Seq[(String, Long)]] =
  query.result
```

For H2 the SQL `ROWNUM()` function is used to generate a number.
The data from this query will be:

```tut:book
exec(action).foreach(println)
```

Not all databases support zip joins.
Check for the `relational.zip` capability in the `capabilities` field
of your chosen database profile:

```tut:book
// H2 supports zip
slick.driver.H2Driver.capabilities.
  map(_.toString).
  contains("relational.zip")

// SQLite does not support zip
slick.driver.SQLiteDriver.capabilities.
  map(_.toString).
  contains("relational.zip")
```

```tut:invisible
assert(false == slick.driver.SQLiteDriver.capabilities.map(_.toString).contains("relational.zip"), "SQLLite now supports ZIP!")
assert(true  == slick.driver.H2Driver.capabilities.map(_.toString).contains("relational.zip"), "H2 no longer supports ZIP?!")
```


## Joins Summary

In this chapter we've seen examples of the two different styles of join:
applicative and monadic.
We've also mixed and matched these styles.

We've seen how to construct the arguments to `on` methods,
either with a binary join condition
or by deconstructing a tuple with pattern matching.

Each join step produces a tuple.
Using pattern matching in `map` and `filter` allows us to clearly name each part of the tuple,
especially when the tuple is deeply nested.

We've also explored inner and outer joins, zip joins, and cross joins.
We saw that each type of join is a query,
making it compatible with combinators such as `map` and `filter`
from earlier chapters.


## Seen Any Scary Queries? {#scary}

If you've been following along and running the example joins,
you may have noticed large and unusual queries being generated.
Or you may not have. Since Slick 3.1, the SQL generated by Slick has improved greatly.

However, you may find the SQL generated a little strange or involved.
If Slick generates verbose queries are they are going to be slow?

Here's the key concept: the SQL generated by Slick is fed to the database optimizer.
That optimizer has far better knowledge
about your database, indexes, query paths, than anything else.
It will optimize the SQL from Slick into something that works well.

Unfortunately, some optimizers don't manage this very well.
Postgres does a good job. MySQL is, at the time of writing, pretty bad at this.
The trick here is to watch for slow queries,
and use your database's `EXPLAIN` command to examine and debug the query plan.

Optimisations can often be achieved by rewriting monadic joins in applicative style
and judiciously adding indices to the columns involved in joins.
However, a full discussion of query optimisation is out of the scope of this book.
See your database's documentation for more information.

If all else fails, we can rewrite queries for ultimate control
using Slick's _Plain SQL_ feature.
We will look at this in [Chapter 7](#PlainSQL).


## Aggregation

Aggregate functions are all about computing a single value from some set of rows.
A simple example is `count`.
This section looks at aggregation, and also at grouping rows, and computing values on those groups.

### Functions

Slick provides a few aggregate functions, as listed in the table below.

--------------------------------------------------------------------
Method           SQL
---------------  ---------------------------------------------------
 `length`        `COUNT(1)`

 `countDistinct` `COUNT(DISTINCT column)`

 `min`           `MIN(column)`

 `max`           `MAX(column)`

 `sum`           `SUM(column)`

 `avg`           `AVG(column)` --- mean of the column values
-----------      --------------------------------------------------

: A Selection of Aggregate Functions


Using them causes no great surprises, as shown in the following examples:

```tut:book
val numRows: DBIO[Int] = messages.length.result

val numDifferentSenders: DBIO[Int] =
  messages.map(_.senderId).countDistinct.result

val firstSent: DBIO[Option[Long]] =
  messages.map(_.id).min.result
```

While `length` and `countDistinct` return an `Int`, the other functions return an `Option`.
This is because there may be no rows returned by the query, meaning the is no minimum, maximum and so on.


### Grouping

Aggregate functions are often used with column grouping.
For example, how many messages has each user sent?
That's a grouping (by user) of a aggregate (count).

#### `groupBy`

Slick provides `groupBy` which will group rows by some expression. Here's an example:

```tut:book
val msgPerUser: DBIO[Seq[(Long, Int)]] =
  messages.groupBy(_.senderId).
  map { case (senderId, msgs) => senderId -> msgs.length }.
  result
```

A `groupBy` must be followed by a `map`.
The input to the `map` will be the grouping key (`senderId`) and a query for the group.

When we run the query, it'll work, but it will be in terms of a user's primary key:

```tut:book
exec(msgPerUser)
```

#### Groups and Joins

It'd be nicer to see the user's name. We can do that using our join skills:

```tut:book
val msgsPerUser =
   messages.join(users).on(_.senderId === _.id).
   groupBy { case (msg, user)   => user.name }.
   map     { case (name, group) => name -> group.length }.
   result
```

The results would be:

```tut:book
exec(msgsPerUser).foreach(println)
```

So what's happened here?
What `groupBy` has given us is a way to place rows into groups according to some function we supply.
In this example the function is to group rows based on the user's name.
It doesn't have to be a `String`, it could be any type in the table.

When it comes to mapping, we now have the key to the group (the user's name in our case),
and the corresponding group rows _as a query_.

Because we've joined messages and users, our group is a query of those two tables.
In this example we don't care what the query is because we're just counting the number of rows.
But sometimes we will need to know more about the query.


#### More Complicated Grouping

Let's look at a more involved example by collecting some statistics about our messages.
We want to find, for each user, how many messages they sent, and the id of their first message.
We want a result something like this:

```scala
Vector(
  (HAL,   2, Some(2)),
  (Dave,  2, Some(1)))
```

We have all the aggregate functions we need to do this:

```tut:book
val stats =
   messages.join(users).on(_.senderId === _.id).
   groupBy { case (msg, user) => user.name }.
   map     {
    case (name, group) =>
      (name, group.length, group.map{ case (msg, user) => msg.id}.min)
   }
```

We've now started to create a bit of a monster query.
We can simplify this, but before doing so, it may help to clarify that this query is equivalent to the following SQL:

```sql
select
  user.name, count(1), min(message.id)
from
  message inner join user on message.sender = user.id
group by
  user.name
```

Convince yourself the Slick and SQL queries are equivalent, by comparing:

* the `map` expression in the Slick query to the `SELECT` clause in the SQL;

* the `join` to the SQL `INNER JOIN`; and

* the `groupBy` to the SQL `GROUP` expression.

If you do that you'll see the Slick expression makes sense.
But when seeing these kinds of queries in code it may help to simplify by introducing intermediate functions with meaningful names.

There are a few ways to go at simplifying this,
but the lowest hanging fruit is that `min` expression inside the `map`.
The issue here is that the `group` pattern is a `Query` of `(MessageTable, UserTable)` as that's our join.
That leads to us having to split it further to access the message's ID field.

Let's pull that part out as a method:

```tut:book
import scala.language.higherKinds

def idOf[S[_]](group: Query[(MessageTable,UserTable), (Message,User), S]) =
    group.map { case (msg, user) => msg.id }
```

What we've done here is introduced a method to work on the group query,
using the knowledge of the `Query` type introduced in [The Query and TableQuery Types](#queryTypes) section of Chapter 2.

The query (`group`) is parameterized by thee things: the join, the unpacked values, and the container for the results.
By container we mean something like `Seq[T]`.
We don't really care what our results go into, but we do care we're working with messages and users.

With this little piece of domain specific language in place, the query becomes:

```tut:book
val nicerStats =
   messages.join(users).on(_.senderId === _.id).
   groupBy { case (msg, user)   => user.name }.
   map     { case (name, group) => (name, group.length, idOf(group).min) }

exec(nicerStats.result).foreach(println)
```

We think these small changes make code more maintainable and, quite frankly, less scary.
It may be marginal in this case, but real world queries can become large.
Your team mileage may vary, but if you see Slick queries that are hard to understand,
try pulling the query apart into named methods.


<div class="callout callout-info">
**Group By True**

There's a `groupBy { _ => true}` trick you can use where you want to select more than one aggregate from a query.

As an example, have a go at translating this SQL into a Slick query:

```sql
select min(id), max(id) from message where content like '%read%'
```

It's pretty easy to get either `min` or `max`:

```tut:book
messages.filter(_.content like "%read%").map(_.id).min
```

But you want both `min` and `max` in one query. This is where `groupBy { _ => true}` comes into play:

```tut:book
messages.
 filter(_.content like "%read%").
 groupBy(_ => true).
 map {
  case (_, msgs) => (msgs.map(_.id).min, msgs.map(_.id).max)
}
```

The effect if `_ => true` here is to group all rows into the same group!
This allows us to reuse the `msgs` query, and obtain the result we want.
</div>

#### Grouping by Multiple Columns

The result of `groupBy` doesn't need to be a single value: it can be a tuple.  This gives us access to grouping by multiple columns.

We can look at the number of messages per user per room.  Something like this:

```scala
Vector(
  (Air Lock, HAL,   1),
  (Air Lock, Dave,  1),
  (Kitchen,  Frank, 3) )
```

...assuming we add a message from Frank:

```tut:book
val addFrank = for {
  kitchenId <- insertRoom += Room("Kitchen")
  frankId   <- insertUser += User("Frank")
  rowsAdded <- messages ++= Seq(
    Message(frankId, "Hello?",    Some(kitchenId)),
    Message(frankId, "Helloooo?", Some(kitchenId)),
    Message(frankId, "HELLO!?",   Some(kitchenId))
  )
} yield rowsAdded

exec(addFrank)
```

To run the report we're going to need to group by room and then by user, and finally count the number of rows in each group:

```tut:book
val msgsPerRoomPerUser =
   rooms.
   join(messages).on(_.id === _.roomId).
   join(users).on{ case ((room,msg), user) => user.id === msg.senderId }.
   groupBy { case ((room,msg), user)   => (room.title, user.name) }.
   map     { case ((room,user), group) => (room, user, group.length) }.
   sortBy  { case (room, user, group)  => room }
```

Hopefully you're now in a position where you can unpick this:

* We join on messages, room and user to be able to display the room title and user name.

* The value passed into the `groupBy` will be determined by the join.

* The result of the `groupBy` is the columns for the grouping, which is a tuple of the room title and the user's name.

* We select (`map`) just the columns we want: room, user and the number of rows.

* For fun we've thrown in a `sortBy` to get the results in room order.

Running the action produces our expected report:

```tut:book
exec(msgsPerRoomPerUser.result).foreach(println)
```


## Take Home Points

Slick supports `join`, `joinLeft`, `joinRight`, `joinOuter` and a `zip` join. You can map and filter over these queries as you would other queries with Slick.  Using pattern matching on the query tuples can be more readable than accessing tuples via `._1`, `._2` and so on.

Aggregation methods, such as `length` and `sum`, produce a value from a set of rows.

Rows can be grouped based on an expression supplied to `groupBy`. The result of a grouping expression is a group key and a query defining the group. Use `map`, `filter`, `sortBy` as you would with any query in Slick.

The SQL produced by Slick might not be the SQL you would write.
Slick expects the database query engine to perform optimisation. If you find slow queries, take a look at _Plain SQL_, discussed in the next chapter.



## Exercises

Because these exercises are all about multiple tables, take a moment to remind yourself of the schema.
You'll find this in the example code, `chatper-06`, in the source file `chat_schema.scala`.

### Name of the Sender

Each message is sent by someone.
That is, the `messages.senderId` will have a matching row via `users.id`.

Please...

- Write a monadic join to return all `Message` rows and the associated `User` record for each of them.

- Change your answer to return only the content of a message and the name of the sender.

- Modify the query to return the results in name order.

- Re-write the query as an applicative join.

These exercises will get your fingers familiar with writing joins.

<div class="solution">
These queries are all items we've covered in the text:

```tut:book
val ex1 = for {
  m <- messages
  u <- users
  if u.id === m.senderId
} yield (m, u)

val ex2 = for {
  m <- messages
  u <- users
  if u.id === m.senderId
} yield (m.content, u.name)

val ex3 = ex2.sortBy{ case (content, name) => name }

val ex4 =
  messages.
   join(users).on(_.senderId === _.id).
   map    { case (msg, usr)     => (msg.content, usr.name) }.
   sortBy { case (content,name) => name }
```
</div>

### Messages of the Sender

Write a method to fetch all the message sent by a particular user.
The signature is:

```tut:book:silent
def findByName(name: String): Query[Rep[Message], Message, Seq] = ???
```

<div class="solution">
This is a filter, a join, and a map:

```tut:book
def findByName(name: String): Query[Rep[Message], Message, Seq] = for {
  u <- users    if u.name === name
  m <- messages if m.senderId === u.id
} yield m
```

...or...

```tut:book
def findByName(name: String): Query[Rep[Message], Message, Seq] =
  users.filter(_.name === name).
  join(messages).on(_.id === _.senderId).
  map{ case (user, msg) => msg }
```
</div>


### Having Many Messages

Modify the `msgsPerUser` query...

```tut:book
val msgsPerUser =
   messages.join(users).on(_.senderId === _.id).
   groupBy { case (msg, user)  => user.name }.
   map     { case (name, group) => name -> group.length }
```

...to return the counts for just those users with more than 2 messages.

<div class="solution">
SQL distinguishes between `WHERE` and `HAVING`. In Slick you use `filter` for both:

```tut:book
val msgsPerUser =
   messages.join(users).on(_.senderId === _.id).
   groupBy { case (msg, user)  => user.name }.
   map     { case (name, group) => name -> group.length }.
   filter  { case (name, count) => count > 2 }
```

At this point in the book, only Frank has more than two messages:

```tut:book
exec(msgsPerUser.result)

// Let's check:
val frankMsgs = 
  messages.join(users).on {
    case (msg,user) => msg.senderId === user.id && user.name === "Frank" 
  }

exec(frankMsgs.result).foreach(println)
```

...although if you've been experimenting with the database, your results could be different.
</div>

### Collecting Results

A join on messages and senders will produce a row for every message.
Each row will be a tuple of the user and message:

```tut:book
users.join(messages).on(_.id === _.senderId)
// res1: slick.lifted.Query[
//  (UserTable, MessageTable),
//  (UserTable#TableElementType, MessageTable#TableElementType),
//  Seq] = Rep(Join Inner)
```

The return type is effectively type is `Seq[User, Message]`.

Sometimes you'll really want something like a `Map[User, Seq[Message]]`.

There's no built-in way to do that in Slick, but you can do it in Scala using the collections `groupBy` method.

```tut:book
val almost = Seq(
  ("HAL"  -> "Hello"),
  ("Dave" -> "How are you?"),
  ("HAL"  -> "I have terrible pain in all the diodes")
  ).groupBy{ case (name, message) => name }
```

That's close, but the values in the map are still a tuple of the name and the message.
We can go further and reduce this to:

```tut:book:silent
val correct = almost.mapValues { values =>
  values.map{ case (name, msg) => msg }
}
```
```tut:book
correct.foreach(println)
```

Go ahead and write a method to encapsulate this for a join:

```tut:book:silent
def userMessages: DBIO[Map[User, Seq[Message]]] = ???
```

<div class="solution">
You need all the code in the question and also what you know about action combinators:

```tut:book
def userMessages: DBIO[Map[User,Seq[Message]]] =
  users.join(messages).on(_.id === _.senderId).result.
  map { rows =>
    rows.groupBy{ case (user, message) => user }.
    mapValues(values => values.map{ case (name, msg) => msg })
  }

exec(userMessages).foreach(println)
```
</div>

