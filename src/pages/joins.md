# Joins and Aggregates {#joins}

TODO: Intro, what you're going to learn.

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

val davesMessages = for {
  message <- messages
  user    <- message.sender
  room    <- message.room
  if user.id === daveId &&
     room.id === airLockId &&
     message.roomId === room.id
} yield message
~~~

or without referring to `message`s foreign keys `sender` and `room`.

~~~ scala
val daveId:UserPK = ???
val roomId:RoomPK = ???

val altDavesMessages = for {
  message <- messages
  if message.senderId === daveId &&
     message.roomId   === airLockId
} yield message
~~~

## Explicit Joins

Which are the kind we use, more explicit.


Slick offers the following methods to join two or more tables:

  * `leftJoin`  - a left outer join
  * `rightJoin` - a right outer join
  * `innerJoin` - an inner join
  * `outerJoin` - a full outer join.

The above methods are convenience to `join` with an explicit `JoinType` parameter.
If `join` isn't supplied `JoinType` it defaults to `innnerJoin`.

An explanation of SQL joins can be found on [Wikipedia][link-wikipedia-joins].

Let's rework the implicit examples from above using explicit methods:

``` scala
      //Left outer join
      lazy val left = messages.
        leftJoin(users).
        leftJoin(rooms).
        on { case ((m, u), r)     => m.senderId === u.id && m.roomId === r.id }.
        filter { case ((m, u), r) => u.id       === daveId && r.id === airLockId }.
        map { case ((m, u), r) => m }

      //Right outer join
      lazy val right = for {
        ((msgs, usrs), rms) <- messages rightJoin users on (_.senderId === _.id) rightJoin rooms on (_._1.roomId === _.id)
        if usrs.id === daveId && rms.id === airLockId && rms.id === msgs.roomId
      } yield msgs

      //Inner join
      lazy val inner = for {
        ((msgs, usrs), rms) <- messages innerJoin users on (_.senderId === _.id) leftJoin rooms on (_._1.roomId === _.id)
        if usrs.id === daveId && rms.id === airLockId && rms.id.? === msgs.roomId
      } yield msgs



```
TODO:Brief explanation of above queries


<div class="callout callout-info">
**No Full outer Join**

At the time of writing H2 does not support full outer joins.

~~~ scala
lazy val outer = for {
  (msg, usr) ← messages outerJoin users on (_.senderId.? === _.id.?)
} yield msg -> usr
~~~
</div>

## Slick is not a DSL for SQL

- Using Slick you are expressing what you want
- Find out an "Algebra" is and describe it, if relevant.
- SQL generated depends on database
- Specific database, version, optimizer turns it into what gers run
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
     } yield u. -> r.title
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
Make sure there are no `null` columns!

<div class="solution">
Simple right?
Just replace the `leftJoin` with a rightJoin from the query above!

~~~ scala
lazy val usersRooms = for {
  (usrs,occ) ← users rightJoin occupants on (_.id === _.userId)
} yield usrs.name -> occ.roomId

~~~
</div>


## Take Home Points

The SQL produced by Slick might not be the SQL you would write.
Slick expects the database query engine to optimise the query.



