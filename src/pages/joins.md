# Joins and Aggregates {#joins}

Wrangling data with joins and aggregates can be painful.  In this chapter we'll try to ease that pain by exploring:

* different styles of join (implicit and explixit);
* different ways to join (inner, outer and zip);
* aggregate functions and grouping.


## Implicit Joins

The SQL standards recognize two styles of join: implicit and explicit.  Implicit joins have been deprecated, but they're common enough to deserve a brief investigation.

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
select u."name", m."content" from "message" m, "user" u where u."id" = m."sender"
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
} yield message
~~~

As we have foreign keys (`sender`, `room`) defined on our `message` table, we can use them in the query. Here we have reworked the same example to use the foreign keys:

~~~ scala
val daveId:Id[UserTable] = ???
val roomId:Id[RoomTable] = ???

val davesMessages = for {
  message <- messages
  user    <- message.sender
  room    <- message.room
  if user.id        === daveId &&
     room.id        === airLockId &&
     message.roomId === room.id
} yield message
~~~

Let's compare the SQL the two versions of the query generate:

Manually joining:

~~~ sql
select x2."sender", x2."content", x2."ts", x2."id", x2."to", x2."room", x2."readBy"
from "message" x2, "user" x3, "room" x4
where (((x2."sender" = x3."id") and (x2."room" = x4."id")) and (x3."id" = 1)) and
      (x4."id" = 1)
~~~

Using Slicks foreign key methods:

~~~ sql
select x2."sender", x2."content", x2."ts", x2."id", x2."to", x2."room", x2."readBy"
from "message" x2, "user" x3, "room" x4
where ((x3."id" = x2."sender") and (x4."id" = x2."room")) and
      (((x3."id" = 1) and (x4."id" = 1)) and (x2."room" = x4."id"))
~~~

Apart from some bracketitis, the queries are not far from the handwritten version.


## Explicit Joins

An explicit join is where the join type is unsurprisingly explicitly defined.
They should be the prefered type of join as the intention of the query is clear.

Slick offers the following methods to join two or more tables:

  * `innerJoin` - an inner join
  * `leftJoin`  - a left outer join
  * `rightJoin` - a right outer join
  * `outerJoin` - a full outer join.

The above are convenience methods to `join` with an explicit `JoinType` parameter.
If `join` isn't supplied `JoinType` it defaults to `innnerJoin`.

An explanation of SQL joins can be found on [Wikipedia][link-wikipedia-joins].

Let's rework the implicit examples from above using explicit methods:

``` scala
//Left outer join
lazy val left = messages.
  leftJoin(users).on(_.senderId === _.id).
  leftJoin(rooms).on{ case ((m,u),r) => m.roomId === r.id}.
  filter { case ((m, u), r) => u.id === daveId && r.id === airLockId }.
  map { case ((m, u), r) => m }

//Right outer join
lazy val right = for {
  ((msgs, usrs), rms) <- messages rightJoin users on (_.senderId === _.id)
                                  rightJoin rooms on (_._1.roomId === _.id)
  if usrs.id === daveId &&
     rms.id === airLockId &&
     rms.id === msgs.roomId
} yield msgs

//Inner join
lazy val inner = for {
  ((msgs, usrs), rms) <- messages innerJoin users on (_.senderId === _.id)
                                  innerJoin rooms on (_._1.roomId === _.id)
  if usrs.id === daveId && rms.id === airLockId && rms.id.? === msgs.roomId
} yield msgs
```

<div class="callout callout-info">
**No Full outer Join**

At the time of writing H2 does not support full outer joins,
so has not been included above.

A simple example of a full out join would be:

``` scala

//Full outer join
lazy val outer = for {
  (msg, usr) ← messages outerJoin users on (_.senderId.? === _.id.?)
} yield msg -> usr
```
</div>

Above we can see an example of each of the explicit joins.
It is worth noting we can mix join types,
we don't need to use the same type of join throughout a query.

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



