<!--
-->








Sometimes it's necessary to convert from a non-nullable column to a nullable one in a query. For example, if we're performing an outer join on two tables, it is always possible that columns in one table will contain `null` values. We will see examples of this in [Chapter 5](#joins). In these circumstances, we can convert a non-`Optional` column into an `Optional` one using the `?` operator:

~~~ scala
messages.map(_.sender.?)
// res19: scala.slick.lifted.Query[
//   scala.slick.lifted.Column[Option[String]],
//   Option[String],
//   Seq
// ] = scala.slick.lifted.WrappingQuery@38e47d45
~~~








Another possible surprise is that matching on a specific non-null value works with a `String` or an `Option[String]`:

~~~ scala
val oe: Option[String] = Some("dave@example.org")
val e:  String         = "dave@example.org"

// True:
users.filter(_.email === oe).list == users.filter(_.email === e).list
~~~

To understand what's going on here, we need to review the types involved in the query:

![Column Types in the Query](src/img/query-types.png)

Although the values being tested for are `String` and `Option[String]`,
Slick implicitly lifts these values into `Column[T]` types for comparison.
From there, Slick will compare the `Column[Option[String]]` we defined in the table
with either the `Column[String]` or `Column[Option[String]]` in the query.
This is not specific to `String` types---it is a pattern for all the optional columns.







## Counting Results: The *length* Method and Column Queries

We can create a `Column` expression representing the length of any `Query` by calling its `length` method:

~~~ scala
messages.length
// res8: scala.slick.lifted.Column[Int] =
//   Column(Apply Function count(*))
~~~

We can either use this in larger expressions or, interestingly, invoke it directly:

~~~ scala
messages.length.run
// res9: Int = 4
~~~

But how does this work? A `Column` isn't a `Query` so how can we invoke it?

Slick provides limited support for running column expressions directly against the database. We can't use all of the invoker methods described in the last section, but we can use `run` and `selectStatement`. Here's a simple example:

~~~ scala
((10 : Column[Int]) + 20).run
// res10: Int = 30
~~~

Here we create a constant `Column[Int]` of value `10`, and use the `+` method described in the [Numeric Column Methods](#NumericColumnMethods) section to create a simple SQL expression `10 + 20`. We use the `run` method to execute this against the database and retrieve the value `30`. If we use the `selectStatement` method we'll see that the database is actually doing all of the math:

~~~ scala
((10 : Column[Int]) + 20).selectStatement
// res11: String = select 10 + 20
~~~

It's this same process that allows us to call `messages.length.run`. Let's look at the SQL:

~~~ scala
messages.length.selectStatement
// res9: String =
//   select x2.x3 from (
//     select count(1) as x3 from (
//       select x4."sender" as x5, x4."content" as x6, x4."id" as x7
//       from "message" x4
//     ) x8
//   ) x2
~~~

Slick generates an overly complicated query here. There are two issues:

 1. the query contains three nested `SELECT` statements instead of one;
 2. the query counts distinct values of the tuple `(sender, content, id)`, instead of simply counting `ids`.

These issues cause varying amounts of trouble depending on the quality of the query planner in our database. PostgreSQL, for example, has an excellent query planner that will optimise the nested selects away, although your mileage may vary with other database engines.

We can help our database out by being slightly cleverer in our choice of query. For example, counting values of a single indexed primary key is considerably faster than counting entire rows:

~~~ scala
messages.map(_.id).length.selectStatement
// res10: String =
//   select x2.x3 from (
//     select count(1) as x3 from (
//       select x4."id" as x5 from "message" x4
//     ) x6
//   ) x2
~~~

When using Slick, or indeed any database library that generates SQL from a DSL, it's important to keep one eye on the performance characteristics of the queries we're generating. Knowing SQL and the query planning capabilities of the database server is as important as knowing the query DSL itself.








#### Boilerplate Free Primary Keys

Modify the definition of `Occupant` to use type parameter definition of table primary keys, assume `User` and `Room` are already implement this way.

~~~ scala
case class Occupant(roomId: Long, userId: Long)

class OccupantTable(tag: Tag) extends Table[Occupant](tag, "occupant") {
  def roomId = column[Long]("room")
  def userId = column[Long]("user")

  def pk = primaryKey("room_user_pk", (roomId, userId))

  def * = (roomId, userId) <> (Occupant.tupled, Occupant.unapply)
}

lazy val occupants = TableQuery[OccupantTable]
~~~

<div class="solution">
We need to update the existing definition of `roomId` and `userId` from `Long` to `PK[TableName]`:

~~~ scala
case class Occupant(roomId: PK[RoomTable], userId: PK[UserTable])

class OccupantTable(tag: Tag) extends Table[Occupant](tag, "occupant") {
  def roomId = column[PK[RoomTable]]("room")
  def userId = column[PK[UserTable]]("user")

  def pk = primaryKey("room_user_pk", (roomId, userId))

  def * = (roomId, userId) <> (Occupant.tupled, Occupant.unapply)
}

lazy val occupants = TableQuery[OccupantTable]
~~~

</div>




Let's look at one more table to see what a more involved query looks like. You'll probably want to refer to the schema for this chapter shown in figure 5.1.


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