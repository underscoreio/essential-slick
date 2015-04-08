# Joins and Aggregates {#joins}

Into, what you're going to learn.

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

  * `leftJoin`
  * `rightJoin`
  * `innerJoin`
  * `outerJoin`

There is also `join` which by default is an `innnerJoin`, but one can supply a `JoinType`.
The above methods are niceties to join with an explicit `JoinType` parameter.

An explanation of SQL joins can be found on [Wikipedia][link-wikipedia-joins].

Let's rework the implicit examples from above using explicit methods:


``` scala

      lazy val x = for {
        ((msgs, usrs), rms) ← messages leftJoin users on (_.senderId === _.id) leftJoin rooms on (_._1.roomId === _.id)
        if usrs.id === daveId && rms.id === airLockId && rms.id.? === msgs.roomId
      } yield msgs

      lazy val y = for {
        (m1, u) ← messages leftJoin users on ( _.senderId === _.id)
        (m2, r) ← messages leftJoin rooms on ( _.roomId   === _.id)
        if m1.id === m2.id && u.id === daveId && r.id === airLockId && r.id.? === m1.roomId
      } yield m1

      lazy val z = messages.
                      leftJoin(users).
                        leftJoin(rooms).
                          on{ case ((m,u),r) =>  m.senderId === u.id && m.roomId === r.id } .
                            filter{case ((m,u),r) => u.id === daveId && r.id === airLockId} .
                              map {case ((m,u),r) => m}

```

<div class="callout callout-danger">
**Slick limitation**

Due to Slick's current implementation it does not know that SQLs outer joins can contain nullable values,
even for non nullable columns.
If you attempt to reference a column in an join column that is null Slick with throw a `SlickException`.
To get around this Slick currently generates a `?` method on columns so you can inform Slick with columns may be null.

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

Maybe mention them?

## Outer Joins

Explicit outer joins, handling null via `.?`
Examples

## Aggregation

Simple ones: min, max, sum, avg
Group By
Monster example of a join and aggregate?

## Take Home Points

The SQL produced by Slick might not be the SQL you would write.
Slick expects the database query engine to optimise the query.
