# Joins and Aggregates {#joins}

Wrangling data with [joins][link-wikipedia-joins and aggregates can be painful.  In this chapter we'll try to ease that pain by exploring:

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

That's the implicit style of query.

We could also rewrite the query to declare the join ourselves:

~~~ scala
val q = for {
  msg <- messages
  usr <- users
  if usr.id === msg.senderId
} yield (usr.name, msg.content)
~~~

Note how this time we're using `msg.senderId`, not the foreign key `sender`. This produces the same query when we joined using `sender`.

Let's look at more complex implicit query,
after reviewing the schema for this chapter, in figure 4.1.

![The database schema for this chapter.  Find this code in the _chat-schema.scala_ file of the example project on GitHub.](src/img/Schema.png)


We can retrieve all messages by Dave in the Air Lock using implicit joins:

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


### Left Outer Join

A left outer join adds an extra twist. Now we are selecting all the records from a table, and matching records from another table _if they exist_, and if not we will have `NULL` values in the query result.

For an example of from our chat schema, observe that messages can be sent privately to another user. So let's say we want a list of all the messages and who they were sent to.  Visually the left outer join is as shown in figure 4.2.

![A visualization of the left outer join example. Selecting messages and associated recipients (users). For similar diagrams, see [A Visual Explanation of SQL Joins][link-visual-joins], _Coding Horror_, 11 Oct 2007.](src/img/left-outer.png)

To implement this type of query we need to be aware of what columns are being returned, and if they can be `NULL` or not:

``` scala
val left = messages.
  leftJoin(users).on(_.toId === _.id).
  map { case (m, u) => (m.content, u.name.?) }

left.run.foreach(result => println(result))
```

We're producing a list of messages and the name of user they were sent to (if any). Note the `u.name.?` expression required to turn the potentially null result from the query into an `Option` value.

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

If you're thinking that detecting and add `.?` to a column is a bit of a pain, you'd be right.  The good news is that the situation will be much better for Slick 3.

In the meantime, if you do miss a NULL column mapping, you'll see this when the query is executed:

```
Read NULL value (null) for ResultSet
```
</div>


### Right Outer Join

```
//Right outer join
lazy val right = for {
  ((msgs, usrs), rms) <- messages rightJoin users on (_.senderId === _.id)
                                  rightJoin rooms on (_._1.roomId === _.id)
  if usrs.id === daveId &&
     rms.id === airLockId &&
     rms.id === msgs.roomId
} yield msgs


```

### Summary

Above we can see an example of each of the explicit joins.
It is worth noting we can mix join types,
we don't need to use the same type of join throughout a query.

<div class="callout callout-info">
**No Full outer Join**

At the time of writing H2 does not support full outer joins,
so has not been included above.

A simple example of a full out join would be:

``` scala
val outer = for {
  (msg, usr) <- messages outerJoin users on (_.senderId.? === _.id.?)
} yield msg -> usr
```
</div>


We can also see different ways to construct the arguments to our `on` methods,
either deconstructing the tuple using a case statement or by referencing the tuple position with an underscore method,
e.g. `_1`.

We would recommend using a case statement as it easier to read than walking the tuple.

The three examples above show a join and it's conditional grouped.
We can however construct a query but adding all joins and then having one conditional.
Let's look at an example of the left join using this method:

~~~ scala
lazy val left = messages.
  leftJoin(users).
  leftJoin(rooms).
  on { case ((m, u), r) => m.senderId === u.id && m.roomId === r.id }.
  filter { case ((m, u), r) => u.id === daveId && r.id === airLockId }.
  map { case ((m, u), r) => m }
~~~

We will see how this is incredibley useful in the next chapter when looking at composing queries.

Finally, we have shown examples of building queries using either for comprehension or maps and filters.





## Seen Any Monster Queries?

Now, let's have a look at the SQL Slick generates for each of these queries:

``` sql
-- left
select x2.x3, x2.x4, x2.x5, x2.x6, x2.x7, x2.x8, x2.x9
from
    (select x10.x11 as x4, x10.x12 as x9, x10.x13 as x6, x10.x14 as x8, x10.x15 as x7, x10.x16 as x5, x10.x17 as x3, x18.x19 as x20, x18.x21 as x22, x18.x23 as x24 from (select x25."content" as x11, x25."readBy" as x12, x25."id" as x13, x25."room" as x14, x25."to" as x15, x25."ts" as x16, x25."sender" as x17 from "message" x25) x10 left outer join (select x26."id" as x19, x26."name" as x21, x26."email" as x23 from "user" x26) x18 on x10.x17 = x18.x19) x2 left outer join (select x27."title" as x28, x27."id" as x29 from "room" x27) x30 on x2.x8 = x30.x29
where (x2.x20 = 1) and (x30.x29 = 1)

-- right

select x2.x3, x2.x4, x2.x5, x2.x6, x2.x7, x2.x8, x2.x9
from
  (select x10.x11 as x4, x10.x12 as x9, x10.x13 as x6, x10.x14 as x8, x10.x15 as x7, x10.x16 as x5, x10.x17 as x3, x18.x19 as x20, x18.x21 as x22, x18.x23 as x24 from (select x25."content" as x11, x25."readBy" as x12, x25."id" as x13, x25."room" as x14, x25."to" as x15, x25."ts" as x16, x25."sender" as x17 from "message" x25) x10 right outer join (select x26."id" as x19, x26."name" as x21, x26."email" as x23 from "user" x26) x18 on x10.x17 = x18.x19) x2 right outer join (select x27."title" as x28, x27."id" as x29 from "room" x27) x30 on x2.x8 = x30.x29
where ((x2.x20 = 1) and (x30.x29 = 1)) and (x30.x29 = x2.x8)

-- inner

select x2.x3, x2.x4, x2.x5, x2.x6, x2.x7, x2.x8, x2.x9
from
  (select x10.x11 as x4, x10.x12 as x9, x10.x13 as x6, x10.x14 as x8, x10.x15 as x7, x10.x16 as x5, x10.x17 as x3, x18.x19 as x20, x18.x21 as x22, x18.x23 as x24 from (select x25."content" as x11, x25."readBy" as x12, x25."id" as x13, x25."room" as x14, x25."to" as x15, x25."ts" as x16, x25."sender" as x17 from "message" x25) x10 inner join (select x26."id" as x19, x26."name" as x21, x26."email" as x23 from "user" x26) x18 on x10.x17 = x18.x19) x2 inner join (select x27."title" as x28, x27."id" as x29 from "room" x27) x30 on x2.x8 = x30.x29
where ((x2.x20 = 1) and (x30.x29 = 1)) and (x30.x29 = x2.x8)
```
This is suffering from more than just bracketitis, a handwritten query is going to be much nicer than this.
In the next section we will look how and when we need to worry about this and how Slick mitigates against this.

## Slick is not a DSL for SQL

These generated queries are a bit worrying,
hand writing the query is far tighter:

~~~ sql
select *
from "message" left outer join "user" on "message"."sender" = "user"."id"
               left outer join "room" on "message"."room"   = "room"."id"
where
        "user"."id" = 1 and
        "room"."id" = 1
~~~

If slick generates such verbose queries surely they aren't going to be performant?

<!-- help help, I hate this - yes I am aware I've just mangled something you wrote. It has gone from lovley bullet points to bleh -->
First, using Slick you are expressing what you want,
discover an "Algebra" for your problem and describe it.

The SQL generated depends on the database being targeted.
The database saves the day by optimizing the Slick supplied SQL.

<div class="callout callout-warn">
**Mysql**
MySQL particularly bad at this, so it doesn't so much save the day as look sheepish while trying to run the query while not making eye contact.
</div>


<!-- See DifferentDatabases.scala  in chapter 4 and see if it makes sense to include examples. -->

### What to do for queries the database can't optimise ?

If the database query optimizer can not help then it's time to look at plain SQL.

TODO: LOOK HERE http://slick.typesafe.com/doc/2.1.0/sql.html


  - different imports, no slick driver


- give examples.

- exercise rewrite inner and right as plain sql

## Zip Joins

Zip joins are equivalent to `zip` on Scala's collection,
the join being based on row number.
A simple, but nonsensical example would be to join users and rooms:

<!-- Possibly worth while looking at joining user rooms to get names rather than id from occupants
    Would be a little involved as would need to equal length lists
-->
``` scala
val zipped = for {
       (u,r) <-  users zip rooms
     } yield u.name -> r.title
```

From this slick generates:

``` sql
x2.x3, x4.x5
from (select x6."name" as x3, rownum as x7 from "user" x6) x2 inner join
     (select x8."title" as x5, rownum as x9 from "room" x8) x4 on x2.x7 = x4.x9`
```

and we get back the following:

``` pre
/------+----------\
| X3   | X5       |
+------+----------+
| Dave | Air Lock |
| HAL  | Pod      |
\------+----------/
```


## Outer Joins

If we wanted a list of users and their room id, we could use an outer join:

``` scala
lazy val outer = for {
  (usrs,occ) ← users leftJoin occupants on (_.id === _.userId)
} yield usrs.name -> occ.roomId

println("\n" + outer.list.mkString("\n"))
```

If we run this,
we'll get a `SlickException` with the following message:
`Read NULL value (null) for ResultSet column Path s2._2`.


This is due to Elena not having been assigned to any rooms.
Due to slick's current implementation not knowing that SQLs outer joins can contain nullable values,
even for non nullable columns.

To get around this Slick currently generates a `?` method on columns so you can inform Slick with columns may be null.

Using this, we can now fix our query.

``` scala
lazy val outer = for {
  (usrs,occ) ← users leftJoin occupants on (_.id === _.userId)
} yield usrs.name -> occ.roomId.?

println("\n" + outer.list.mkString("\n"))
```
We could have also used a `rightJoin` and only returned those users who had been assigned to at least one room.


## Aggregation

Lets have a quick looks at how we can use aggregation functions to return Dave's first and last message:

``` scala
lazy val firstAndLastMessage = messages.filter(_.senderId === daveId).groupBy { _ => true }.map {
  case (_, group) => (group.map(_.id).max, group.map(_.id).min)
}
```
<!-- found this on stackoverflow, should I reference it?
    //http://stackoverflow.com/questions/27049646/how-to-select-max-min-in-same-query-in-slick/27055250#27055250
-->
Notice the `groupBy { _ => true }`?
This is needed so we can use the aggregate functions `min` and `max`.
Slick will ignore this when generating the SQL.
We can see this using `selectStatement`:

``` sql
select max(x2."id"), min(x2."id") from "message" x2 where x2."sender" = 1
```

## Group By

TODO: Monster example of a join and aggregate?


### Exercises

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



