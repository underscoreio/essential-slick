# Data Modelling

Now that we can do the basics of connecting to a database, running queries, and changing data, we turn to richer models of data.

In this chapter we will:

- understand how to structure an application;
- look at alternatives to modelling rows as case classes;
- expand on our knowledge of modelling tables to introduce optional values and foreign keys; and
- use more custom types to avoid working with just low-level database values.

We'll expand chat application schema to support more than just messages through this chapter.

## Application Structure

Our examples so far have been a single monolithic application. That's now how you'd work with Slick for a more substantial project.  We'll explain how to split up an application in this section.

We've also been importing the H2 driver.  We need a driver of course, but it's useful to delay picking the driver until the code needs to be run. This will allow us to switch driver, which can be useful for testing. For example, you might use H2 for unit testing, but PostgresSQL for production purposes.

### Pattern Outline

The basic pattern we'll use is as follows:

* Isolate our schema into a trait (or a few traits) in which the Slick _profile_ is abstract.  We will often refer to this trait as "the tables".

* Create an instance of our tables using a specific profile.

* Finally, configure a `Database` to obtain a `Session` to work with the table instance.

_Profile_ is a new term for us. When we have previously written...

~~~ scala
import scala.slick.driver.H2Driver.simple._
~~~

...that is giving us H2-specific JDBC driver, which is a `JdbcProfile`, which in turn is a `RelationalProfile` provided by Slick. It means that Slick could, in principle, be used with non-JDBC-based, or indeed non-relational, databases. In other words, _profile_ is an abstraction above a specific driver.


### Example

Re-working the example from Chapter 1, we have the schema in a trait:

~~~ scala
trait Profile {
  // Place holder for a specific profile
  val profile: scala.slick.driver.JdbcProfile
}

trait Tables {
  // Self-type indicating that our tables must be mixed in with a Profile
  this: Profile =>

  // Whatever that Profile is, we import it as normal:
  import profile.simple._

  // Row and table definitions here as normal
}
~~~

We currently have a small schema and can get away with putting all the table defintions into a single trait.  However, there's nothing to stop us from splitting the schema into, say `UserTables` and `MessageTables`, and so on.  They can all be brought together with `extends` and `with`:

~~~ scala
// Bring all the components together:
class Schema(val profile: JdbcProfile) extends Tables with Profile

object Main extends App {

  // A specific schema with a particular driver:
  val schema = new Schema(scala.slick.driver.H2Driver)

  // Use the schema:
  import schema._, profile.simple._

  def db = Database.forURL("jdbc:h2:mem:chapter03", driver="org.h2.Driver")

  db.withSession {
    // Work with the database as normal here
  }
}
~~~

To work with a different database, create a different `Schema` instance and supply a different driver. The rest of the code does not need to change.

### Additional Considerations

There is a potential down-side of packaging everything into a single `Schema` and performing `import schema._`.  All your case classes, and table queries, custom methods, implicits, and other values are imported into your current namespace.

If you recognise this as a problem, it's time to split your code more finely and take care over importing just what you need.


## Representations for Rows

In Chapter 1 we introduced rows as being represented by case classes.
There are in fact three common representations used: tuples, case classes, and an experimental `HList` implementation.

### Case Classes and `<>`

To explore these different representations we'll start with comparing tuples and case classes.
For a little bit of variety, let's define a `user` table so we no longer have to store names in the `message` table.

A user will have an ID and a name. The row representation will be:

~~~ scala
final case class User(name: String, id: Long = 0L)
~~~

The schema is:

~~~ scala
final class UserTable(tag: Tag) extends Table[User](tag, "user") {
 def id = column[Long]("id", O.PrimaryKey, O.AutoInc)
 def name = column[String]("name")
 def * = (name, id) <> (User.tupled, User.unapply)
}
~~~

None of this should be a surprise, as it is essentially what we have seen in the first chapter. What we'll do now is look a little bit deeper into how rows are mapped into case classes.

`Table[T]` class requires the `*` method to be defined. This _projection_ is of type `ProvenShape[T]`. A "shape" is a description of how the data in the row is to be structured. Is it to be a case class? A tuple? A combination of these? Something else? Slick provides implicit conversions from various data types into a "shape", allowing it to be sure at compile time that what you have asked for in the projection matches the schema defined.

To explain this, let's work through an example.

If we had simply tried to define the projection as a tuple...

~~~ scala
def * = (name, id)
~~~

...the compiler would tell us:

~~~
Type mismatch
 found: (scala.slick.lifted.Column[String], scala.slick.lifted.Column[Long])
 required: scala.slick.lifted.ProvenShape[chapter03.User]
~~~

This is good. We've defined the table as a `Table[User]` so we want `User` values, and the compiler has spotted that we've not defined a default projection to supply `User`s.

How do we resolve this? The answer here is to give Slick the rules it needs to prove it can convert from the `Column` values into the shape we want, which is a case class. This is the role of the mapping function, `<>`.

The two arguments to `<>` are:

* a function from `U => R`, which converts from our unpacked row-level encoding into our preferred representation; and
* a function from `R => Option[U]`, which is going the other way.

We can supply these functions by hand if we want:

~~~ scala
def intoUser(pair: (String, Long)): User = User(pair._1, pair._2)

def fromUser(user: User): Option[(String, Long)] = Some((user.name, user.id))
~~~

...and write:

~~~ scala
def * = (name, id) <> (intoUser, fromUser)
~~~

Case classes already supply these functions via `User.tupled` and `User.unapply`, so there's no point doing this.
However it is useful to know, and comes in handy for more elaborate packaging and unpackaging of rows.
We will see this in one of the exercises in this section.


### Tuples

You've seen how Slick is able to map between a tuple of columns into case classes.
However you can use tuples directly if you want, because Slick already knows how to convert from a `Column[T]` into a `T` for a variety of `T`s.

Let's return to the compile error we had above:

~~~
Type mismatch
 found: (scala.slick.lifted.Column[String], scala.slick.lifted.Column[Long])
 required: scala.slick.lifted.ProvenShape[chapter03.User]
~~~

We fixed this by supplying a mapping to our case class. We could have fixed this error by redefining the table in terms of a tuple:

~~~ scala
type TupleUser = (String, Long)

final class UserTable(tag: Tag) extends Table[TupleUser](tag, "user") {
 def id = column[Long]("id", O.PrimaryKey, O.AutoInc)
 def name = column[String]("name")
 def * = (name, id)
}
~~~

As you can see there is little difference between the case class and the tuple implementations.

Unless you have a special reason for using tuples, or perhaps just a table with a single value, you'll probably use case classes for the advantages they give:

* we have a simple type to pass around (`User` vs. `(String, Long)`); and
* the fields have names, which improves readability.


<div class="callout callout-info">
**Expose Only What You Need**

We can hide information by excluding it from our row definition. The default projection controls what is returned, in what order, and it is driven by our row definition. You don't need to project all the rows, for example, when working with a table with legacy columns that aren't being used.
</div>



### Heterogeneous Lists

Slick's **experimental** [`HList`][link-slick-hlist] implementation is useful if you need to support tables with more than 22 columns,
such as a legacy database.

To motivate this, let's suppose our user table contains lots of columns for all sorts of information about a user:

~~~ scala
import scala.slick.collection.heterogenous.{ HList, HCons, HNil }
import scala.slick.collection.heterogenous.syntax._

final class UserTable(tag: Tag) extends Table[User](tag, "user") {
  def id           = column[Long]("id", O.PrimaryKey, O.AutoInc)
  def name         = column[String]("name")
  def age          = column[Int]("age")
  def gender       = column[Char]("gender")
  def height       = column[Float]("height_m")
  def weight       = column[Float]("weight_kg")
  def shoeSize     = column[Int]("shoe_size")
  def email        = column[String]("email_address")
  def phone        = column[String]("phone_number")
  def accepted     = column[Boolean]("terms")
  def sendNews     = column[Boolean]("newsletter")
  def street       = column[String]("street")
  def city         = column[String]("city")
  def country      = column[String]("country")
  def faveColor    = column[String]("fave_color")
  def faveFood     = column[String]("fave_food")
  def faveDrink    = column[String]("fave_drink")
  def faveTvShow   = column[String]("fave_show")
  def faveMovie    = column[String]("fave_movie")
  def faveSong     = column[String]("fave_song")
  def lastPurchase = column[String]("sku")
  def lastRating   = column[Int]("service_rating")
  def tellFriends  = column[Boolean]("recommend")
  def petName      = column[String]("pet")
  def partnerName  = column[String]("partner")

  def * = name :: age :: gender :: height :: weight :: shoeSize ::
          email :: phone :: accepted :: sendNews ::
          street :: city :: country ::
          faveColor :: faveFood :: faveDrink :: faveTvShow :: faveMovie :: faveSong ::
          lastPurchase :: lastRating :: tellFriends ::
          petName :: partnerName :: id :: HNil
}
~~~

I hope you don't have a table that looks like this, but it does happen.

You could try to model this with a case class. Scala 2.11 supports case classes with more than 22 arguments,
but it does not implement the `unapply` method we'd want to use for mapping.  Instead, in this situation,
we're using a _hetrogenous list_.

An HList has a mix of the properties of a list and a tuple.  It has an arbitrary length, just as a list,
but unlike a list, each element can be a different type, like a tuple.
As you can see from the `*` definition, an `Hlist` is a kind of shape that Slick knows about.

This `HList` projection needs to match with the definition of `User` in `Table[User]`. For that, we list the types in a type alias:

~~~ scala
type User =
  String :: Int :: Char :: Float :: Float :: Int ::
  String :: String :: Boolean :: Boolean ::
  String :: String :: String :: String :: String :: String :: String :: String :: String ::
  String :: Int :: Boolean ::
  String :: String  :: Long :: HNil
~~~

Typing this in by hand is error prone and likely to drive you crazy. There are two ways to improve on this:

- The first is to know that Slick can generate this code for you from an existing database. We'll look at
that in chatper **TODO**.  We expect you'd be needing `HList`s for legacy database structures, and in that case
code generate is the way to go.

- Second, you can improve the readability of `User` by _value clases_ to replace `String` with a more meaningful type.
We'll see this in the section on [value classes](#value-classes), later in this chapter.


Once you have an `HList`-based schema, you work with it in much the same way as you would other data representations.
To create an instance of an `HList` we use the cons operator and `HNil`:

~~~ scala
users +=
  "Dr. Dave Bowman" :: 43 :: 'M' :: 1.7f :: 74.2f :: 11 ::
  "dave@example.org" :: "+1555740122" :: true :: true ::
  "123 Some Street" :: "Any Town" :: "USA" ::
  "Black" :: "Ice Cream" :: "Coffee" :: "Sky at Night" :: "Silent Running" :: "Bicycle made for Two" ::
  "Acme Space Helmet" :: 10 :: true ::
  "HAL" :: "Betty" :: 0L :: HNil
~~~

A query will produce an `HList` based `User` instance.  To pull out fields you can use `head`, `apply`, `drop`, `fold`, and the
appropriate types from the `Hlist` will be preserved:

~~~ scala
val dave = users.first

val name: String = dave.head
val age: Int = dave.apply(1)
~~~

Accessing the `HList` by index is dangerous. If you run off the end of the list with `dave(99)`, you'll get a run-time exception.

We not recommending you use a `HList` representation, but you need to know it's there for you when dealing with nasty schemas.

<div class="callout callout-danger">
**Extra Dependencies**

Some parts of `HList` depend on Scala reflection. Modify your _build.sbt_ to include:

~~~ scala
"org.scala-lang" % "scala-reflect" % scalaVersion.value
~~~

This took one of the authors **far** to long to establish.
</div>


### Exercises

#### Turning Many Rows into Case Classes

Our `HList` example mapped a table with many columns.
It's not the only way to deal with lots of columns.

Use custom functions with `<>` and map that table into a tree of case classes.
To do this you will need to define the schema, define a `User`, insert data, and query the data.

To make this easier, we're just going to map six of the columns.
Here are the case classes to use:

~~~ scala
case class EmailContact(name: String, email: String)
case class Address(street: String, city: String, country: String)
case class User(contact: EmailContact, address: Address, id: Long = 0L)
~~~

You'll find a definition of `UserTable` that you can copy and paste in the example code in the folder _chapter-03_.

<div class="solution">
A suitable projection is:

~~~ scala
def pack(row: (String, String, String, String, String, Long)): User =
  User(
    EmailContact(row._1, row._2),
    Address(row._3, row._4, row._5),
    row._6
  )

def unpack(user: User): Option[(String, String, String, String, String, Long)] =
  Some((user.contact.name, user.contact.email,
        user.address.street, user.address.city, user.address.country,
        user.id))

def * = (name, email, street, city, country, id) <> (pack, unpack)
~~~

We can insert and query as normal:

~~~ scala
users += User(
  EmailContact("Dr. Dave Bowman", "dave@example.org"),
  Address("123 Some Street", "Any Town", "USA")
)
~~~

Executing `users.run` will produce:

~~~ scala
Vector(
  User(
    EmailContact(Dr. Dave Bowman,dave@example.org),
    Address(123 Some Street,Any Town,USA),
    1
  )
)
~~~

You can continue to select just some fields. For example `users.map(_.email).run` will produce:

~~~ scala
Vector(dave@example.org)
~~~

However, notice that if you used `users.ddl.create`, only the columns defined in the default projection were created in the H2 database.

</div>



## Table and Column Representation

Now we know how rows can be represented and mapped, we will look in more detail at the representation of the table and the columns that make up a table.
In particular we'll explore nullable columns,
foreign keys, more about primary keys, composite keys,
and options you can apply a table.

### Nullable Columns

Columns defined in SQL are nullable by default. That is, they can contain `NULL` as a value.
Slick makes columns not nullable by default, and
if you want a nullable column you model it naturally in Scala as an `Option[T]`.

Let's modify `User` to have an optional email address:

~~~ scala
case class User(name: String, email: Option[String] = None, id: Long = 0L)

class UserTable(tag: Tag) extends Table[User](tag, "user") {
  def id    = column[Long]("id", O.PrimaryKey, O.AutoInc)
  def name  = column[String]("name")
  def email = column[Option[String]]("email")

  def * = (name, email, id) <> (User.tupled, User.unapply)
}

lazy val users = TableQuery[UserTable]
lazy val insertUser = users returning users.map(_.id)
~~~

We can insert users with or without an email address:

~~~ scala
val daveId: Long = insertUser += User("Dave", Some("dave@example.org"))
val halId:  Long = insertUser += User("HAL")
~~~

Selecting those rows out produces:

~~~ scala
List(User(Dave,Some(dave@example.org),1), User(HAL,None,2))
~~~

So far, so ordinary.
What might be a surprise is how you go about selecting all rows that have no email address:

~~~ scala
// Don't do this
val none: Option[String] = None
users.filter(_.email === none).list
~~~

We have one row in the database without an email address, but the query will produce no results.
If you're familiar with SQL, you'll maybe see the problem.
This query is equivalent to:

~~~ sql
SELECT * FROM "user" WHERE "email" = NULL
~~~

You might want that to match NULL email addresses, but that's not the behaviour of SQL.
What you need instead is:

~~~ sql
SELECT * FROM "user" WHERE "email" IS NULL
~~~

In Slick that is:

~~~ scala
users.filter(_.email.isEmpty).list
// results in: List(User(HAL,None,2))
~~~

There's also `isDefined` for `IS NOT NULL`.

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

That rounds off what you need to know to model optional columns with Slick.
However, we will meet the subject again when
dealing with joins in the next chapter, and in a moment when looking at a variation of primary keys.


### Primary Keys

We've defined primary keys by using the class `O` which provides column options:

~~~ scala
def id = column[Long]("id", O.PrimaryKey, O.AutoInc)
~~~

We combine this with a class class that has a default ID,
knowing that Slick won't insert this value because the field is marked as auto incrementing:

~~~ scala
case class User(name: String, email: Option[String] = None, id: Long = 0L)
~~~

That's the style that suits us in this book, but you should be aware of alternatives.
You may find our `id: Long = 0L` default a bit arbitrary.
Perhaps you'd prefer to model the primary key as an `Option[Long]`.
It will be `None` until it is assigned, and then `Some[Long]`.

We can do that, but we need to know how to convert our non-null primary key into an optional value.
This is handled by the `?` method on the column:

~~~ scala
case class User(id: Option[Long], name: String, email: Option[String] = None)

class UserTable(tag: Tag) extends Table[User](tag, "user") {
  def id    = column[Long]("id", O.PrimaryKey, O.AutoInc)
  def name  = column[String]("name")
  def email = column[Option[String]]("email")

  def * = (id.?, name, email) <> (User.tupled, User.unapply)
}
~~~

The change is small:

* the row class, `User`, defines `id` as `Option[Long]`; and
* the projection has to convert the database non-null `id` into an `Option`, via `?`.

To see why we need this, imagine what would happen if we omitted the call to `id.?`.
The projection from (`Long`, `String`, `Option[String]`)
would not match the `Table[User]` definition, which requires `Option[Long]` in
the first position.  In fact, Slick would report:

~~~
No matching Shape found. Slick does not know how to map the given types.
~~~

Given what we know about Slick so far, this is a pretty helpful message.


### Compound Primary Keys

There is a second way to declare a column as a primary key:

~~~ scala
def id = column[Long]("id", O.AutoInc)
def pk = primaryKey("pk_id", id)
~~~

This separate step doesn't make much of a difference in this case.
It separates the column definition from the key constraint,
meaning the DDL will emit:

~~~ sql
ALTER TABLE "user" ADD CONSTRAINT "pk_id" PRIMARY KEY("id")
~~~

(As it happens, this specific example [doesn't currently work with H2 and Slick](https://github.com/slick/slick/issues/763).
The `O.AutoInc` marks the column as an H2 "IDENTIY"
column which is, implicitly, a primary key as far as H2 is concerned.)

Where `primaryKey` is more useful is when you have a compound key.
This is a key which is based on the value of two columns.

By way of a not at all contrived example,
let's add the ability for people to chat in rooms.

The room definition is straight-forward:

~~~ scala
// Regular table definition for a chat room:
case class Room(title: String, id: Long = 0L)

class RoomTable(tag: Tag) extends Table[Room](tag, "room") {
 def id    = column[Long]("id", O.PrimaryKey, O.AutoInc)
 def title = column[String]("title")
 def * = (title, id) <> (Room.tupled, Room.unapply)
}

lazy val rooms = TableQuery[RoomTable]
lazy val insertRoom = rooms returning rooms.map(_.id)
~~~

<div class="callout callout-info">
**Benefit of Case Classes**

Now we have `room` and `user` the benefit of case classes over tuples becomes apparent.
As tuples, both would have the same type signature: `(String,Long)`.
It would get error prone passing around tuples like that.
</div>


To say who is in which room, we will add a table called `occupant`.
And rather than have a sane auto-generated primary key for `occupant`, we'll
make it a compound of the user and the room:

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

The SQL generated for the `occupant` table is:

~~~ sql
CREATE TABLE "occupant" (
  "room" BIGINT NOT NULL,
  "user" BIGINT NOT NULL
)

ALTER TABLE "occupant" ADD CONSTRAINT "room_user_pk" PRIMARY KEY("room", "user")
~~~

Using the `occupant` table is no different from any other table:

~~~ scala
val daveId: Long = insertUser += User(None, "Dave", Some("dave@example.org"))
val airLockId: Long = insertRoom += Room("Air Lock")

// Put Dave in the Room:
occupants += Occupant(daveId, airLockId)
~~~

Of course, if you try to put Dave in the Air Lock twice, the database
will complain that the key has been violated.


### Foreign Keys

Foreign keys are declared in a similar manner to compound primary keys.

The method `foreignKey` takes four required parameters:
 * a name;
 * the column, or columns, that make up the foreign key;
 * the `TableQuery` that the foreign key belongs to; and
 * a function on the supplied `TableQuery[T]` taking the supplied column(s) as parameters and returning an instance of `T`.

Lets walk through this by using foreign keys to connect a `message` to a `user`.
To do this we change the definition of message to reference an `id` of a `user`:

~~~ scala
case class Message(senderId: Long, content: String, ts: DateTime, id: Long = 0L)

class MessageTable(tag: Tag) extends Table[Message](tag, "message") {
  def id       = column[Long]("id", O.PrimaryKey, O.AutoInc)
  def senderId = column[Long]("sender")
  def content  = column[String]("content")
  def ts       = column[DateTime]("ts")

  def * = (senderId, content, ts, id) <> (Message.tupled, Message.unapply)

  def sender = foreignKey("sender_fk", senderId, users)(_.id)
}
~~~

The change here is that the column for the message sender is now a `Long`,
when previously we just had a `String`.
We have also defined a method, `sender`,
which is the foreign key linking the `senderId` to a `user` `id`.

The `foreignKey` gives us two things.

First, in the DDL, if you use it, the appropriate constraint is added:

~~~ sql
ALTER TABLE "message" ADD CONSTRAINT "sender_fk"
  FOREIGN KEY("sender") REFERENCES "user"("id")
  ON UPDATE NO ACTION
  ON DELETE NO ACTION
~~~

<div class="callout callout-info">
**On Update and On Delete**

A foreign key makes certain guarantees about the data.
In the case we've looked at there must be a `sender` in the `user` table
to successfully insert a new `message`.

So what happens if something changes with the `user` row?
There are a number of [_referential actions_](http://en.wikipedia.org/wiki/Foreign_key#Referential_actions) that could be triggered.
The default is for nothing to happen, but you can change that.

Let's look at an example.
Suppose we delete a user,
and we want all the messages associated with that user to be removed.
We could do that in our application, but it's something the database can provide for us:

~~~ scala
def sender =
  foreignKey("sender_fk", senderId, users)(_.id, onDelete=ForeignKeyAction.Cascade)
~~~

Providing Slicks DDL command has been run for the table,
or the SQL `ON DELETE CASCADE` action has been manually applied to the database,
the following will remove HAL from the `users` table,
and all of the messages that HAL sent:

~~~ scala
users.filter(_.name === "HAL").delete
~~~

Slick supports `onUpdate` and `onDelete` for the five actions:

------------------------------------------------------------------
Action          Description
-----------     --------------------------------------------------
`NoAction`      The default.

`Cascade`       A change in the referenced table triggers a change in the referencing table.
                In our example, deleting a user will cause their messages to be deleted.

`Restrict`      Changes are restricted, triggered a constraint violation exception.
                In our example, you would not be allowed to delete a user who had
                posted a message.

`SetNull`       The column referencing the updated value will be set to NULL.

`SetDefault`    The default value for the referencing column will be used.
                Default values are discussion in [Table and Column Modifiers](#schema-modifiers),
                later in this chapter.
-----------     --------------------------------------------------

: Referential Actions
</div>


The second thing we get is a query which we can use in a join.
We've dedicated the [next chapter](#joins) to looking at joins in detail, but
to illustrate the foreign key usage, here's a simple join:

~~~ scala
val q = for {
  msg <- messages
  usr <- msg.sender
} yield (usr.name, msg.content)
~~~

This is equivalent the the query:

~~~ sql
SELECT u."name", m."content" FROM "message" m, "user" u WHERE u."id" = m."sender"
~~~

...and will produce:

~~~ scala
Vector(
 (Dave,Hello, HAL. Do you read me, HAL?),
 (HAL,Affirmative, Dave. I read you.),
 (Dave,Open the pod bay doors, HAL.),
 (HAL,I'm sorry, Dave. I'm afraid I can't do that.))
~~~

Notice that we modelled the `Message` row using a `Long` `sender`,
rather than a `User`:

~~~ scala
case class Message(senderId: Long, content: String, ts: DateTime, id: Long = 0L)
~~~

That's the design approach to take with Slick.
The row model should reflect the row, not the row plus a bunch of other data from different tables.
To pull data from across tables, use a query.


### Table and Column Modifiers {#schema-modifiers}

We'll round off this section by looking at modifiers for columns and tables.
These allow you to change default values or sizes for columns,
and add indexes to a table.

We have already seen examples of these,
namely `O.PrimaryKey` and `O.AutoInc`.
Column options are defined in [`ColumnOption`][link-slick-column-options],
and as you have seen are accessed via `O`.

We'll look at `Length`, `DBTYPE`, and `Default` now:

~~~ scala
case class User(name: String, avatar: Option[Array[Byte]] = None, id: Long = 0L)

class UserTable(tag: Tag) extends Table[User](tag, "user") {
  def id     = column[Long]("id", O.PrimaryKey, O.AutoInc)
  def name   = column[String]("name", O.Length(64, true), O.Default("Anonymous Coward"))
  def avatar = column[Option[Array[Byte]]]("avatar", O.DBType("BINARY(2048)"))

  def * = (name, avatar, id) <> (User.tupled, User.unapply)
}
~~~

We have modified `name` to fix the maximum length of the column, and give a default value.

`O.Default` gives a default value for rows being inserted.
Remember it's the DDL commands from `users.ddl` that instruct the database to provide this default.

`O.Length` takes one parameter you'd expect, one one you might not expect:

 * `Int` - maximum length of the column; and
 * `Boolean` - `true` to use `VARCHAR`, `false` for a SQL `CHAR`.

`O.DBType` has been used on the `avatar` column to control the exact type used by the database.


Finally, we can add an index to the table:

~~~ scala
def nameIndex = index("name_idx", name, unique=true)
~~~

The corresponding DDL statement will be:

~~~ sql
CREATE UNIQUE INDEX "name_idx" ON "user" ("name")
~~~


### Exercises

#### Filtering Optional Columns

Sometimes you want to look at all the users in the database.
Sometimes you want to only see rows matching a particular value.

Working with the optional email address for a user,
write a method that will take an optional value,
and list rows matching that value.

The method signature is:

~~~ scala
def filterByEmail(email: Option[String]) = ???
~~~

We want `filterByEmail(Some("dave@example.org")).run` to produce one row,
and `filterByEmail(None).run` to produce two rows.

<div class="solution">
We can decide on the query to run in the two cases from inside our application:

~~~ scala
def filterByEmail(email: Option[String]) =
  if (email.isEmpty) users
  else users.filter(_.email === email)
~~~
</div>


#### Inside the Option

Build on the last exercise to match rows that start with the supplied optional value.
Recall that `Column[String]` defines `startsWith`.

So this time even `filterByEmail(Some("dave@")).run` will produce one row.

<div class="solution">
As the `email` value is optional we can't simply pass it to `startsWith`.

~~~ scala
def filterByEmail(email: Option[String]) =
  email.map(e =>
    users.filter(_.email startsWith e)
  ) getOrElse users
~~~
</div>


#### Matching or Undecided

Not everyone has an email address, so perhaps when filtering it would be safer to only exclude rows that don't match our filter criteria.

Add Elena to the database...

~~~ scala
insert += User("Elena", Some("elena@example.org"))
~~~

...and modify `filterByEmail` so when we search for `Some("elena@example.org")` we only
exclude Dave, as he definitely doesn't match that address.

<div class="solution">
This problem we can represent in SQL, so we can do it with one query:

~~~ scala
def filterByEmail(email: Option[String]) =
  users.filter(u => u.email.isEmpty || u.email === email)
~~~
</div>


#### Enforcement

What happens if you try adding a message with a user id of `3`?

For example:

~~~ scala
messages += Message(3L, "Hello HAl!", DateTime.now)
~~~

<div class="solution">
We get a runtime exception as we have violated referential integrity.
There is no row in the `user` table with a primary id of `3`.
</div>


#### Model This

We're now charging for our chat service.
Outstanding payments will be stored in a table called `bill`.
The default change is $12.00, and bills are recorded against a user.
A user should only have one or zero entries in this table.
Make sure it is impossible for a user to be deleted while they have a bill to pay.

Go ahead and model this.

Hint: Remember to include your new table when creating the schema:

~~~ scala
(messages.ddl ++ users.ddl ++ bills.dll).create
~~~

Additionally, provide queries to give the full details of users:

- who do have an outstanding bill; and
- who have no outstanding bills.

Hint: Slick provides `in` for SQL's `WHERE x IN (SELECT ...)` expressions.


<div class="solution">
There are a few ways to model this table regarding constraints and defaults.
Here's one way, where the default is on the database,
and he unique primary key is simply the user's `id`:

~~~ scala
case class Bill(userId: Long, amount: BigDecimal)

class BillTable(tag: Tag) extends Table[Bill](tag, "bill") {
  def userId = column[Long]("user", O.PrimaryKey)
  def amount = column[BigDecimal]("dollars", O.Default(12.00))
  def * = (userId, amount) <> (Bill.tupled, Bill.unapply)
  def user = foreignKey("fk_bill_user", userId, users)(_.id, onDelete=ForeignKeyAction.Restrict)
}

lazy val bills = TableQuery[BillTable]
~~~

Exercise the code as follows:

~~~ scala
bills += Bill(daveId, 12.00)
println(bills.list)

// Unique index or primary key violation:
//bills += Bill(daveId, 24.00)

// Referential integrity constraint violation: "fk_bill_user:
//users.filter(_.name === "Dave").delete

// Who has a bill?
val has = for {
  b <- bills
  u <- b.user
} yield u

// Who doesn't have a bill?
val hasNot = for {
  u <- users
  if !(u.id in bills.map(_.userId))
} yield u
~~~
</div>


## Value Classes {#value-classes}

In modelling rows we are using `Long`s as primary keys.
Although that's a good choice for the database, it's not a great choice
in our application.
The problem with it is that we can make some silly mistakes:

~~~ scala
// Users:
val halId:  Long = insertUser += User("HAL")
val daveId: Long = insertUser += User("Dave")

// Buggy lookup of a sender
val id = messages.filter(_.senderId === halId).map(_.id).first

val rubbish = messages.filter(_.senderId === id)
~~~

Do you see the problem here? We've looked up a message `id`,
and then going and using it to search for senders with that `id`.
It compiles, it runs, but we can prevent these kinds of problems using Scala's type system.

Before showing how, here's another downside of using `Long` as a primary key:

~~~ scala
def lookupByUserId(id: Long) = users.filter(_.id === id)
~~~

It would be much clearer to use the types of the method, and write:

~~~ scala
def lookup(id: UserPK) = users.filter(_.id === id)
~~~

We can do that, and have the compiler help us matching up primary keys, by using [value classes][link-scala-value-classes].
A value class is a compile-time wrapper around a value. At run time, the wrapper goes away,
leaving no allocation or performance overhead in our running code.

We define value classes like this:

~~~ scala
object PKs {
  case class MessagePK(value: Long) extends AnyVal
  case class UserPK(value: Long) extends AnyVal
}
~~~

To be able to use them in our tables, we need to provide Slick with the conversion rules.
This is just the same as we've previously added for JodaTime:

~~~ scala
import PKs._
implicit val messagePKMapper = MappedColumnType.base[MessagePK, Long](_.value, MessagePK(_))
implicit val userPKMapper    = MappedColumnType.base[UserPK, Long](_.value, UserPK(_))
~~~

Recall that `MappedColumnType.base` is how we define the functions to convert between our classes (`MessagePK`, `UserPK`)
and the database values (`Long`).

We _can_ do that, but for such a mechanical piece of code,
Slick provides a macro to take care of this for us.
We only need to write...

~~~ scala
object PKs {
  import scala.slick.lifted.MappedTo
  case class MessagePK(value: Long) extends AnyVal with MappedTo[Long]
  case class UserPK(value: Long) extends AnyVal with MappedTo[Long]
}
~~~

...and the `MappedTo` macro takes care of creating the `MappedColumnType.base` implicits for us.


With our value classes and implicits in place,
we can now use them to give us type checking on our primary and therefore foreign keys:

~~~ scala
case class User(name: String, id: UserPK = UserPK(0L))

class UserTable(tag: Tag) extends Table[User](tag, "user") {
  def id   = column[UserPK]("id", O.PrimaryKey, O.AutoInc)
  def name = column[String]("name")
  def * = (name, id) <> (User.tupled, User.unapply)
}

case class Message(senderId: UserPK, content: String,ts: DateTime, id: MessagePK = MessagePK(0L))

class MessageTable(tag: Tag) extends Table[Message](tag, "message") {
  def id       = column[MessagePK]("id", O.PrimaryKey, O.AutoInc)
  def senderId = column[UserPK]("sender")
  def content  = column[String]("content")
  def ts       = column[DateTime]("ts")
  def * = (senderId, content, ts, id) <> (Message.tupled, Message.unapply)
  def sender = foreignKey("sender_fk", senderId, users)(_.id, onDelete=ForeignKeyAction.Cascade)
}
~~~

Notice how we're able to be explicit: the user `id` is a `UserPK` and the message sender is also a `UserPK`.

Now, if we try our buggy query again, the compiler catches the problem:

~~~ scala
Cannot perform option-mapped operation
     with type: (PKs.UserPK, PKs.MessagePK) => R
 for base type: (PKs.UserPK, PKs.UserPK) => Boolean
[error] val rubbish = messages.filter(_.senderId === id)
                                                 ^
~~~

The compiler is telling us it wanted to compare `UserPK` to another `UserPK`,
but found a `UserPK` and a `MessagePK`.

Values classes are a reasonable way to make your code safer and more legible.
The amount of code you need to write is small,
however for a large database it can become dull writing many such methods.
In that case, consider either generating the source code rather than writing it or by generalising our definition of a primary key, so we only need to define it once.

Rather than providing a definition for each table

~~~ scala
final case class MessagePK(value: Long) extends AnyVal with MappedTo[Long]
~~~

we can supply the table as a type parameter

~~~ scala
final case class Id[A](value: Long) extends AnyVal with MappedTo[Long]
~~~

allowing us to now define our row and tables.

~~~ scala
case class User(id: Option[Id[UserTable]], name: String, email: Option[String] = None)

class UserTable(tag: Tag) extends Table[User](tag, "user") {
  def id = column[Id[UserTable]]("id", O.AutoInc, O.PrimaryKey)
  def name = column[String]("name")
  def email = column[Option[String]]("email")

  def * = (id.?, name, email) <> (User.tupled, User.unapply)
}

lazy val users = TableQuery[UserTable]
~~~

We now get type safety without having to define the boiler plate of individual Id classes per table.


### Exercises

#### Mapping Enumerations

We can use the same trick that we've seen for `DateTime` and value classes to map enumerations.

Here's a Scala Enumeration for a user's role:

~~~ scala
object UserRole extends Enumeration {
  type UserRole = Value
  val Owner   = Value("O")
  val Regular = Value("R")
}
~~~

Modify the `user` table to include a `UserRole`.
In the database store the role as a single character.

<div class="solution">
The first step is to supply an implicit to and from the database values:

~~~ scala
object UserRole extends Enumeration {
  type UserRole = Value
  val Owner   = Value("O")
  val Regular = Value("R")
}

import UserRole._
implicit val userRoleMapper =
  MappedColumnType.base[UserRole, String](_.toString, UserRole.withName(_))
~~~

Then we can use the `UserRole` in the table definition:

~~~ scala
case class User(name: String, userRole: UserRole = Regular, id: UserPK = UserPK(0L))

class UserTable(tag: Tag) extends Table[User](tag, "user") {
  def id   = column[UserPK]("id", O.PrimaryKey, O.AutoInc)
  def name = column[String]("name")
  def role = column[UserRole]("role", O.Length(1,false))

  def * = (name, role, id) <> (User.tupled, User.unapply)
}
~~~
</div>


#### Alternative Enumerations

Modify your solution to the previous exercise to store the value in the database as an integer.

Oh, and by the way, this is a legacy system. If we see an unrecognized user role value, just
default it to a `UserRole.Regular`.

<div class="solution">
The only change to make is to the mapper, to go from a `UserRole` and `String`, to a `UserRole` and `Int`:

~~~ scala
implicit val userRoleMapper =
  MappedColumnType.base[UserRole, Int](
  _.id,
  v => UserRole.values.find(_.id == v) getOrElse Regular)
~~~
</div>

#### Boilerplate free primary keys

Modify the definition of to use type parameter definition of table primary keys, assume `User` and `Room` are already implement this way.

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
All we need to do is update the existing definition of `roomId` and `userId` from `Long` to `Id[TableName]`:

~~~ scala
case class Occupant(roomId: Id[RoomTable], userId:Id[UserTable])

class OccupantTable(tag: Tag) extends Table[Occupant](tag, "occupant") {
  def roomId = column[Id[RoomTable]]("room")
  def userId = column[Id[UserTable]]("user")

  def pk = primaryKey("room_user_pk", (roomId, userId))

  def * = (roomId, userId) <> (Occupant.tupled, Occupant.unapply)
}

lazy val occupants = TableQuery[OccupantTable]
~~~

</div>


## Sum Types

We've used case classes extensively for modelling data.
These are known as _product types_, which form one half of _algebraic data types_ (ADTs).
The other half is known as _sum types_, which we will look at now.

As an example we will add a flag to messages.
Perhaps a administrator of the chat will be able to mark messages as important, offensive, or spam.
In the database we'll store these as characters: `!`, `X`, and `$`.
We don't want to use those symbols in source code, so instead we will establish a sealed trait
and a set of case objects:

~~~ scala
sealed trait Flag
case object Important extends Flag
case object Offensive extends Flag
case object Spam extends Flag
~~~

As with other custom types, we define a mapping to the database values:

~~~ scala
implicit val flagType =
  MappedColumnType.base[Flag, Char](
    flag => flag match {
      case Important => '!'
      case Offensive => 'X'
      case Spam      => '$'
    },
    ch => ch match {
      case '!' => Important
      case 'X' => Offensive
      case '$' => Spam
    })
~~~

This is similar to the enumeration pattern from the last set of exercises.
There is a difference, though, in that sealed traits can be checked by the compiler to
ensure we have covered all the cases.  That is, is we add a new flag (`OffTopic`),
but forget to add it to our `Flag => Char` function,
the compiler will warn us that we have missed a case.
(By enabling the Scala compiler's `-Xfatal-warnings` option,
these warnings will become errors, preventing your program from compiling).

Using `Flag` is the same as any other custom type:

~~~ scala
case class Message(
  senderId: UserPK,
  content:  String,
  ts:       DateTime,
  flag:     Option[Flag] = None,
  id:       MessagePK = MessagePK(0L))

class MessageTable(tag: Tag) extends Table[Message](tag, "message") {
  def id       = column[MessagePK]("id", O.PrimaryKey, O.AutoInc)
  def senderId = column[UserPK]("sender")
  def content  = column[String]("content")
  def flag     = column[Option[Flag]]("flag")
  def ts       = column[DateTime]("ts")

  def * = (senderId, content, ts, flag, id) <> (Message.tupled, Message.unapply)

  def sender = foreignKey("sender_fk", senderId, users)(_.id, onDelete=ForeignKeyAction.Cascade)
}

lazy val messages = TableQuery[MessageTable]
~~~

And we can add a message with a flag set:

~~~ scala
messages +=
  Message(halId,  "I'm sorry, Dave. I'm afraid I can't do that.", start plusSeconds 6, Some(Important))
~~~

When we execute a query, we can express ourselves in terms of our meaningful type.
However, we need to give the compiler a little help:

~~~ scala
messages.filter(_.flag === (Important : Flag)).run
~~~

Notice the _type annotation_ added to the `Important` value.
If you find yourself writing that kind of query often, hold on until Chapter 5:
there we look at ways you can write `messages.isImportant` instead.



### Exercises

#### Custom Boolean

Messages can be high priority or low priority.
The database value for high priority messages will be: `y`, `Y`, `+`, or `high`.
For low priority messages the value will be: `n`, `N`, `-`, `lo`, or `low`.

Go ahead and model this with a sum type.

<div class="solution">
This is similar to the `Flag` example above,
except we need to handle multiple values from the database.


~~~ scala
sealed trait Priority
case object HighPriority extends Priority
case object LowPriority  extends Priority

implicit val priorityType =
  MappedColumnType.base[Priority, String](
    flag => flag match {
      case HighPriority => "y"
      case LowPriority  => "n"
    },
    str => str match {
      case "Y" | "y" | "+" | "high"         => HighPriority
      case "N" | "n" | "-" | "lo"   | "low" => LowPriority
  })
~~~

</div>



## Take Home Points


Foreign keys define a constraint, and allow you to link tables in a join.

Slick's philosophy is to keep models simple. Model rows as rows, and don't try to include values from different tables.






