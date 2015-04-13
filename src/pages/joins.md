# Joins and Aggregates {#joins}

In this chapter we'll learn about the different styles of join available to you,
including implicit, explicit,inner,outer and zip.
We'll round the chapter off with a quick look at aggregate functions and grouping.


## Implicit Joins

We have seen an example of implicit joins in the last chapter.

~~~ scala
val q = for {
  msg <- messages
  usr <- msg.sender
} yield (usr.name, msg.content)
~~~

As the name suggests an implicit join is one where we don't need
to specify the type of joins to use.

Let's look at more complex query,
after reviewing our schema:

[insert schema diagram here or possibly code sample ?]

We can retrieve all messages by Dave for a given room using implicit joins:

~~~ scala
val daveId:UserPK = ???
val roomId:RoomPK = ???

val altDavesMessages = for {
  message <- messages
  user    <- users
  if message.senderId === user.id &&
     message.roomId   === airLockId &&
     user.id          === daveId
} yield message
~~~

We can also use foreign keys defined on our tables when composing a query.
Here we have reworked the same example to use `messages`  foreign keys.

~~~ scala
val daveId:UserPK = ???
val roomId:RoomPK = ???

val davesMessages = for {
  message <- messages
  user    <- message.sender
  room    <- message.room
  if user.id === daveId &&
     room.id === airLockId &&
     message.roomId === room.id
} yield message
~~~

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

## Slick is not a DSL for SQL

- Using Slick you are expressing what you want
- Find out an "Algebra" is and describe it, if relevant.
- SQL generated depends on database
- Specific database, version, optimizer turns it into what gets run
- MySQL particularly bad at this
- use plain SQL.
- give examples.

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



