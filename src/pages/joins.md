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
List out the methods.
Re-work implicit examples using explicit.

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
