# Joins and Aggregates {#joins}

Wrangling data with [joins][link-wikipedia-joins] and aggregates can be painful.  In this chapter we'll try to ease that pain by exploring:

* different styles of join (monadic and applicative);
* different ways to join (inner, outer and zip); and
* aggregate functions and grouping.

## Two Kinds of Join

There are two styles of join in Slick.
One, called _applicative_, is based on an explicit `join` method.
It's a lot like the SQL `JOIN` ... `ON` syntax.

The second, _monadic_, makes use of `flatMap` as a way to join tables.

They are not mutually exclusive.
It's often convenient to create an applica􏰀tive join, and then use it in a monadic join.

## Monadic Joins

We have seen an example of monadic joins in the previous chapter:

~~~ scala
val q = for {
  msg <- messages
  usr <- msg.sender
} yield (usr.name, msg.content)
~~~

Notice how we are using `msg.sender` which is defined as a foreign key:

``` scala
class MessageTable(tag: Tag) extends Table[Message](tag, "message") {
  def id       = column[Long]("id", O.PrimaryKey, O.AutoInc)
  def senderId = column[Long]("sender")
  def content  = column[String]("content")

  def * = (senderId, content, id) <> (Message.tupled, Message.unapply)

  def sender = foreignKey("sender_fk", senderId, users)(_.id)
}
```

We can express the same query without using a for comprehension:

~~~ scala
val q =
 messages.flatMap(msg =>
  msg.sender.map( usr => (usr.name, msg.content) )
 )
~~~

Either way, when we run the query Slick generates something like the following SQL:

``` sql
select
  u."name", m."content"
from
  "message" m, "user" u
where
  u."id" = m."sender"
```

That's the monadic style of query, using foreign key relations.

<div class="callout callout-info">
**Run the Code**

You'll find the example queries for this section in the file _joins.sql_ over at [the associated GitHub repository][link-example].

From the _chapter-05_ folder start SBT and at the SBT `>` prompt run:

~~~
runMain JoinsExample
~~~
</div>


Even if we don't have a foreign key, we can use the same style, but control the join ourselves:

~~~ scala
val q = for {
  msg <- messages
  usr <- users if usr.id === msg.senderId
} yield (usr.name, msg.content)
~~~

Note how this time we're using `msg.senderId`, not the foreign key `sender`.
This produces the same query when we joined using `sender`.

You'll see plenty of examples of this style of join.
They look straight-forward to read, and are natural to write.
The cost is that Slick has to translate the monadic expression down to something that SQL is capable of running.

## Applicative Joins

An applicative join is where the join type is explicitly defined.
In SQL this is via the `JOIN` and `ON` keywords,
which is mirrored in Slick as the `join` and `on` methods.

Slick offers the following methods to join two or more tables:

  * `join`      --- an inner join,
  * `joinLeft`  --- a left outer join,
  * `joinRight` --- a right outer join,
  * `joinFull`  --- a full outer join.

We will work through examples of these.
But as a quick taste of the syntax, here's how we can join the `messages` table to the `users` on the `senderId`:

``` scala
val q = messages join users on (_.senderId === _.id)
```

This will be a query of `(MessageTable, UserTable)`.
If we wanted to, we could be more explicit about the values used in the `on` part:

``` scala
val q = messages join users on
  ( (m: MessageTable, u: UserTable) =>  m.senderId === u.id)
```

...but it reads well without this.

Joins like this are queries which we turn in to actions the usual way:

~~~ scala
val action: DBIO[Seq[(Message, User)]] =
  q.result
~~~

In the rest of this section we'll work through a variety of more involved joins.
You may find it useful to refer to figure 5.1, which sketches the schema we're using in this chapter.

![
The database schema for this chapter.
Find this code in the _chat-schema.scala_ file of the example project on GitHub.
A _message_ can have a _sender_, which is a join to the _user_ table.
Also, a _message_ can be in a _room_, which is a join to the _room_ table.
Finally, a _user_ can be in a _room_, which is a join between _user_ and _room_ via the _occupant_ table.
](src/img/Schema.png)


### Inner Join

An inner join is where we select records from multiple tables, where those records exist (in some sense) in all tables. We'll look at a chat example where we expect messages that have a sender in the user table, and a room in the rooms table:

~~~ scala
val usersAndRooms =
  messages.
  join(users).on(_.senderId === _.id).
  join(rooms).on{case ((msg,user), room) => msg.roomId === room.id}

// usersAndRooms: slick.lifted.Query[
//  ((MessageTable, UserTable), RoomTable),
//  ((MessageTable#TableElementType, UserTable#TableElementType), RoomTable#TableElementType),
//  Seq
// ] = Rep(Join Inner)
~~~

We're joining `messages` to `users`, and `messages` to `rooms`.
We need two `join`s---if you are joining _n_ tables you'll need _n-1_ join expressions.

Notice that the second `on` method call is given a tuple of `(MessageTable,UserTable)` and `RoomTable`.
That is, it's a tuple where the first element is itself a tuple.
We're using a pattern match to make this explicit, and that's the style we prefer.
However, you may see this more concisely expressed as:

``` scala
val usersAndRooms =
  messages.
  join(users).on(_.senderId  === _.id).
  join(rooms).on(_._1.roomId === _.id)
```

Pattern matching on `((msg,user), room)` is easier for us to read than expressions like `_._1.roomId`.
However, we'll get the same effect with either version.

#### Mapping Joins

We can turn this query into an action as it stands:

~~~ scala
val action: DBIO[Seq[((Message, User), Room)]] =
  usersAndRooms.result
~~~

...but typically we will `map` the query to the type of result we want:

~~~ scala
val usersAndRooms =
  messages.
  join(users).on(_.senderId  === _.id).
  join(rooms).on{case ((msg,user), room) => msg.roomId === room.id}.
  map{case ((msg, user), room) => (msg.content, user.name, room.title)}

val action: DBIO[Seq[(String, String, String)]] =
  usersAndRooms.result

exec(action)
// res1: Seq[(String, String, String)] =
// Vector(
// (Hello, HAL. Do you read me, HAL?, Dave, Air Lock),
// (Affirmative, Dave. I read you.,   HAL,  Air Lock)
// ...
~~~

#### Filter with Joins

As joins are just queries, we can make use the combinators we know.
We've already seen that we can use the `map` combinator with `join`.
Another example would be the `filter` method.

As an example, we can use our `usersAndRooms` query and modify it to focus on a particular room.
Perhaps we want to use our join for the Air Lock room:

~~~ scala
// The query we've already seen...
val usersAndRooms =
  messages.
  join(users).on(_.senderId === _.id).
  join(rooms).on{case ((msg,user), room) => msg.roomId === room.id}

// ...modified to focus on one room:
val airLockMsgs =
  usersAndRooms.
  filter{ case (_, room) => room.title === "Air Lock" }
~~~

As with other queries, the filter become a `WHERE` clause in SQL.  Something like this:

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

It won't be exactly that query, as we describe later in [Seen Any Scary Queries?](#scary)

### Left Join

A left join (a.k.a. left outer join), adds an extra twist. Now we are selecting all the records from a table, and matching records from another table _if they exist_, and if not we will have `NULL` values in the query result.

For an example from our chat schema, observe that messages can optionally be sent privately to another user via the `toId` column:

~~~ scala
// Abbreviate table:
class MessageTable(tag: Tag) extends Table[Message](tag, "message") {
  def id       = column[Id[MessageTable]]("id", O.PrimaryKey, O.AutoInc)
  def senderId = column[Id[UserTable]]("sender")
  def content  = column[String]("content")
  def toId     = column[Option[Id[UserTable]]]("to")
  // ... etc
}
~~~

So let's say we want a list of all the messages and who they were sent to.
Visually the left outer join is as shown in figure 5.2.

![A visualization of the left outer join example. Selecting messages and associated recipients (users). For similar diagrams, see [A Visual Explanation of SQL Joins][link-visual-joins], _Coding Horror_, 11 Oct 2007.](src/img/left-outer.png)

The join would be:

``` scala
val left = messages.
  joinLeft(users).on(_.toId === _.id)
```

This query, `left`, is going to fetch messages, and also lookup the user the message was sent to.
There might not be a user, because messages could be public and not sent to anyone in particular.
In that case, the result of the join for that row will be a SQL `NULL` user.

Slick will lift that possibly null value into something much more comfortable: `Option`. The type of `left` will be:

~~~ scala
slick.lifted.Query[
  (MessageTable, Rep[Option[UserTable]]),
  (MessageTable#TableElementType, Option[User]),
  Seq]
~~~

The result is a tuple of the (message, user) pairing, but Slick has made that user part `Option[User]` for us automatically.

If we want to just pick out the message content and the recipient name, we obviously use `map` on the query:

``` scala
val left = messages.
  joinLeft(users).on(_.toId === _.id).
  map { case (m, u) => (m.content, u.map(_.name)) }
```

Because the user element is optional, we naturally extract the `name` element inside another `map`: `u.map(_.name)`.

The type of this query becomes:

``` scala
slick.lifted.Query[
  (slick.lifted.Rep[String], slick.lifted.Rep[Option[String]]),
  (String, Option[String]),
  Seq]
```

The types `String` and `Option[String]` correspond to the sender name and the recipient name.

The sample data we have in _joins.sql_ in the _chapter05_ folder contains just two private messages (between Frank and Dave).
The rest are public. So our query results are:

~~~ scala
exec(left.result).foreach(println)

// (Hello, HAL. Do you read me, HAL?,             None)
// (Affirmative, Dave. I read you.,               None)
// (Open the pod bay doors, HAL.,                 None)
// (I'm sorry, Dave. I'm afraid I can't do that., None)
// (Well, whaddya think?,                         None)
// (I'm not sure, what do you think?,             None)
// (Are you thinking what I'm thinking?,          Some(Dave))
// (Maybe,                                        Some(Frank))
```

### Right Join

In the left join we selected all the records from the left side of the join, with possibly `NULL` values from the other tables.
The right join (or right outer join) swaps this,
selecting all message from the table on the right side of the join.

We can switch the example for left join and ask for all users, what private messages have they received.
For variety we're using the for comprehension style:

``` scala
val right = for {
  (msg, user) <- messages joinRight(users) on(_.toId === _.id)
} yield (user.name, msg.map(_.content))
```

From the results this time we can see that just Dave and Frank have seen private messages:

```
exec(right.result).foreach(println)

// (Dave,  Some(Are you thinking what I'm thinking?))
// (HAL,   None)
// (Elena, None)
// (Frank, Some(Maybe))
```


### Full Outer Join

Full outer joins means either side could be `NULL`.

From our schema an example would be the title of all rooms and messages in those rooms.
Either side could be `NULL` because messages don't have to be in rooms,
and rooms don't have to have any messages.

``` scala
val outer = for {
  (room, msg) <- rooms joinFull messages on (_.id === _.roomId)
} yield (room.map(_.title), msg.map(_.content))
```

We can see this by running the query against the chapter 5 schema:

```
(Some(Air Lock),Some(Hello, HAL. Do you read me, HAL?))
(Some(Air Lock),Some(Affirmative, Dave. I read you.))
(Some(Air Lock),Some(Open the pod bay doors, HAL.))
(Some(Air Lock),Some(I'm sorry, Dave. I'm afraid I can't do that.))
(Some(Pod),Some(Well, whaddya think?))
(Some(Pod),Some(I'm not sure, what do you think?))
(Some(Pod),Some(Are you thinking what I'm thinking?))
(Some(Pod),Some(Maybe))
(Some(Crew Quarters),None)
(None,Some(I am a HAL 9000 computer.))
(None,Some(I became operational at the H.A.L. plant in Urbana, Illinois on the 12th of January 1992.))
```

Some rooms have many messages, the Crew Quarters has no messages, and `HAL` isn't in a room when he gives his final monologue.

<div class="callout callout-info">
At the time of writing H2 does not support full outer joins.
Whereas earlier versions of Slick would throw a runtime exception,
Slick 3 compiles the query into to something that will run, emulating a full outer join.
</div>

### Cross Joins

In the examples above, whenever we've used `join` we've also used an `on` to constrain the join.
This is optional.

If you omit the `on` call you end up with an implicit cross join.
That is, the result will be every row from the left table with every row from the right table.
If you have 10 rows in the first table, and 5 in the second, the cross join will produce 50 rows.

An example:

~~~ scala
val query = messages joinLeft users

// query: slick.lifted.BaseJoinQuery[
//  MessageTable, Rep[Option[UserTable]],
//  MessageTable#TableElementType,Option[User],
//  Seq,
//  MessageTable,
//  UserTable] = Rep(Join LeftOption)
~~~

## Zip Joins

Zip joins are equivalent to `zip` on a Scala collection.
Recall that the `zip` in the collections library operates on two lists and returns a list of pairs:

``` scala
val xs = List(1,2,3)

xs zip xs.drop(1)
// List[(Int, Int)] = List((1,2), (2,3))
```

Slick provides the equivalent for queries, plus two variations. Let's say we want to pair up adjacent messages into what we'll call a "conversation":

```scala
// Select message content, ordered by the date the messages were sent
val msgs = messages.sortBy(_.ts asc).map(_.content)

// Pair up adjacent messages:
val conversations = msgs zip msgs.drop(1)

exec(conversations.result).foreach(println)
```

This will turn into an inner join, producing output like:

```
(Hello, HAL. Do you read me, HAL?, Affirmative, Dave. I read you.),
(Affirmative, Dave. I read you.  , Open the pod bay doors, HAL.),
(Open the pod bay doors, HAL.    , I'm sorry, Dave. I'm afraid I can't  ↩
                                                                    do that.)
```

A second variation, `zipWith`, allows you to give a mapping function along with the join.
We can provide a function to upper-case the first part of a conversation, and lower-case the second part:

``` scala
def combiner(c1: Rep[String], c2: Rep[String]) =
  (c1.toUpperCase, c2.toLowerCase)

val query = msgs.zipWith(msgs.drop(1), combiner)
```

The final variant is `zipWithIndex`, which is as per the Scala collections method of the same name. Let's number each message:

``` scala
val query = messages.map(_.content).zipWithIndex

val action: DBIO[Seq[(String, Long)]] =
  query.result
```

For H2 the SQL `ROWNUM()` function is used to generate a number. The data from this query will start:

```
(Hello, HAL. Do you read me, HAL?, 0),
(Affirmative, Dave. I read you.,   1),
(Open the pod bay doors, HAL.,     2),
...
```


## Joins Summary

This chapter has shown examples of the two different styles of join, applicative and monadic. You can also mix these styles.

We've seen how to construct the arguments to `on` methods,
either deconstructing the tuple with pattern matching, or by referencing the tuple position with an underscore method,
e.g. `_1`. We would recommend using a case statement as it easier to read than walking the tuple.

We also explored inner and outer joins, zip joins, and cross joins.
We saw that they are queries, and can be manipulated with combinators like any other query.


## Seen Any Scary Queries? {#scary}

If you've been following along and running the example joins, you might have noticed large and unusual queries being generated.

An example is looking up the user's name and message content for each message:

~~~ scala
users.
  join(messages).
  on(_.id === _.senderId).
  map{ case (u,m) => u.name -> m.content }
~~~

The query we'd write by hand for this is:

~~~ sql
select
  "user".name, "message".content
from
  "user" inner join "message" on "user".id = "message".sender
~~~

Slick actually produces:

``` sql
select
  x2.x3, x4.x5
from
  (select x6."name" as x3, x6."id" as x7 from "user" x6) x2
inner join
  (select x8."content" as x5, x8."sender" as x9 from "message" x8) x4
on
  x2.x7 = x4.x9
```

That's not so bad, but it is a little strange. For more involved queries they can look much worse.
If Slick generates such verbose queries are they are going to be slow? Yes, sometimes they will be.

Here's the key concept: the SQL generated by Slick is fed to the database optimizer. That optimizer has far better knowledge about your database, indexes, query paths, than anything else.  It will optimize the SQL from Slick into something that works well.

Unfortunately, some optimizers don't manage this very well. Postgres does a good job. MySQL is, at the time of writing, pretty bad at this. You know the lesson here: measure, use your database tools to EXPLAIN the query plan, and adjust queries as necessary.  The ultimate adjustment of a query is to re-write it using _Plain SQL_. We will introduce Plain SQL in [Chapter 6](#PlainSQL).



## Aggregation

Aggregate functions are all about computing a single value from some set of rows. A simple example is `count`. This section looks at aggregation, and also at grouping rows, and computing values on those groups.

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

``` scala
val numRows = exec(messages.length.result)

val senders:Int = exec(messages.map(_.senderId).countDistinct.result)

val firstSent:Option[DateTime] = exec(messages.map(_.ts).min.result)
```

While `length` and `countDistinct` return an `Int`, the other functions return an `Option`. This is because there may be no rows returned by the query, meaning the is no minimum, maximum and so on.


### Grouping

You may find you use the aggregate functions with column grouping. For example, how many messages has each user sent?  Slick provides `groupBy` which will group rows by some expression. Here's an example:

``` scala
val msgPerUser =
  messages.groupBy(_.senderId).
  map { case (senderId, msgs) => senderId -> msgs.length }.
  result
```

That'll work, but it will be in terms of a user's primary key. It'd be nicer to see the user's name. We can do that using our join skills:

``` scala
val msgsPerUser =
   messages.join(users).on(_.senderId === _.id).
   groupBy { case (msg, user)  => user.name }.
   map     { case (name, group) => name -> group.length }.
   result
```

The results would be:

``` scala
Vector((Frank,2), (HAL,2), (Dave,4))
```

So what's happened here? What `groupBy` has given us is a way to place rows into groups, according to some function we supply. In this example, the function is to group rows based on the user's name. It doesn't have to be a `String`, it could be any type in the table.

When it comes to mapping, we now have the key to the group (the user's name in our case), and the corresponding group rows as a query.  Because we've joined messages and users, our group is a query of those two tables.  In this example we don't care what the query is because we're just counting the number of rows.  But sometimes we will need to know more about the query.


Let's look at a more involved example, by collecting some statistics about our messages. We want to find, for each user, how many messages they sent, and the date of their first message.  We want a result something like this:

```
Vector(
  (Frank, 2, Some(2001-02-16T20:55:00.000Z)),
  (HAL,   2, Some(2001-02-17T10:22:52.000Z)),
  (Dave,  4, Some(2001-02-16T20:55:04.000Z)))
```

We have all the aggregate functions we need to do this:

``` scala
val stats =
   messages.join(users).on(_.senderId === _.id).
   groupBy { case (msg, user) => user.name }.
   map     {
    case (name, group) =>
      (name, group.length, group.map{ case (msg, user) => msg.ts}.min)
   }
```

We've now started to create a bit of a monster query. We can simplify this, but before doing so, it may help to clarify that this query is equivalent to the following SQL:

``` sql
select
  user.name, count(1), min(message.ts)
from
  message inner join user on message.sender = user.id
group by
  user.name
```

Convince yourself the Slick and SQL queries are equivalent, by comparing:

* the `map` expression in the Slick query to the `SELECT` clause in the SQL;
* the `join` to the SQL `INNER JOIN`; and
* the `groupBy` to the SQL `GROUP` expression.

If you do that you'll see the Slick expression makes sense. But when seeing these kinds of queries in code it may help to simplify by introducing intermediate functions with meaningful names.

There are a few ways to go at simplifying this, but the lowest hanging fruit is that `min` expression inside the `map`.  The issue here is that the `group` pattern is a `Query` of `(MessageTable, UserTable)` as that's our join. That leads to us having to split it further to access the message's timestamp field.

Let's pull that part out as a method:

```scala
import scala.language.higherKinds

def timestampOf[S[_]](group: Query[(MessageTable,UserTable), ↩
                                                (Message,User), S]) =
  group.map { case (msg, user) => msg.ts }
```

What we've done here is introduced a method to work on the group query, using the knowledge of the `Query` type introduced in [The Query and TableQuery Types](#queryTypes) section of Chapter 2.

The query (`group`) is parameterized by the join, the unpacked values, and the container for the results. By container we mean something like `Seq[T]`.  We don't really care what our results go into, but we do care we're working with messages and users.

With this little piece of domain specific language in place, the query becomes:

``` scala
val nicerStats =
   messages.join(users).on(_.senderId === _.id).
   groupBy { case (msg, user)   => user.name }.
   map     { case (name, group) => (name, group.length, timestampOf(group).min) }
```

We think these small changes make code more maintainable and, quite frankly, less scary. It may be marginal in this case, but real world queries can become large. Your team mileage may vary, but if you see Slick queries that are hard to understand, try pulling the query apart into named methods.


<div class="callout callout-info">
**Group By True**

There's a `groupBy { _ => true}` trick you can use where you want to select more than one aggregate from a query.

As an example, have a go at translating this SQL into a Slick query:

``` sql
select min(ts), max(ts) from message where content like '%read%'
```

It's pretty easy to get either `min` or `max`:

``` scala
messages.filter(_.content like "%read%").map(_.ts).min
```

But you want both `min` and `max` in one query. This is where `groupBy { _ => true}` comes into play:

``` scala
messages.filter(_.content like "%read%").groupBy(_ => true).map {
  case (_, msgs) => (msgs.map(_.ts).min, msgs.map(_.ts).max)
}
```

The effect here is to group all rows into the same group! This allows us to reuse the `msgs` collection, and obtain the result we want.
</div>

#### Grouping by Multiple Columns

The result of `groupBy` doesn't need to be a single value: it can be a tuple.  This gives us access to grouping by multiple columns.

We can look at the number of messages per user per room.  Something like this:

```
Vector(
  (Air Lock, HAL,   2),
  (Air Lock, Dave,  2),
  (Pod,      Dave,  2),
  (Pod,      Frank, 2) )
```

That is, we need to group by room and then by user, and finally count the number of rows in each group:

``` scala
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
* We select just the columns we want: room, user and the number of rows.
* For fun we've thrown in a `sortBy` to get the results in room order.


## Take Home Points

Slick supports `join`, `joinLeft`, `joinRight`, `joinOuter` and a `zip` join. You can map and filter over these queries as you would other queries with Slick.  Using pattern matching on the query tuples can be more readable than accessing tuples via `._1`, `._2` and so on.

Aggregation methods, such as `length` and `sum`, produce a value from a set of rows.

Rows can be grouped based on an expression supplied to `groupBy`. The result of a grouping expression is a group key and a query defining the group. Use `map`, `filter`, `sortBy` as you would with any query in Slick.

The SQL produced by Slick might not be the SQL you would write.
Slick expects the database query engine to perform optimisation. If you find slow queries, take a look at _Plain SQL_, discussed in the next chapter.



## Exercises

### `HAVING` Many Messages

Modify the `msgsPerUser` query...


~~~ scala
val msgsPerUser =
   messages.join(users).on(_.senderId === _.id).
   groupBy { case (msg, user)  => user.name }.
   map     { case (name, group) => name -> group.length }
~~~

...to return the counts for just those users with more than 2 messages.

<div class="solution">
SQL distinguishes between `WHERE` and `HAVING`. In Slick, you just use `filter`:

~~~ scala
val msgsPerUser =
   messages.join(users).on(_.senderId === _.id).
   groupBy { case (msg, user)  => user.name }.
   map     { case (name, group) => name -> group.length }.
   filter  { case (name, count) => count > 2 }
~~~

Running this on the data in _aggregates.scala_ produces:

~~~ scala
Vector((Dave,4))
~~~
</div>


### User Rooms

In this chapter we saw this query:

~~~ scala
val outer = for {
  (usrs, occ) <- users joinLeft occupants on (_.id === _.userId)
} yield usrs.name -> occ.map(_.roomId)
~~~

It would be nicer if we could find another way to express this so it didn't show rooms users don't occupy.

<div class="solution">
A right join between users and occupants can help us here.
For a row to exist in the occupant table it must have a room:

~~~ scala
val usersRooms = for {
  (usrs,occ) <- users joinRight occupants on (_.id === _.userId)
} yield usrs.name -> occ.roomId
~~~
</div>