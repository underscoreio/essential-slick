# Joins and Aggregates {#joins}

Wrangling data with [joins][link-wikipedia-joins] and aggregates can be painful.  In this chapter we'll try to ease that pain by exploring:

* different styles of join (implicit and explicit);
* different ways to join (inner, outer and zip); and
* aggregate functions and grouping.


## Implicit Joins

The SQL standards recognize two styles of join: implicit and explicit. Implicit joins have been deprecated, but they're common enough to deserve a brief investigation.

We have seen an example of implicit joins in the last chapter:

~~~ scala
val q = for {
  msg <- messages
  usr <- msg.sender
} yield (usr.name, msg.content)
~~~

Notice how we are using `msg.sender` which is defined as a foreign key:

``` scala
def sender = foreignKey("msg_sender_fk", senderId, users)(_.id)
```

Slick generates something like the following SQL:

``` sql
select
  u."name", m."content"
from
  "message" m, "user" u
where
  u."id" = m."sender"
```

That's the implicit style of query, using foreign key relations.

<div class="callout callout-info">
**Run the Code**

You'll find the example queries for this section in the file _joins.sql_ over at [the associated GitHub repository][link-example].

From the _chapter-04_ folder, start SBT and at the SBT '>' prompt run:

~~~
runMain chapter04.JoinsExample
~~~
</div>


We can also rewrite the query to control the table relationships ourselves:

~~~ scala
val q = for {
  msg <- messages
  usr <- users
  if usr.id === msg.senderId
} yield (usr.name, msg.content)
~~~

Note how this time we're using `msg.senderId`, not the foreign key `sender`. This produces the same query when we joined using `sender`.

Let's look add one more table to see what a more involved query looks like. You'll probably want to refer to the schema for this chapter shown in figure 4.1.

![The database schema for this chapter.  Find this code in the _chat-schema.scala_ file of the example project on GitHub.](src/img/Schema.png)


We can retrieve all messages by Dave in the Air Lock, again as an implicit join:

~~~ scala
val daveId: PK[UserTable] = ???
val roomId: PK[RoomTable] = ???

val davesMessages = for {
  message <- messages
  user    <- users
  room    <- rooms
  if message.senderId === user.id &&
     message.roomId   === room.id &&
     user.id          === daveId  &&
     room.id          === airLockId
} yield (message.content, user.name, room.title)
~~~

As we have foreign keys (`sender`, `room`) defined on our `message` table, we can use them in the query. Here we have reworked the same example to use the foreign keys:

~~~ scala
val daveId: PK[UserTable] = ???
val roomId: PK[RoomTable] = ???

val davesMessages = for {
  message <- messages
  user    <- message.sender
  room    <- message.room
  if user.id        === daveId &&
     room.id        === airLockId
} yield (message.content, user.name, room.title)
~~~

Both cases will produce SQL something like this:

~~~ sql
select
  m."content", u."name", r."title"
from
  "message" m, "user" u, "room" r
where (
  (u."id" = m."sender") and
  (r."id" = m."room")
) and (
  (u."id" = 1) and
  (r."id" = 1)
)
~~~

## Explicit Joins

An explicit join is where the join type is, unsurprisingly, explicitly defined.
In SQL this is via the `JOIN` and `ON` keyword, which is mirrored in Slick as the `join` and `on` methods.

Slick offers the following methods to join two or more tables:

  * `innerJoin` or `join` --- an inner join
  * `leftJoin`  --- a left outer join
  * `rightJoin` --- a right outer join
  * `outerJoin` --- a full outer join.

The above are convenience methods to `join` with an explicit `JoinType` parameter (which defaults to `innnerJoin`).  As you can see, Slicks's explicit join syntax gives you more options for how to join tables.

As a quick taste of the syntax, we can join the `messages` table to the `users` on the `senderId`:

``` scala
val q = messages innerJoin users on (_.senderId === _.id)
```

This will be a query of `(MessageTable, UserTable)`. If we wanted to, we could be more explicit about the values used in the `on` part:

``` scala
val q = messages innerJoin users on ( (m: MessageTable, u: UserTable) => m.senderId === u.id)
```

...but it reads well without this.

In the rest of this section we'll work through a variety of more involved joins.

### Inner Join

Let's rework the implicit examples from above using explicit `innerJoin` methods. It will produce the same results as the implicit join.

An inner join is where we select records from multiple tables, where those records exist (in some sense) in all tables. For the chat example this will be messages that have a sender in the user table, and a room in the rooms table:

```scala
val inner =
  messages.
  innerJoin(users).on(_.senderId === _.id).
  innerJoin(rooms).on{ case ((msg,user), room) => msg.roomId === room.id}

val query = for {
  ((msgs, usrs), rms) <- inner
  if usrs.id === daveId && rms.id === airLockId
} yield (msgs.content, usrs.name, rms.title)

val results = query.run
```

You might prefer to inline `inner` within the `query`. That's fine, but we've separated the parts out here to discuss them. And as queries in Slick compose, this works out nicely.

Let's start with the `inner` part. We're joining `messages` to `users`, and `messages` to `rooms`. We need two `join` (if you are joining _n_ tables you'll need _n-1_ join expressions). Notice that the second `on` method call is given a tuple of `(MessageTable,UserTable)` and `RoomTable`.

We're using a pattern match to make this explicit, and that's the style we prefer.  However, you may see this more concisely expressed as:

``` scala
val inner =
  messages.
  innerJoin(users).on(_.senderId  === _.id).
  innerJoin(rooms).on(_._1.roomId === _.id)
```

Either way, when it comes to the `query` itself we're using pattern matching again to unpick the results of `inner`, and adding additional guard conditions (which will be a `WHERE` clause in SQL), and mapping to the columns we want.


### Left Join

A left join (a.k.a. left outer join), adds an extra twist. Now we are selecting all the records from a table, and matching records from another table _if they exist_, and if not we will have `NULL` values in the query result.

For an example of from our chat schema, observe that messages can optionally be sent privately to another user. So let's say we want a list of all the messages and who they were sent to.  Visually the left outer join is as shown in figure 4.2.

![A visualization of the left outer join example. Selecting messages and associated recipients (users). For similar diagrams, see [A Visual Explanation of SQL Joins][link-visual-joins], _Coding Horror_, 11 Oct 2007.](src/img/left-outer.png)

To implement this type of query we need to be aware of what columns are being returned, and if they can be `NULL` or not:

``` scala
val left = messages.
  leftJoin(users).on(_.toId === _.id).
  map { case (m, u) => (m.content, u.name.?) }

left.run.foreach(result => println(result))
```

We're producing a list of messages and the name of user they were sent to (if any). Note the `u.name.?` expression is required to turn the potentially null result from the query into an `Option` value.  You need to deal with this on a column-by-column basis.

The result of the query, using the test data in _joins.sql_ over at GitHub, is:

```
(Hello, HAL. Do you read me, HAL?,             None)
(Affirmative, Dave. I read you.,               None)
(Open the pod bay doors, HAL.,                 None)
(I'm sorry, Dave. I'm afraid I can't do that., None)
(Well, whaddya think?,                         None)
(I'm not sure, what do you think?,             None)
(Are you thinking what I'm thinking?,          Some(Dave))
(Maybe,                                        Some(Frank))
```

Only the last two are private messages, sent to Dave and Frank. The rest were public, and have no user in the `toId` column.

<div class="callout callout-info">
**NULLs in Joins**

If you're thinking that detecting null values and adding `.?` to a column is a bit of a pain, you'd be right.  The good news is that the situation will be much better for Slick 3. But in the meantime, you need to handle it for each column yourself.

There's a way to tell if you've got it wrong. Take a look at this query, which is trying to list users and the rooms they are occupying:

``` scala
val outer = for {
  (usrs, occ) <- users leftJoin occupants on (_.id === _.userId)
} yield usrs.name -> occ.roomId
```

Do you see what's wrong here? If we run this,
we'll get a `SlickException` with the following message:

`Read NULL value (null) for ResultSet column Path s2._2`.

This is due to one user (Elena) not having been assigned to any rooms.

It's a limitation in Slick 2.x. even for non nullable columns.

The fix is to manually add `.?` to the selected column:

``` scala
yield usrs.name -> occ.roomId.?
```
</div>


### Right Join

In the left join we selected all the records from one side of the join, with possibly `NULL` values from the other tables. The right join (or right outer join) reverses this.

We can switch the example for left join and ask for all users, what private messages have they received:

```
val right = for {
  (msg, user) <- messages.rightJoin(users).on(_.toId === _.id)
} yield (user.name, msg.content.?)

right.run.foreach(result => println(result))
```

From the results this time we can see that just Dave and Frank have seen private messages:

```
(Dave,  Some(Are you thinking what I'm thinking?))
(HAL,   None)
(Elena, None)
(Frank, Some(Maybe))
```


### Full Outer Join

At the time of writing H2 does not support full outer joins. But if you want to try it out with a different database, a simple example would be:

``` scala
val outer = for {
  (room, msg) <- rooms outerJoin messages on (_.id === _.roomId)
} yield room.title.? -> msg.content.?
```

That would be title of all room and messages in those rooms. Either side could be `NULL` because messages don't have to be in rooms, and rooms don't have to have any messages.

## Zip Joins

Zip joins are equivalent to `zip` on a Scala collection.  Recall that the `zip` in the collections library takes a pair of lists and returns a list of pairs:

``` scala
scala> val xs = List(1,2,3)

scala> xs zip xs.drop(1)
/// List[(Int, Int)] = List((1,2), (2,3))
```

Slick provides the equivalent for queries, plus two variations. Let's say we want to pair up adjacent messages into what we'll call a "conversation":

```
// Select messages, ordered by the date the messages were sent
val msgs = messages.sortBy(_.ts asc)

// Pair up adjacent messages:
val conversations = msgs zip msgs.drop(1)

// Select out just the contents of the first and second messages:
val results: List[(String,String)] =
  conversations.map { case (fst, snd) => fst.content -> snd.content }.list
```

This will turn into an inner join, producing output like:

```
(Hello, HAL. Do you read me, HAL?, Affirmative, Dave. I read you.),
(Affirmative, Dave. I read you.  , Open the pod bay doors, HAL.),
(Open the pod bay doors, HAL.    , I'm sorry, Dave. I'm afraid I can't do that.)
```

A second variation, `zipWith`, allows you to give a mapping function along with the join. We could have written the above as:

``` scala
def combiner(fst: MessageTable, snd: MessageTable) =
  fst.content -> snd.content

val results = msgs.zipWith(msgs.drop(1), combiner).list
```

The final variant is `zipWithIndex`, which is as per the Scala collections method of the same name. Let's number each message:

``` scala
messages.zipWithIndex.map {
  case (msg, index) => index -> msg.content
}.list
```

The data from this query will start:

```
(0,Hello, HAL. Do you read me, HAL?),
(1,Affirmative, Dave. I read you.),
(2,Open the pod bay doors, HAL.),
...
```


### Summary

We've seen examples of the different kinds of join. You can also mix join types.
If you want to left join on a couple of tables, and then right join on something else, go ahead because Slick supports that.

We can also see different ways to construct the arguments to our `on` methods,
either deconstructing the tuple with pattern matching, or by referencing the tuple position with an underscore method,
e.g. `_1`. We would recommend using a case statement as it easier to read than walking the tuple.

The examples above show a join and each time we've used an `on` to constrain the join.  This is optional.  If you omit the `on` call, you end up with an implicit cross join (every row from the left table with every row from the right table).  For example:

```scala
(messages leftJoin users).run.foreach(println)
```

Finally, we have shown examples of building queries using either for comprehension or maps and filters. You get to pick which style you prefer.


## Seen Any Scary Queries?

If you've been following along and running the example joins, you might have noticed large and unusual queries being generated.

For example:

~~~ scala
users.join(messages).on(_.id === _.senderId).map{ case (u,m) => u.name -> m.content }
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
  (select x8."content" as x5, x8."sender" as x9 from "message" x8) x4 on x2.x7 = x4.x9
```

That's not so bad, but it is a little strange. For more involved queries they can look much worse.
If Slick generates such verbose queries are they are going to be slow? Yes, sometimes they will be.

Here's the key concept: the SQL generated by Slick is fed to the database optimizer. That optimizer has far better knowledge about your database, indexes, query paths, than anything else.  It will optimize the SQL from Slick into something that works well.

Unfortunately, some optimizers don't manage this very well. Postgres does a good job. MySQL is, at the time of writing, pretty bad at this. You know the lesson here: measure, use your database tools to EXPLAIN the query plan, and adjust queries as necessary.  The ultimate adjustment of a query is to re-write it using _Plain SQL_. We will introduce Plain SQL in [chapter 6](#PlainSQL).



## Aggregation

Aggregate functions are all about computing a single value from some set of rows. A simple example is `count`. we will also look at grouping rows, and computing values on those groups.

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
val numRows: Int = messages.length.run

val numSenders: Int = messages.map(_.senderId).countDistinct.run

val firstSent: Option[DateTime] = messages.map(_.ts).min.run
```

While `length` and `countDistinct` return an `Int`, the rest of the other functions is an `Option`. This is because there may be no rows returned by the query, meaning the is no minimum, maximum and so on.


### Grouping

You may find you use the aggregate functions with column grouping. For example, how many messages has each user sent?  Slick provides `groupBy` which will group rows by some expression. Here's an example:

``` scala
val msgPerUser =
  messages.groupBy(_.senderId).
  map { case (senderId, msgs) => senderId -> msgs.length }.
  run
```

That'll work, but it will be in terms of a user's primary key. It'd be nicer to see the user's name. We can do that using our join skills:

``` scala
val msgsPerUser =
   messages.join(users).on(_.senderId === _.id).
   groupBy { case (msg, user)  => user.name }.
   map     { case (name, group) => name -> group.length }.
   run
```

The results would be:

``` scala
Vector((Frank,2), (HAL,2), (Dave,4))
```

So what's happened here? What `groupBy` has given us is a way to place rows into groups, according to some function we supply. In this example, the function is to group rows based on the user's name. It doesn't have to be a `String`, it could be any type in the table.

When it comes to mapping, we now have the key to the group (user's name in our case), and the corresponding group rows as a query.  Because we've joined messages and users, our group is a query of those two tables.  In this example we don't care what the query is because we're just counting the number of rows.  But sometimes we will need to know more about the query.

#### A More Complex Example

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

There are a few ways to go at simplifying this, but the lowest hanging fruit is that `min` expression inside the `map`.  The issue here is that the `group` pattern is a `Query` of `(MessageTable, UserTable)` as that's our join, which leads to us having to split it further to access the message's timestamp field.

Let's pull that part out as a method:

```scala
import scala.language.higherKinds

def timestampOf[S[_]](group: Query[(MessageTable,UserTable), (Message,User), S]) =
  group.map { case (msg, user) => msg.ts }
```

What we've done here is introduced a method to work on the group query.  The query is parameterized by the join, the mapped values, and the container for the results. By container we mean something like `Vector[T]` (from `run`-ing the query) or `List[T]` (if we `list` the query).  We don't really care what our results go into, but we do care we're working with messages and users.

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

* We join on messages, room and user to be able to display the room and and user name.
* The value passed into the `groupBy` will be determined by the join.
* The result of the `groupBy` is the columns for the grouping, which is a tuple of the room title and the user's name.
* We select just the columns we want: room, user and the number of rows
* For fun we've thrown in a `sortBy` to get the results in room order.


### Exercises


TODO: Exercise idea: HAVING a lot of msgs.  modify msgsPerUser to return the counts for just those uses with more than 2 messages. (Slick doesn't distinguish WHERE and HAVING, so just filter as normal).


#### User rooms

Return a list of users names and the rooms they belong to using an explicit join.
Make sure there are no `null` columns in the result set!

<div class="solution">
Simple right?
Just replace the `leftJoin` with a rightJoin from the query above!

~~~ scala
lazy val usersRooms = for {
  (usrs,occ) <- users rightJoin occupants on (_.id === _.userId)
} yield usrs.name -> occ.roomId

~~~
</div>


## Take Home Points

The SQL produced by Slick might not be the SQL you would write.
Slick expects the database query engine to optimise the query.



