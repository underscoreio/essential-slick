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

**TODO --- I think this sounds pants**
For the rest of the chapter we'll look at some more indepth areas of data modelling.

###Null columns

Thus far we have only looked at non null columns,
however sometimes we will wish to modal optional data.
Slick handles this in an idiomatic scala fashion using `Option[T]`.

Let's expand our data model to allow direct messaging,
by adding the ability to define a recipient on `Message`.
We'll label the column `to`:

~~~ scala

  final case class Message(sender: Long,
                           content: String,
                           ts: DateTime,
                           to: Option[Long] = None,
                           id: Long = 0L)

  final class MessageTable(tag: Tag) extends Table[Message](tag, "message") {

    def id       = column[Long]("id", O.PrimaryKey, O.AutoInc)
    def senderId = column[Long]("sender")
    def toId     = column[Option[Long]]("to")
    def content  = column[String]("content")
    def ts       = column[Timestamp]("ts")

    def * = (senderId, content, ts, toId, id) <> (Message.tupled, Message.unapply)

  }

~~~

<div class="callout callout-danger">
#### Equality
We can not compare these columns as `Option[T]` in queries.

Consider the snippet below,
what do you expect the two results to be?

~~~ scala

val :Option[Long] = None

val a = messages.filter(_.to === to).iterator.foreach(println)
val b = messages.filter(_.to.isEmpty).iterator.foreach(println)

~~~

If you said they would both produce the list of messages,
you'd be wrong.
`a` returns an empty list as `None === None` returns `None`.
We need to use `isEmpty` if we want to filter on null columns.
</div>


###Primary keys

There are two methods to declare a column is a primary key.
In the first we declare a column is a primary key using class `O` which provides column options.
We have seen examples of this in `Message` and `User`.

~~~ scala
def id = column[Long]("id", O.PrimaryKey, O.AutoInc)
~~~

The second method uses a method `primaryKey` which takes two parameters ---
a name and a tuple of columns.
This is useful when defining compound primary keys.

By way of a not at all contrived example,
let us add the ability for people to chat in rooms.
I've excluded the room definition,
it is the same as user.

~~~ scala
  final case class Room(name: String, id: Long = 0L)

  final class RoomTable(tag: Tag) extends Table[User](tag, "room") {
    def id = column[Long]("id", O.PrimaryKey, O.AutoInc)
    def name = column[String]("name")
    def * = (name, id) <> (User.tupled, User.unapply)
  }

  lazy val rooms = TableQuery[RoomTable]

  final case class Occupant(roomId:Long,userId:Long)

  final class OccupantTable(tag: Tag) extends Table[Occupant](tag, "occupant") {
    def roomId = column[Long]("room")
    def userId = column[Long]("user")
    def pk = primaryKey("room_user_pk", (roomId,userId))
    def * = (roomId,userId) <> (Occupant.tupled, Occupant.unapply)
  }

  lazy val occupants = TableQuery[UserTable]
~~~
<div class="callout callout-info">
####TODO Give this a Label
Now we have `room` and `user` the benefit of case classes over tuples becomes apparent.
They both have the same tuple signature `(String,Long)`.
It would get error prone passing around tuples like this.
</div>


The SQL generated for the `occupant` table is:

~~~ sql
create table "occupant" ("room" BIGINT NOT NULL,"user" BIGINT NOT NULL)
alter table "occupant" add constraint "room_user_pk" primary key("room","user")
~~~

###Foreign keys

Foreign keys are declared in a similar manner to compound primary keys,
with the method --- `foreignKey`.
`foreignKey` takes four required parameters:
   * a name;
   * the column(s) that make the foreignKey;
   * the `TableQuery`that the foreign key belongs to, and
   * a function on the supplied `TableQuery[T]` taking the supplied column(s) as parameters and returning an instance of `T`.

Let's improve our model by using foreign keys for `message`, `sender` and `to` fields:

~~~ scala
  lazy val messages = TableQuery[MessageTable]

  final case class User(name: String, id: Long = 0L)

  final class UserTable(tag: Tag) extends Table[User](tag, "user") {
    def id = column[Long]("id", O.PrimaryKey, O.AutoInc)
    def name = column[String]("sender")
    def * = (name, id) <> (User.tupled, User.unapply)
  }

  lazy val users = TableQuery[UserTable]

  final case class Message(sender: Long,
                           content: String,
                           ts: DateTime,
                           to: Option[Long] = None,
                           id: Long = 0L)

  final class MessageTable(tag: Tag) extends Table[Message](tag, "message") {
    def id       = column[Long]("id", O.PrimaryKey, O.AutoInc)
    def senderId = column[Long]("sender")
    def sender   = foreignKey("sender_fk", senderId, users)(_.id)
    def toId     = column[Option[Long]]("to")
    def to       = foreignKey("to_fk", toId, users)(_.id)
    def content  = column[String]("content")
    def ts       = column[DateTime]("ts")
    def *        = (senderId, content, ts, toId, id) <> (Message.tupled, Message.unapply)
  }

  lazy val messages = TableQuery[MessageTable]
~~~


We can see the SQL this produces by running: `dl.createStatements.foreach(println)`.
Which we have included here:
<!-- I've formatted this for readability -->

~~~ sql
CREATE TABLE "message" ("sender" BIGINT NOT NULL,
                        "content" VARCHAR NOT NULL,
                        "ts" TIMESTAMP NOT NULL,
                        "to" BIGINT,
                        "id" BIGINT GENERATED BY DEFAULT
                        AS IDENTITY(START WITH 1) NOT NULL PRIMARY KEY)

ALTER TABLE "message"
      ADD CONSTRAINT "sender_fk"
      FOREIGN KEY("sender")
      REFERENCES "user"("id") ON UPDATE NO ACTION ON DELETE NO ACTION
alter TABLE "message"
      ADD constraint "to_fk"
      FOREIGN KEY("to")
      REFERENCES "user"("id") ON UPDATE NO ACTION ON DELETE NO ACTION
~~~

<div class="callout callout-info">
####Slick isn't an ORM

Adding foreign keys to our data model does not mean we can traverse from `Message` to `User`, as Slick is not an ORM.

We can however compose our queries and join to return the `User` we are interested in.
The following defines a query which will return the users who sent messages containing `do`:

~~~ scala
  val senders = for {
    message <- messages
    if message.content.toLowerCase like "%do%"
    sender <- message.sender
  } yield sender
~~~

</div>


###Value classes

Something about case classes are better than tuples.
However,
we are still assigning `Long`s as primary keys,
there is nothing to stop us asking for all messages based on a users id:

~~~ scala
val rubbish = oHAL.map{hal => messages.filter(msg => msg.id === hal.id)  }
~~~

This makes no sense, but the compiler can not help us.
Let's see how [value classes][link-scala-value-classes] can help us.
We'll define value classes for `message`, `user` and `room` primary keys.

~~~ scala
  final case class MessagePK(value: Long) extends AnyVal
  final case class UserPK(value: Long)    extends AnyVal
  final case class RoomPK(value: Long)    extends AnyVal
~~~

For us to be able to use these, we need to define implicits so Slick can convert between the value class and expected type.

~~~ scala
  implicit val messagePKMapper = MappedColumnType.base[MessagePK, Long](_.value, MessagePK(_))
  implicit val userPKMapper = MappedColumnType.base[UserPK, Long](_.value, UserPK(_))
  implicit val roomPKMapper = MappedColumnType.base[RoomPK, Long](_.value, RoomPK(_))
~~~

With our value classes and implicits in place,
we can now use them to give us type checking on our primary and therefore foriegn keys!

~~~ scala
  final case class Message(sender: UserPK,
                           content: String,
                           ts: DateTime,
                           to: Option[UserPK] = None,
                           id: MessagePK = MessagePK(0))

  final class MessageTable(tag: Tag) extends Table[Message](tag, "message") {
    def id = column[MessagePK]("id", O.PrimaryKey, O.AutoInc)
    def senderId = column[UserPK]("sender")
    def sender = foreignKey("sender_fk", senderId, users)(_.id)
    def toId = column[Option[UserPK]]("to")
    def to = foreignKey("to_fk", toId, users)(_.id)
    def content = column[String]("content")
    def ts = column[DateTime]("ts")
    def * = (senderId, content, ts, toId, id) <> (Message.tupled, Message.unapply)
  }
~~~

Now, if we try our query again :

~~~ scala
[error] /Users/jonoabroad/developer/books/essential-slick-example/chapter-03/src/main/scala/chapter03/main.scala:129: Cannot perform option-mapped operation
[error]       with type: (chapter03.Example.MessagePK, chapter03.Example.UserPK) => R
[error]   for base type: (chapter03.Example.MessagePK, chapter03.Example.MessagePK) => Boolean
[error]     val rubbish = oHAL.map{hal => messages.filter(msg => msg.id === hal.id)  }
[error]                                                                 ^
[error] /Users/jonoabroad/developer/books/essential-slick-example/chapter-03/src/main/scala/chapter03/main.scala:129: ambiguous implicit values:
[error]  both value BooleanOptionColumnCanBeQueryCondition in object CanBeQueryCondition of type => scala.slick.lifted.CanBeQueryCondition[scala.slick.lifted.Column[Option[Boolean]]]
[error]  and value BooleanCanBeQueryCondition in object CanBeQueryCondition of type => scala.slick.lifted.CanBeQueryCondition[Boolean]
[error]  match expected type scala.slick.lifted.CanBeQueryCondition[Nothing]
[error]     val rubbish = oHAL.map{hal => messages.filter(msg => msg.id === hal.id)  }
[error]                                                  ^
[error] two errors found
[error] (compile:compile) Compilation failed
[error] Total time: 2 s, completed 06/02/2015 12:12:53 PM
~~~

The compiler helps,
by telling us we are attempting to compare a `MessagePK` with a `UserPK`.

###Row and column control

We have already seen several examples of these,
including `O.PrimaryKey` and `O.AutoInc`.
Which unsurprislingly declare a column to be a primary key and auto incrementing.
Column options are defined in [ColumnOption][link-slick-column-options],
and as you have seen are accessed via `O`.
We get access to `O` when we import the slick driver,
in our case `import scala.slick.driver.H2Driver.simple._`.

As well as `PrimaryKey` and `AutoInc`,
there is also `Length`, `DBTYPE` and `Default`.

**TODO: add words around examples:**

`Length` takes two parameters:

 * integer - number of unicode characters,
 * boolean - true `VarChar`, false `Char`.

~~~ scala
def name = column[String]("name",O.Length(128,true))
~~~

~~~ sql
-- true
create table "user" ("name" VARCHAR(128) NOT NULL,"id" BIGINT GENERATED BY DEFAULT AS IDENTITY(START WITH 1) NOT NULL PRIMARY KEY)
-- false
create table "user" ("name" CHAR(128) NOT NULL,"id" BIGINT GENERATED BY DEFAULT AS IDENTITY(START WITH 1) NOT NULL PRIMARY KEY)
~~~


`DBType` ...


~~~ scala
def avatar = column[Option[Array[Byte]]]("avatar",O.DBType("Binary(2048)"))
~~~

~~~ sql
create table "user" ("name" VARCHAR DEFAULT '☃' NOT NULL,
                     "avatar" Binary(2048),
                     "id" BIGINT GENERATED BY DEFAULT AS IDENTITY(START WITH 1)
                      NOT NULL PRIMARY KEY)
~~~


`Default` ...

~~~ scala
def name = column[String]("name",O.Default("☃"))
~~~

~~~ sql

create table "user" ("name" VARCHAR DEFAULT '☃' NOT NULL,"id" BIGINT GENERATED BY DEFAULT AS IDENTITY(START WITH 1) NOT NULL PRIMARY KEY)

~~~



<div class="callout callout-info">
#### Notes

##### Nullability

We can also explicitly declare the nullability of a column using `NotNull` and`Nullable`.
Just use `Option[T]` - `NotNull` and `Nullable` are redundant.

##### `Strings`

It is worth noting when defining a `String` column,
if you do not provide either a `Length` or `DBType` column option Slick will default to either `VARCHAR` or `VARCHAR(254)` in the DDL.
</div>

##Custom Column Mapping

- enumerations
- more examples of this

##Virtual columns and server-side casts here?

## Exercises

### Add a message

What happens if you try adding a message with a user id of `3`?
For example:

~~~ scala
messages += Message(3L, "Hello HAl!",  new DateTime(2001, 2, 17, 10, 22, 50))
~~~

<div class="solution">

We get a runtime exception as we have violated referential integrity.
There is no row in the `user` table with a primary id of `3`.

~~~ bash

[error] (run-main-12) org.h2.jdbc.JdbcSQLException: Referential integrity constraint violation: "sender_fk: PUBLIC.""message"" FOREIGN KEY(""sender"") REFERENCES PUBLIC.""user""(""id"") (3)"; SQL statement:
[error] insert into "message" ("sender","content","ts","to")  values (?,?,?,?) [23506-185]
org.h2.jdbc.JdbcSQLException: Referential integrity constraint violation: "sender_fk: PUBLIC.""message"" FOREIGN KEY(""sender"") REFERENCES PUBLIC.""user""(""id"") (3)"; SQL statement:
insert into "message" ("sender","content","ts","to")  values (?,?,?,?) [23506-185]
  at org.h2.message.DbException.getJdbcSQLException(DbException.java:345)
  at org.h2.message.DbException.get(DbException.java:179)
  at org.h2.message.DbException.get(DbException.java:155)
  at org.h2.constraint.ConstraintReferential.checkRowOwnTable(ConstraintReferential.java:372)
  at org.h2.constraint.ConstraintReferential.checkRow(ConstraintReferential.java:314)
  at org.h2.table.Table.fireConstraints(Table.java:920)
  at org.h2.table.Table.fireAfterRow(Table.java:938)
  at org.h2.command.dml.Insert.insertRows(Insert.java:161)
  at org.h2.command.dml.Insert.update(Insert.java:114)
  at org.h2.command.CommandContainer.update(CommandContainer.java:78)
  at org.h2.command.Command.executeUpdate(Command.java:254)
  at org.h2.jdbc.JdbcPreparedStatement.executeUpdateInternal(JdbcPreparedStatement.java:157)
  at org.h2.jdbc.JdbcPreparedStatement.executeUpdate(JdbcPreparedStatement.java:143)
  at scala.slick.driver.JdbcInsertInvokerComponent$BaseInsertInvoker$$anonfun$internalInsert$1.apply(JdbcInsertInvokerComponent.scala:183)
  at scala.slick.driver.JdbcInsertInvokerComponent$BaseInsertInvoker$$anonfun$internalInsert$1.apply(JdbcInsertInvokerComponent.scala:180)
  at scala.slick.jdbc.JdbcBackend$SessionDef$class.withPreparedStatement(JdbcBackend.scala:191)
  at scala.slick.jdbc.JdbcBackend$BaseSession.withPreparedStatement(JdbcBackend.scala:389)
  at scala.slick.driver.JdbcInsertInvokerComponent$BaseInsertInvoker.preparedInsert(JdbcInsertInvokerComponent.scala:170)
  at scala.slick.driver.JdbcInsertInvokerComponent$BaseInsertInvoker.internalInsert(JdbcInsertInvokerComponent.scala:180)
  at scala.slick.driver.JdbcInsertInvokerComponent$BaseInsertInvoker.insert(JdbcInsertInvokerComponent.scala:175)
  at scala.slick.driver.JdbcInsertInvokerComponent$InsertInvokerDef$class.$plus$eq(JdbcInsertInvokerComponent.scala:70)
  at scala.slick.driver.JdbcInsertInvokerComponent$BaseInsertInvoker.$plus$eq(JdbcInsertInvokerComponent.scala:145)
  at chapter03.Example$$anonfun$5.apply(main.scala:84)
  at chapter03.Example$$anonfun$5.apply(main.scala:57)
  at scala.slick.backend.DatabaseComponent$DatabaseDef$class.withSession(DatabaseComponent.scala:34)
  at scala.slick.jdbc.JdbcBackend$DatabaseFactoryDef$$anon$4.withSession(JdbcBackend.scala:61)
  at chapter03.Example$.delayedEndpoint$chapter03$Example$1(main.scala:56)
  at chapter03.Example$delayedInit$body.apply(main.scala:12)
  at scala.Function0$class.apply$mcV$sp(Function0.scala:40)
  at scala.runtime.AbstractFunction0.apply$mcV$sp(AbstractFunction0.scala:12)
  at scala.App$$anonfun$main$1.apply(App.scala:76)
  at scala.App$$anonfun$main$1.apply(App.scala:76)
  at scala.collection.immutable.List.foreach(List.scala:381)
  at scala.collection.generic.TraversableForwarder$class.foreach(TraversableForwarder.scala:35)
  at scala.App$class.main(App.scala:76)
  at chapter03.Example$.main(main.scala:12)
  at chapter03.Example.main(main.scala)
  at sun.reflect.NativeMethodAccessorImpl.invoke0(Native Method)
  at sun.reflect.NativeMethodAccessorImpl.invoke(NativeMethodAccessorImpl.java:57)
  at sun.reflect.DelegatingMethodAccessorImpl.invoke(DelegatingMethodAccessorImpl.java:43)
  at java.lang.reflect.Method.invoke(Method.java:606)
~~~
</div>

1. How do we write a query for messages: without a recipient?
2. How do we write a query for messages with a recipient?
3. How do we write a query for messages with a given recipient?



