# Data modeling

We can now manipulate our data,
let's look at how we can provider a richer model to work with.
We'll expand chat application schema to support more than just messages through the chapter.


In this chapter we will:

- look at alternatives to modelling rows as case classes,
- expand on our knowledge of modelling tables; and
- use custom types & mapping to provide richer.


## Rows

In chapter 1 we introduced rows as being represented by case classes.
There are in fact 3 representations we can use, tuples, case classes and  an experimental `HList`s.
We'll look at the first 2 and what differences there are between them.

Let's define a `user` so we no longer have to store their names in the `message` table.
A user will have an id and a name.

~~~ scala
  type  TupleUser = (Long,String)

  final case class CaseUser(id:Long,name:String)
~~~

As you can see there is little difference between the two implementations.
A little more typing in defining the case class,
but we get a lot of benefit.
The compiler is able to help us with type checking,
we have a sensible type to pass around,
which helps with increased meaning ---
is a tuple of `(Long,String)` the same as `(String,Long)`?
We can't tell, one could be a count of messages rather than a
`user`.


<div class="callout callout-warning">
### HList

Slick's **experimental** [`HList`][link-slick-hlist] implementation is useful if you need to support tables with more than 22 columns,
such as a legacy database.

As an aside,
here is the `user` table using `HList`.

~~~ scala

  type User  = String :: Long :: HNil

  final class UserTable(tag: Tag) extends Table[User](tag, "user") {
    def id = column[Long]("id", O.PrimaryKey, O.AutoInc)
    def name = column[String]("sender")
    def * = name :: id :: HNil
  }

  lazy val users = TableQuery[UserTable]

  val dave = "Dave" :: 0L :: HNil
  val hal = "HAL" :: 0L :: HNil

  users ++= Seq(dave,hal)

  val oDave = users.filter(_.name === "Dave").firstOption
  val oHAL = users.filter(_.name === "HAL").firstOption

   for {
        dave <- oDave
        hal  <- oHAL
      } {
      val index = Nat(1)
      val daveId = dave(index)
      val halId = hal(index)

      println(s"daveId $daveId")
      println(s"daveId $halId")

      users.iterator.foreach(println)
~~~

It is worth noting `Nat` has a dependency on `"org.scala-lang" % "scala-reflect" % scalaVersion.value`,
which took one of the authors **far** to long to establish.
</div>

##Tables

Let's looks at the definition of the `User` table and walk through what is involved.

~~~ scala
  final class TupleUserTable(tag: Tag) extends Table[TupleUser](tag, "user") {
    def id = column[Long]("id", O.PrimaryKey, O.AutoInc)
    def name = column[String]("name")
    def * = (name,id)
  }
  final class UserTableA(tag: Tag) extends Table[User](tag, "user") {
    def id = column[Long]("id", O.PrimaryKey, O.AutoInc)
    def name = column[String]("name")
    def * = (name,id) <> (User.tupled,User.unapply)
  }
~~~

We've defined two versions of the the `user` table, one using a tuple,
the other a case class.
As you can there is little difference between the two,
the of kind the `Table` class and the definition of the `*` method,
we'll come back to this.

First let's look at how this class relates to the database table.
The name of the table is given as a parameter,
in this case the `String` `user` --- `Table[User](tag, "user")`.
An optional schema name can also be provided, if required by your database.

Next we define methods for each of the tables columns.
These call the method `column` with it's type,
name and zero of more options.
This is rather self explainitory --- `name` has the type `String` and is mapped to a column `name`.
It has no options,
we'll explore column in the rest of this chapter.

Finally,
we come back to `*`.
It is the only method we are required to implement.
It defines the default projection for the table.
That is the row object we defined earlier.
If we are not using tuples we need to define how Slick will map between our row and projection.
We do this using the `<>` operator and supplying two methods,
one to wrap a returned tuple into our type and another to unwrap our type into a tuple.
In the `User` example `User.tupled` takes a tuple and returns a User,
while `User.unapply` takes a user and returns an `Option` of `(Long,String)`.

<div class="callout callout-info">
**Expose only what you need**

We can hide information by excluding it from our row definition. The default projection controls what is returned and it is driven by our row definition.
</div>

<!--
I think something like this should go here, but meh.
From now on, we will use case classes in our examples as they are easier to reason about.
-->

For the rest of the chapter we'll look at some more indepth areas of data modelling.

##Primary & Foreign keys

There are two methods to declare a column is a primary key.
In the first we declare a column is a primary key using class `O` which provides column options. We have seen examples of this in `Message` and `User`.

~~~ scala
def id = column[Long]("id", O.PrimaryKey, O.AutoInc)
~~~

The second method uses a method `primaryKey` which takes two parameters --- a name and a tuple of columns.  This is useful when defining compound primary keys.

<!--  Im aware this has nothing to do with the messaging example, I wanted something separate as I'm working around an issue with sqlite and autoincrement fields.
      As sooon as one defines O.AutoInc on a field slick or the driver is creating SQL marking the field as a PK.
    -->
As an example, let us define a table `ColourShape` which has two columns `colour` and `shape` which has a composite primary key consisting of both columns.

~~~ scala

  final case class ColourShape(colour: Long, shape: String)

  final class ColourShapeTable(tag: Tag) extends Table[ColourShape](tag, "colour_shape") {
    def colour = column[Long]("colour")
    def shape = column[String]("shape")

    def pk = primaryKey("colour_shape_pk", (colour,shape))

    def * = (colour,shape) <> (ColourShape.tupled, ColourShape.unapply)

  }

  lazy val coluredShapes = TableQuery[ColourShapeTable]

~~~

This would produce the following table:

~~~ sql
create table "colour_shape" ("colour" INTEGER NOT NULL,"shape" VARCHAR(254) NOT NULL,constraint "colour_shape_pk" primary key("colour","shape"))
~~~

Foreign keys are declared in a similar manner to compound primary keys, with the method --- `foreignKey`. `foreignKey` takes four required parameters:
   * a name;
   * the column(s) that make the foreignKey;
   * the `TableQuery`that the foreign key belongs to, and
   * a function on the supplied `TableQuery[T]` taking the supplied column(s) as parameters and returning an instance of `T`.

As an example let's improve our model by replacing the `sender` column in `Message` with a foreign key to the `User` primary key.

~~~ scala


  final case class User(id: Long, name: String)

  final class UserTable(tag: Tag) extends Table[User](tag, "user") {
    def id = column[Long]("id",O.PrimaryKey,O.AutoInc)
    def name = column[String]("name")

    def * = (id, name) <> (User.tupled, User.unapply)
  }

  lazy val users = TableQuery[UserTable]

  final case class Message(id: Long, from: Long, content: String, when: DateTime)

  final class MessageTable(tag: Tag) extends Table[Message](tag, "message") {
    def id = column[Long]("id", O.PrimaryKey, O.AutoInc)
    def senderId = column[Long]("sender")
    def sender = foreignKey("sender_fk", senderId, users)(_.id)
    def content = column[String]("content")
    def when = column[DateTime]("when")
    def * = (id, senderId, content, when) <> (Message.tupled, Message.unapply)
  }

  lazy val messages = TableQuery[MessageTable]

~~~

This will produce the following table:

<!-- I've formatted this for readability -->
~~~ sql
sqlite> .schema message
CREATE TABLE "message" ("id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
             "sender" INTEGER NOT NULL,
             "to" INTEGER,"content" VARCHAR(254) NOT NULL,
             "ts" TIMESTAMP NOT NULL,
             constraint
                  "sender_fk" foreign key("sender") references "user"("id")
                  on update NO ACTION on delete NO ACTION,
             constraint
                  "to_fk" foreign key("to") references "user"("id")
                  on update NO ACTION on delete NO ACTION);
~~~

<div class="callout callout-info">
**Slick isn't an ORM **

Adding foreign keys to our data model does not mean we can traverse from `Message` to `User`, as Slick is not an ORM.

We can however compose our queries and join the return the `User` we are interested in.

</div>

_TODO: Add a query example_

##Value classes

_TODO use a value class to define message content._


##Null columns

Thus far we have only looked at non null columns, however sometimes we will wish to modal optional data. Slick handles this in an idiomatic scala fashion using `Option[T]`. Let's expand our data model to allow direct messaging by adding the ability to define a recipient on `Message`, which we will label `to`:

~~~ scala

  final case class Message(id: Long, sender: Long, to: Option[Long], content: String, ↩
                           ts: Timestamp)

  final class MessageTable(tag: Tag) extends Table[Message](tag, "message") {

    def id = column[Long]("id", O.PrimaryKey, O.AutoInc)
    def senderId = column[Long]("sender")
    def sender = foreignKey("sender_fk", senderId, users)(_.id)
    def toId = column[Option[Long]]("to")
    def to = foreignKey("to_fk", toId, users)(_.id)
    def content = column[String]("content")
    def ts = column[Timestamp]("ts")

    def * = (id, senderId, toId, content, ts) <> (Message.tupled, Message.unapply)

  }

~~~

<div class="callout callout-info">
***Equality***

While nullability is treated in an idiomatic Scala fashion using `Option[T]`. It behaves differently.

</div>

###Exercises

1. How do we write a query for messages: without a recipient?
2. How do we write a query for messages with a recipient?
3. How do we write a query for messages with a given recipient?

##Row and column control (autoinc etc)

__TODO__

##Custom Column Mapping

- value classes
- enumerations
- more examples of this

##Virtual columns and server-side casts here?

##Exercises