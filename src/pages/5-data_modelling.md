# Data Modelling {#Modelling}

We can do the basics of connecting to a database, running queries, and changing data.
We turn now to richer models of data and how our application hangs together.

In this chapter we will:

- understand how to structure an application;

- look at alternatives to modelling rows as case classes;

- store richer data types in columns; and

- expand on our knowledge of modelling tables to introduce optional values and foreign keys.

To do this, we'll expand the chat application schema to support more than just messages.

## Application Structure

So far, all of our examples have been written in a single Scala file.
This approach doesn't scale to larger application codebases.
In this section we'll explain how to split up application code into modules.

Until now we've also been exclusively using Slick's H2 driver.
When writing real applications we often need to be able to
switch drivers in different circumstances.
For example, we may use PostgreSQL in production and H2 in our unit tests.

An example of this pattern can be found in the [example project][link-example],
folder _chapter-05_, file _structure.scala_.

### Abstracting over Databases

Let's look at how we can write code that works with multiple different database drivers.
When we previously wrote:

```tut:book
import slick.driver.H2Driver.api._
```

We now have to write an import that works with a variety of drivers.
Fortunately, Slick provides a common supertype for the drivers
for the most popular databases---a trait called `JdbcProfile`:

```tut:book
import slick.driver.JdbcProfile
```

<div class="callout callout-info">
*Drivers and Profiles*

Slick uses the words "driver" and "profile" interchangeably.
We'll start referring to Slick drivers as "profiles" here
to distinguish them from the JDBC drivers that sit lower in the code.
</div>

We can't import directly from `JdbcProfile` because it isn't a concrete object.
Instead, we have to *inject a dependency* of type `JdbcProfile` into our application
and import from that. The basic pattern we'll use is as follows:

* isolate our database code into a trait (or a few traits);

* declare the Slick profile as an abstract `val` and import from that; and

* extend our database trait to make the profile concrete.

Here's the simplest form of this pattern:

```tut:book
trait DatabaseModule {
  // Declare an abstract profile:
  val profile: JdbcProfile

  // Import the Slick API from the profile:
  import profile.api._

  // Write our database code here...
}

object Main extends App {
  // Instantiate the database module, assigning a concrete profile:
  val databaseLayer = new DatabaseModule {
    val profile = slick.driver.H2Driver
  }
}
```

In this pattern, we declare our profile using an abstract `val`.
This is enough to allow us to write `import profile.api._`.
The compiler knows that the `val` is *going to be* an immutable `JdbcProfile`
even if we haven't yet said which one.
When we instantiate the `DatabaseModule` we bind `profile` to our profile of choice.

### Scaling to Larger Codebases

As our applications get bigger,
we need to split our code up into multiple files to keep it manageable.
We can do this by extending the pattern above to a family of traits:

```tut:book
trait Profile {
  val profile: JdbcProfile
}

trait DatabaseModule1 { self: Profile =>
  import profile.api._

  // Write database code here
}

trait DatabaseModule2 { self: Profile =>
  import profile.api._

  // Write more database code here
}

// Mix the modules together:
class DatabaseLayer(val profile: JdbcProfile) extends
  Profile with
  DatabaseModule1 with
  DatabaseModule2

// Instantiate the modules and inject a profile:
object Main extends App {
  val databaseLayer = new DatabaseLayer(slick.driver.H2Driver)
}
```

Here we factor out our `profile` dependency into its own `Profile` trait.
Each module of database code specifies `Profile` as a self-type,
meaning it can only be extended by a class that also extends `Profile`.
This allows us to share the `profile` across our family of modules.

To work with a different database, we inject a different profile
when we instantiate the database code:

```tut:book
val anotherDatabaseLayer = new DatabaseLayer(slick.driver.PostgresDriver)
```

This basic pattern is reasonable way of structuring your application.

<!--
### Namespacing Queries

We can exploit the expanded form of `TableQuery[T]`, a macro, to provide a location to store queries.
`TableQuery[T]`'s expanded form is:

~~~ scala
(new TableQuery(new T(_)))`
~~~

Using this, we can provide a module to hold `Message` queries:

~~~ scala
object messages extends TableQuery(new MessageTable(_)) {

  def messagesFrom(name: String) =
    this.filter(_.sender === name)

  val numSenders = this.map(_.sender).countDistinct
}
~~~

This adds values and methods to `messages`:

~~~ scala
val action =
  messages.numSenders.result
~~~
-->

## Representations for Rows

In previous chapters we modelled rows as case classes.
Although this is the most common usage pattern, and the one we recommend,
there are several representation options available, including tuples,
case classes, and `HList`s.
Let's investigate these by looking in more detail
at how Slick relates columns in our database to fields in our classes.

### Projections, `ProvenShapes`, and `<>`

When we declare a table in Slick, we are required to implement a `*` method
that specifies a "default projection":

```tut:book
final class MyTable(tag: Tag) extends Table[(String, Int)](tag, "mytable") {
  def column1 = column[String]("column1")
  def column2 = column[Int]("column2")
  def * = (column1, column2)
}
```

<div class="callout callout-info">
**Expose Only What You Need**

We can hide information by excluding it from our row definition.
The default projection controls what is returned, in what order,
and is driven by our row definition.

For example, we don't need to map everything
in a table with legacy columns that aren't being used.
</div>

Projections provide mappings between database columns and Scala values.
In the code above, the definition of `*` is mapping `column1` and `column2`
from the database to the `(String, Int)` tuples defined in the `extends Table` clause.

If we look at the definition of `*` in the `Table` class, we see something confusing:

~~~ scala
abstract class Table[T] {
  def * : ProvenShape[T]
}
~~~

The type of `*` is actually something called a `ProvenShape`,
not a tuple of columns as we specified in our example.
There is clearly something else going on here.
Slick is using implicit conversions
to build a `ProvenShape` object from the columns we provided.

The internal workings of `ProvenShape` are certainly beyond the scope of this book.
Suffice to say that Slick can use any Scala type as a projection provided it can generate a compatible `ProvenShape`.
If we look at the rules for `ProvenShape` generation,
we will get an idea about what data types we can map.
Here are the three most common use cases:


```tut:invisible
// Because I can't get the code in the enumerated list to render and indent nicely with tut yet.

// 1
    final class MyTable(tag: Tag) extends Table[String](tag, "mytable") {
      def column1 = column[String]("column1")
      def * = column1
    }

// 2
  final class MyTable(tag: Tag) extends Table[(String, Int)](tag, "mytable") {
    def column1 = column[String]("column1")
    def column2 = column[Int]("column2")
    def * = (column1, column2)
  }

// 3
    case class User(name: String, id: Long)
    final class UserTable(tag: Tag) extends Table[User](tag, "user") {
      def id   = column[Long]("id", O.PrimaryKey, O.AutoInc)
      def name = column[String]("name")
      def * = (name, id) <> (User.tupled, User.unapply)
    }
```

1.  Single `column` definitions produce shapes that map the column contents
to a value of the column's type parameter.
For example, a column of `Rep[String]` maps a value of type `String`:

    ```scala
    final class MyTable(tag: Tag) extends Table[String](tag, "mytable") {
      def column1 = column[String]("column1")
      def * = column1
    }
    ```
    <!-- If you change this ^^ code update the invisible block above -->

2. Tuples of database columns map tuples of their type parameters.
For example, `(Rep[String], Rep[Int])` is mapped to `(String, Int)`:

    ```scala
    final class MyTable(tag: Tag) extends Table[(String, Int)](tag, "mytable") {
      def column1 = column[String]("column1")
      def column2 = column[Int]("column2")
      def * = (column1, column2)
    }
    ```
    <!-- If you change this ^^ code update the invisible block above -->

3. If we have a `ProvenShape[A]`, we can convert it to a `ProvenShape[B]`
using the "projection operator" `<>`.
In this example we know we can get `ProvenShape[A]` when the `A` is the `String` and `Int` tuple (from the previous example).
We supply functions to convert each way between `A` and `B`
and Slick builds the resulting shape. Here our `B` is the `User` case class:

    ```scala
    case class User(name: String, id: Long)

    final class UserTable(tag: Tag) extends Table[User](tag, "user") {
      def id   = column[Long]("id", O.PrimaryKey, O.AutoInc)
      def name = column[String]("name")
      def * = (name, id) <> (User.tupled, User.unapply)
    }
    ```
    <!-- If you change this ^^ code update the invisible block above -->

The projection operator `<>` is the secret ingredient that
allows us to map a wide variety of types.
As long as we can convert a tuple of columns to and from some type `B`,
we can store instances of `B` in a database.

The two arguments to `<>` are:

* a function from `A => B`, which converts
  from the existing shape's unpacked row-level encoding `(String, Long)`
  to our preferred representation (`User`); and

* a function from `B => Option[A]`, which converts the other way.

We can supply these functions by hand if we want:

```tut:book
def intoUser(pair: (String, Long)): User =
  User(pair._1, pair._2)

def fromUser(user: User): Option[(String, Long)] =
  Some((user.name, user.id))
```

and write:

```tut:book
final class UserTable(tag: Tag) extends Table[User](tag, "user") {
  def id   = column[Long]("id", O.PrimaryKey, O.AutoInc)
  def name = column[String]("name")
  def * = (name, id) <> (intoUser, fromUser)
}
```

In the `User` example, the case class supplies these functions
via `User.tupled` and `User.unapply`, so we don't need to build them ourselves.
However it is useful to remember that we can provide our own functions
for more elaborate packaging and unpackaging of rows.
We will see this in one of the exercises in this section.

### Tuples versus Case Classes

We've seen how Slick is able to map case classes and tuples of values.
But which should we use? In one sense there is little difference
between case classes and tuples---both represent fixed sets of values.
However, case classes differ from tuples in two important respects.

First, case classes have field names, which improves code readability:

```tut:book
val user = User("Dave", 0L)
user.name // case class field access

val tuple = ("Dave", 0L)
tuple._1 // tuple field access
```

Second, case classes have types that distinguish them
from other case classes with the same field types:

```tut:book
case class Dog(name: String, id: Long)

val user = User("Dave", 0L)
val dog  = Dog("Lassie", 0L)
```
```tut:book:fail
user == dog // different types
```

As a general rule, we recommend using case classes to represent database rows
for these reasons.


### Heterogeneous Lists

We've seen how Slick can map database tables to tuples and case classes.
Scala veterans identify a key weakness in this approach---tuples
and case classes don't scale beyond 22 fields[^scala211-limit22].

[^scala211-limit22]: Scala 2.11 introduced the ability
to define case classes with more than 22 fields,
but tuple and function arities are still limited to 22.

Many of us have heard horror stories of legacy tables in enterprise databases
that have tens or hundreds of columns.
We can't map everything in these tables using the tuple approach described above[^slick32].
Fortunately, Slick provides an [`HList`][link-slick-hlist] implementation
to support tables with very large numbers of columns.

[^slick32]: Slick 3.2 is planned to have a new macro, `mapTo`, which will replace `<>` and allow
mapping to tables with more than 22 columns.

To motivate this, let's consider a poorly-designed legacy table
for storing product attributes:

```tut:book
case class Attr(id: Long, productId: Long /* ...etc */)

final class AttrTable(tag: Tag) extends Table[Attr](tag, "attrs") {
  def id        = column[Long]("id", O.PrimaryKey, O.AutoInc)
  def productId = column[Long]("product_id")
  def name1     = column[String]("name1")
  def value1    = column[Int]("value1")
  def name2     = column[String]("name2")
  def value2    = column[Int]("value2")
  def name3     = column[String]("name3")
  def value3    = column[Int]("value3")
  def name4     = column[String]("name4")
  def value4    = column[Int]("value4")
  def name5     = column[String]("name5")
  def value5    = column[Int]("value5")
  def name6     = column[String]("name6")
  def value6    = column[Int]("value6")
  def name7     = column[String]("name7")
  def value7    = column[Int]("value7")
  def name8     = column[String]("name8")
  def value8    = column[Int]("value8")
  def name9     = column[String]("name9")
  def value9    = column[Int]("value9")
  def name10    = column[String]("name10")
  def value10   = column[Int]("value10")
  def name11    = column[String]("name11")
  def value11   = column[Int]("value11")
  def name12    = column[String]("name12")
  def value12   = column[Int]("value12")

  def * = ??? // we'll fill this in below
}
```

Hopefully you don't have a table like this at your organization,
but accidents do happen.

This table has 26 columns---too many to model using tuples and `<>`.
Fortunately, Slick provides an alternative mapping representation
that scales to arbitrary numbers of columns.
This new representation is called a _heterogeneous list_ or `HList`[^hlist].

[^hlist]: You may have heard of `HList` via other libraries, such as [shapeless][link-shapeless].
We're talking here about Slick's own implementation of `HList`, not the shapless one.
You can use the shapeless `HList` via a library we've provided called [slickless][link-slickless].

An `HList` is a sort of hybrid of a list and a tuple.
It has an arbitrary length like a `List`,
but each element can be a different type like a tuple.
Here are some examples:

```tut:book
import slick.collection.heterogeneous.{HList, HCons, HNil}
import slick.collection.heterogeneous.syntax._

val emptyHList = HNil

val shortHList: Int :: HNil = 123 :: HNil

val longerHList: Int :: String :: Boolean :: HNil =
  123 :: "abc" :: true :: HNil
```

`HList`s are constructed recursively like `List`s,
allowing us to model arbitrarily large collections of values:

- an empty `HList` is represented by the singleton object `HNil`;

- longer `HList`s are formed by prepending values using the `::`
  operator, which creates a new list *of a new type*.

Notice the types and values of each `HList` mirror each other:
the `longerHList` comprises values of types `Int`, `String`, and `Boolean`,
and its type comprises the types `Int`, `String`, and `Boolean` as well.
Because the element types are preserved,
we can write code that takes each precise type into account.

Slick is able to produce `ProvenShapes`
to map `HList`s of columns to `HList`s of their values.
For example, the shape for a `Rep[Int] :: Rep[String] :: HNil`
maps values of type `Int :: String :: HNil`.

We can use an `HList` to map the large table in our example above.
Here's what the default projection looks like:

```tut:book
import slick.collection.heterogeneous.{ HList, HCons, HNil }
import slick.collection.heterogeneous.syntax._
import scala.language.postfixOps

type AttrHList =
  Long :: Long ::
  String :: Int :: String :: Int :: String :: Int ::
  String :: Int :: String :: Int :: String :: Int ::
  String :: Int :: String :: Int :: String :: Int ::
  String :: Int :: String :: Int :: String :: Int ::
  HNil

final class AttrTable(tag: Tag) extends Table[AttrHList](tag, "attrs") {
  def id        = column[Long]("id", O.PrimaryKey, O.AutoInc)
  def productId = column[Long]("product_id")
  def name1     = column[String]("name1")
  def value1    = column[Int]("value1")
  def name2     = column[String]("name2")
  def value2    = column[Int]("value2")
  def name3     = column[String]("name3")
  def value3    = column[Int]("value3")
  def name4     = column[String]("name4")
  def value4    = column[Int]("value4")
  def name5     = column[String]("name5")
  def value5    = column[Int]("value5")
  def name6     = column[String]("name6")
  def value6    = column[Int]("value6")
  def name7     = column[String]("name7")
  def value7    = column[Int]("value7")
  def name8     = column[String]("name8")
  def value8    = column[Int]("value8")
  def name9     = column[String]("name9")
  def value9    = column[Int]("value9")
  def name10    = column[String]("name10")
  def value10   = column[Int]("value10")
  def name11    = column[String]("name11")
  def value11   = column[Int]("value11")
  def name12    = column[String]("name12")
  def value12   = column[Int]("value12")

  def * = id :: productId ::
          name1 :: value1 :: name2 :: value2 :: name3 :: value3 ::
          name4 :: value4 :: name5 :: value5 :: name6 :: value6 ::
          name7 :: value7 :: name8 :: value8 :: name9 :: value9 ::
          name10 :: value10 :: name11 :: value11 :: name12 :: value12 ::
          HNil
}

val attributes = TableQuery[AttrTable]
```

Writing `HList` types and values is cumbersome and error prone,
so we've introduced a type alias for `AttrHList`
to avoid as much typing as we can.

```tut:invisible
import slick.driver.H2Driver.api._
import scala.concurrent.{Await,Future}
import scala.concurrent.duration._

val db = Database.forConfig("chapter05")

def exec[T](action: DBIO[T]): T = Await.result(db.run(action), 2.seconds)
```

Working with this table involves inserting, updating, selecting, and modifying
instances of `AttrHList`. For example:

```tut:book
import scala.concurrent.ExecutionContext.Implicits.global

val program: DBIO[Seq[AttrHList]] = for {
  _ <- attributes.schema.create
  _ <- attributes += 0L :: 100L ::
        "name1"  :: 1  :: "name2"  :: 2  :: "name3"  :: 3  ::
        "name4"  :: 4  :: "name5"  :: 5  :: "name6"  :: 6  ::
        "name7"  :: 7  :: "name8"  :: 8  :: "name9"  :: 9  ::
        "name10" :: 10 :: "name11" :: 11 :: "name12" :: 12 ::
        HNil
  rows <- attributes.filter(_.value1 === 1).result
} yield rows


val myAttrs: AttrHList = exec(program).head
```

We can extract values from our query results `HList` using pattern matching
or a variety of type-preserving methods defined on `HList`,
including `head`, `apply`, `drop`, and `fold`:

```tut:book
val id: Long = myAttrs.head
val productId: Long = myAttrs.tail.head
val name1: String = myAttrs(2)
val value1: Int = myAttrs(3)
// And so on...
```

In practice we'll want to map instances of `AttrHList`
to a regular class to make them easier to work with.
Fortunately Slick's `<>` operator works with `HList` shapes as well as tuple shapes.
We have to produce our own mapping functions in place of `apply` and `unapply`,
but otherwise this approach is the same as we've seen for tuples.

```tut:book
// An object so Attrs can be companions when run in the REPL
object AttrModule {

  case class Attrs(id: Long, productId: Long,
    name1: String, value1: Int, name2: String, value2: Int /* etc */)

  object Attrs {
    type AttrHList = Long :: Long ::
      String :: Int :: String :: Int :: /* etc */ HNil

    def hlistApply(hlist: AttrHList): Attrs = hlist match {
      case id :: pId :: n1 :: v1 :: n2 :: v2 /* etc */ :: HNil =>
        Attrs(id, pId, n1, v1, n2, v2 /* etc */)
    }

    def hlistUnapply(a: Attrs): Option[AttrHList] =
      Some(a.id :: a.productId ::
        a.name1 :: a.value1 :: a.name2 :: a.value2 /* etc */ :: HNil)
  }
}

import AttrModule._

final class AttrTable(tag: Tag) extends Table[Attrs](tag, "attributes") {
  def id        = column[Long]("id", O.PrimaryKey, O.AutoInc)
  def productId = column[Long]("product_id")
  def name1     = column[String]("name1")
  def value1    = column[Int]("value1")
  def name2     = column[String]("name2")
  def value2    = column[Int]("value2")
  /* etc */

  def * = (
    id :: productId ::
    name1 :: value1 :: name2 :: value2 /* etc */ :: 
    HNil
  ) <> (Attrs.hlistApply, Attrs.hlistUnapply)
}

val attributes = TableQuery[AttrTable]
```

Now our table is defined on a plain Scala class,
we can query and modify the data using regular data objects as normal:

```tut:book
val program: DBIO[Seq[Attrs]] = for {
  _    <- attributes.schema.create
  _    <- attributes += Attrs(0L, 100L, "n1", 1, "n2", 2 /* etc */)
  rows <- attributes.filter(_.productId === 100L).result
} yield rows

exec(program)
```

As you can see, typing all of the code to define `HList` mappings by hand
is error prone and likely to induce stress. There are two ways to improve on this:

- The first is to know that Slick can _generate_ this code for us from an existing database.
  If our main use for `HList`s is to map legacy database tables,
  code generation is the way to go.

- Second, we can improve the readability of our `HList`s
  by using _value classes_ to replace more vanilla column types like `String` and `Int`.
  This can increase verbosity but significantly reduces errors.
  We'll see this in the section on [value classes](#value-classes),
  later in this chapter.

<div class="callout callout-info">
**Code Generation**

Sometimes your code is the definitive description of the schema;
other times it's the database itself.
The latter is the case when working with legacy databases,
or database where the schema is managed independently of your Slick application.

When the database is considered the source truth in your organisation,
the [Slick code generator][link-ref-gen] is an important tool.
It allows you to connect to a database, generate the table definitions,
and customize the code produced.

Prefer it to manually reverse engineering a schema by hand.
</div>

### Exercises

#### Turning a Row into Many Case Classes

Our `HList` example mapped a table with many columns.
It's not the only way to deal with lots of columns.

Use custom functions with `<>` and map `UserTable` into a tree of case classes.
To do this you will need to define the schema, define a `User`, insert data, and query the data.

To make this easier, we're just going to map six of the columns.
Here are the case classes to use:

~~~ scala
case class EmailContact(name: String, email: String)
case class Address(street: String, city: String, country: String)
case class User(contact: EmailContact, address: Address, id: Long = 0L)
~~~

You'll find a definition of `UserTable` that you can copy and paste in the example code in the file _chapter-05/src/main/scala/nested_case_class.scala_.

<div class="solution">
A suitable projection is:

~~~ scala
type Row = (String, String, String, String, String, Long)

def pack(row: Row): User =
  User(
    EmailContact(row._1, row._2),
    Address(row._3, row._4, row._5),
    row._6
  )

def unpack(user: User): Option[Row] =
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

Executing `exec(users.result)` will produce:

~~~ scala
Vector(
  User(
    EmailContact(Dr. Dave Bowman,dave@example.org),
    Address(123 Some Street,Any Town,USA),
    1
  )
)
~~~

You can continue to select just some fields. For example `users.map(_.email).result` will produce:

~~~ scala
Vector(dave@example.org)
~~~

However, notice that if you used `users.schema.create`, only the columns defined in the default projection were created in the H2 database.
</div>



## Table and Column Representation

Now we know how rows can be represented and mapped,
let's look in more detail at the representation of the table and the columns it comprises.
In particular we'll explore nullable columns,
foreign keys, more about primary keys, composite keys,
and options you can apply to a table.

### Nullable Columns {#null-columns}

Columns defined in SQL are nullable by default.
That is, they can contain `NULL` as a value.
Slick makes columns non-nullable by default---if
you want a nullable column you model it naturally in Scala as an `Option[T]`.

Let's create a variant of `User` with an optional email address:

```tut:book
case class User(name: String, email: Option[String] = None, id: Long = 0L)

class UserTable(tag: Tag) extends Table[User](tag, "user") {
  def id    = column[Long]("id", O.PrimaryKey, O.AutoInc)
  def name  = column[String]("name")
  def email = column[Option[String]]("email")

  def * = (name, email, id) <> (User.tupled, User.unapply)
}

lazy val users = TableQuery[UserTable]
lazy val insertUser = users returning users.map(_.id)
```

We can insert users with or without an email address:

```tut:book
val program = (
  users.schema.create >>
  (users += User("Dave", Some("dave@example.org"))) >>
  (users += User("HAL"))
)

exec(program)
```

and retrieve them again with a select query:

```tut:book
exec(users.result)
```

So far, so ordinary.
What might be a surprise is how you go about selecting all rows that have no email address.
You might expect the following to find the one row that has no email address:

```tut:book
// Don't do this
val none: Option[String] = None
val myUsers = exec(users.filter(_.email === none).result)
```

Despite the fact that we do have
one row in the database no email address,
this query produces no results.

Veterans of database administration will be familiar with this interesting quirk of SQL:
expressions involving `null` themselves evaluate to `null`.
For example, the SQL expression `'Dave' = 'HAL'` evaluates to `false`,
whereas the expression `'Dave' = null` evaluates to `null`.

Our Slick query above amounts to:

~~~ sql
SELECT * FROM "user" WHERE "email" = NULL
~~~

The SQL expression `"email" = null` evaluates to `null` for any value of `"email"`.
SQL's `null` is a falsey value, so this query never returns a value.

To resolve this issue, SQL provides two operators: `IS NULL` and `IS NOT NULL`,
which are provided in Slick by the methods `isEmpty` and `isDefined` defined on any `Rep[Option[A]]`:

--------------------------------------------------------------------------------------------------------
Scala Code              Operand Column Types               Result Type        SQL Equivalent
----------------------- ---------------------------------- ------------------ --------------------------
`col.?`                 `A`                                `Option[A]`        `col`

`col.isEmpty`           `Option[A]`                        `Boolean`          `col is null`

`col.isDefined`         `Option[A]`                        `Boolean`          `col is not null`

--------------------------------------------------------------------------------------------------------

: Optional column methods.
  Operand and result types should be interpreted as parameters to `Rep[_]`.
  The `?` method is described in the next section.



We can fix our query by replacing our equality check with `isEmpty`:

```tut:book
val myUsers = exec(users.filter(_.email.isEmpty).result)
```

which translates to the following SQL:

~~~ sql
SELECT * FROM "user" WHERE "email" IS NULL
~~~


### Primary Keys

We had our first introduction to primary keys in Chapter 1,
where we started setting up `id` fields using
the `O.PrimaryKey` and `O.AutoInc` column options:

~~~ scala
def id = column[Long]("id", O.PrimaryKey, O.AutoInc)
~~~

These options do two things:

- they modify the SQL generated for DDL statements;

- `O.AutoInc` removes the corresponding column
  from the SQL generated for `INSERT` statements,
  allowing the database to insert an auto-incrementing value.

In Chapter 1 we combined `O.AutoInc` with
a case class that has a default ID of `0L`,
knowing that Slick will skip the value in insert statements:

```tut:book
case class User(name: String, id: Long = 0L)
```

While we like the simplicity of this style,
some developers prefer to wrap primary key values in `Options`:

```tut:book
case class User(name: String, id: Option[Long] = None)
```

In this model we use `None` as the primary key of an unsaved record
and `Some` as the primary key of a saved record.
This approach has advantages and disadvantages:

- on the positive side it's easier to identify unsaved records;

- on the negative side it's harder to get the value of a primary key for use in a query.

Let's look at the changes we need to make to our `UserTable`
to make this work:

```tut:book
case class User(id: Option[Long], name: String)

class UserTable(tag: Tag) extends Table[User](tag, "user") {
  def id     = column[Long]("id", O.PrimaryKey, O.AutoInc)
  def name   = column[String]("name")

  def * = (id.?, name) <> (User.tupled, User.unapply)
}


lazy val users = TableQuery[UserTable]
lazy val insertUser = users returning users.map(_.id)
```

The key thing to notice here is that
we *don't* want the primary key to be optional in the database.
We're using `None` to represent an *unsaved* value---the database
assigns a primary key for us on insert,
so we can never retrieve a `None` via a database query.

We need to map our non-nullable database column to an optional field value.
This is handled by the `?` method in the default projection,
which converts a `Rep[A]` to a `Rep[Option[A]]`.


### Compound Primary Keys

There is a second way to declare a column as a primary key:

~~~ scala
def id = column[Long]("id", O.AutoInc)
def pk = primaryKey("pk_id", id)
~~~

This separate step doesn't make much of a difference in this case.
It separates the column definition from the key constraint,
meaning the schema will include:

~~~ sql
ALTER TABLE "user" ADD CONSTRAINT "pk_id" PRIMARY KEY("id")
~~~

<div class="callout callout-info">
**H2 Issue**

As it happens, this specific example [doesn't currently work with H2 and Slick](https://github.com/slick/slick/issues/763).

The `O.AutoInc` marks the column as an H2 "IDENTIY"
column which is, implicitly, a primary key as far as H2 is concerned.
</div>


The `primaryKey` method is more useful for defining *compound* primary keys
that involve two or more columns.

Let's look at this by adding the ability for people to chat in rooms.
First we need a table for storing rooms, which is straightforward:

```tut:book
// Regular table definition for a chat room:
case class Room(title: String, id: Long = 0L)

class RoomTable(tag: Tag) extends Table[Room](tag, "room") {
 def id    = column[Long]("id", O.PrimaryKey, O.AutoInc)
 def title = column[String]("title")
 def * = (title, id) <> (Room.tupled, Room.unapply)
}

lazy val rooms = TableQuery[RoomTable]
lazy val insertRoom = rooms returning rooms.map(_.id)
```

Next we need a table that relates users to rooms.
We'll call this the *occupant* table.
Rather than give this table an auto-generated primary key,
we'll make it a compound of the user and room IDs:

```tut:book
case class Occupant(roomId: Long, userId: Long)

class OccupantTable(tag: Tag) extends Table[Occupant](tag, "occupant") {
  def roomId = column[Long]("room")
  def userId = column[Long]("user")

  def pk = primaryKey("room_user_pk", (roomId, userId))

  def * = (roomId, userId) <> (Occupant.tupled, Occupant.unapply)
}

lazy val occupants = TableQuery[OccupantTable]
```

We can define composite primary keys using tuples or `HList`s of columns
(Slick generates a `ProvenShape` and inspects it to find the list of columns involved).
The SQL generated for the `occupant` table is:

~~~ sql
CREATE TABLE "occupant" (
  "room" BIGINT NOT NULL,
  "user" BIGINT NOT NULL
)

ALTER TABLE "occupant"
ADD CONSTRAINT "room_user_pk" PRIMARY KEY("room", "user")
~~~

Using the `occupant` table is no different from any other table:

```tut:book
val program: DBIO[Int] = for {
   _        <- rooms.schema.create
   _        <- occupants.schema.create
  elenaId    <- insertUser += User(None, "Elena")
  airLockId <- insertRoom += Room("Air Lock")
  // Put Elena in the Room:
  rowsAdded <- occupants += Occupant(airLockId, elenaId)
} yield rowsAdded

exec(program)
```

```tut:invisible
val assure_o1 = exec(occupants.result)
assert(assure_o1.length == 1, "Expected 1 occupant")
```

Of course, if we try to put Dave in the Air Lock twice,
the database will complain about duplicate primary keys.


### Indices

We can use indices to increase the efficiency of database queries
at the cost of higher disk usage.
Creating and using indices is the highest form of database sorcery,
different for every database application,
and well beyond the scope of this book.
However, the syntax for defining an index in Slick is simple.
Here's a table with two calls to `index`:

```tut:book
class IndexExample(tag: Tag) extends Table[(String,Int)](tag, "people") {
  def name = column[String]("name")
  def age  = column[Int]("age")

  def * = (name, age)

  def nameIndex = index("name_idx", name, unique=true)
  def compoundIndex = index("c_idx", (name, age), unique=true)
}
```

The corresponding DDL statement produced due to `nameIndex` will be:

~~~ sql
CREATE UNIQUE INDEX "name_idx" ON "people" ("name")
~~~

We can create compound indices on multiple columns
just like we can with primary keys.
In this case (`compoundIndex`) the corresponding DDL statement will be:

~~~ sql
CREATE UNIQUE INDEX "c_idx" ON "people" ("name", "age")
~~~


### Foreign Keys

Foreign keys are declared in a similar manner to compound primary keys.

The method `foreignKey` takes four required parameters:

 * a name;
 
 * the column, or columns, that make up the foreign key;

 * the `TableQuery` that the foreign key belongs to; and

 * a function on the supplied `TableQuery[T]` taking
   the supplied column(s) as parameters and returning an instance of `T`.

We'll step through this by using foreign keys to connect a `message` to a `user`.
We do this by changing the definition of `message` to reference
the `id` of its sender instead of their name:

```tut:book
case class Message(
  senderId : Long,
  content  : String,
  id       : Long = 0L)

class MessageTable(tag: Tag) extends Table[Message](tag, "message") {
  def id       = column[Long]("id", O.PrimaryKey, O.AutoInc)
  def senderId = column[Long]("sender")
  def content  = column[String]("content")

  def * = (senderId, content, id) <> (Message.tupled, Message.unapply)

  def sender = foreignKey("sender_fk", senderId, users)(_.id)
}

lazy val messages = TableQuery[MessageTable]
```

The column for the sender is now a `Long` instead of a `String`.
We have also defined a method, `sender`,
providing the foreign key linking the `senderId` to a `user` `id`.

The `foreignKey` gives us two things.
First, it adds a constraint to the DDL statement generated by Slick:

~~~ sql
ALTER TABLE "message" ADD CONSTRAINT "sender_fk"
  FOREIGN KEY("sender") REFERENCES "user"("id")
  ON UPDATE NO ACTION
  ON DELETE NO ACTION
~~~

<div class="callout callout-info">
**On Update and On Delete**

A foreign key makes certain guarantees about the data you store.
In the case we've looked at there must be a `sender` in the `user` table
to successfully insert a new `message`.

So what happens if something changes with the `user` row?
There are a number of [_referential actions_][link-fkri] that could be triggered.
The default is for nothing to happen, but you can change that.

Let's look at an example.
Suppose we delete a user,
and we want all the messages associated with that user to be removed.
We could do that in our application, but it's something the database can provide for us:

```tut:book
class AltMsgTable(tag: Tag) extends Table[Message](tag, "message") {
  def id       = column[Long]("id", O.PrimaryKey, O.AutoInc)
  def senderId = column[Long]("sender")
  def content  = column[String]("content")

  def * = (senderId, content, id) <> (Message.tupled, Message.unapply)

  def sender = foreignKey("sender_fk", senderId, users)(_.id, onDelete=ForeignKeyAction.Cascade)
}
```

Providing Slick's `schema` command has been run for the table,
or the SQL `ON DELETE CASCADE` action has been manually applied to the database,
the following action will remove HAL from the `users` table,
and all of the messages that HAL sent:

```tut:silent
users.filter(_.name === "HAL").delete
```

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

</div>


Second, the foreign key gives us a query that we can use in a join.
We've dedicated the [next chapter](#joins) to looking at joins in detail,
but here's a simple join to illustrate the use case:

```tut:book
val q = for {
  msg <- messages
  usr <- msg.sender
} yield (usr.name, msg.content)
```

This is equivalent to the query:

~~~ sql
SELECT u."name", m."content"
FROM "message" m, "user" u
WHERE "id" = m."sender"
~~~

...and once we have populated the database...

```tut:book
def findUserId(name: String): DBIO[Option[Long]] =
  users.filter(_.name === name).map(_.id).result.headOption

def findOrCreate(name: String): DBIO[Long] =
  findUserId(name).flatMap { userId =>
    userId match {
      case Some(id) => DBIO.successful(id)
      case None     => insertUser += User(None, name)
    }
}

// Populate the messages table:
val setup = for {
  daveId <- findOrCreate("Dave")
  halId  <- findOrCreate("HAL")

  // Add some messages:
  _         <- messages.schema.create
  rowsAdded <- messages ++= Seq(
    Message(daveId, "Hello, HAL. Do you read me, HAL?"),
    Message(halId,  "Affirmative, Dave. I read you."),
    Message(daveId, "Open the pod bay doors, HAL."),
    Message(halId,  "I'm sorry, Dave. I'm afraid I can't do that.")
  )
} yield rowsAdded

exec(setup)
```

...our query produces the following results, showing the sender name (not ID) and corresponding message:

```tut:book
exec(q.result)
```

<!--
Notice that we modelled the `Message` row using a `Long` `sender`,
rather than a `User`:

~~~ scala
case class Message(senderId: Long,
                   content: String,
                   id: Long = 0L)
~~~

That's the design approach to take with Slick.
The row model should reflect the row, not the row plus a bunch of other data from different tables.
To pull data from across tables, use a query.
-->


<div class="callout callout-info">
**Save Your Sanity With Laziness**

Defining foreign keys places constraints
on the order in which we have to define our database tables.
In the example above, the foreign key from `MessageTable`
to `UserTable` requires us to place the latter definition above
the former in our Scala code.

Ordering constraints make complex schemas difficult to write.
Fortunately, we can work around them using `def` and `lazy val`.

As a rule, use `lazy val` for `TableQuery`s and `def` foreign keys (for consistency with `column` definitions).
</div>


### Column Options {#schema-modifiers}

We'll round off this section by looking at modifiers for columns and tables.
These allow us to tweak the default values, sizes, and data types for columns
at the SQL level.

We have already seen two examples of column options,
namely `O.PrimaryKey` and `O.AutoInc`.
Column options are defined in [`ColumnOption`][link-slick-column-options],
and as you have seen are accessed via `O`.

The following example introduces three new options:
`O.Length`, `O.SqlType`, and `O.Default`.

```tut:book
case class PhotoUser(
  name   : String,
  avatar : Option[Array[Byte]] = None,
  id     : Long = 0L)

class PhotoTable(tag: Tag) extends Table[PhotoUser](tag, "user") {
  def id     = column[Long]("id", O.PrimaryKey, O.AutoInc)

  def name   = column[String](
                 "name",
                 O.Length(64, true),
                 O.Default("Anonymous Coward")
                )

  def avatar = column[Option[Array[Byte]]]("avatar", O.SqlType("BINARY(2048)"))

  def * = (name, avatar, id) <> (PhotoUser.tupled, PhotoUser.unapply)
}
```

In this example we've done three things:

1. We've used `O.Length` to give the `name` column a maximum length.
   This modifies the type of the column in the DDL statement.
   The parameters to `O.Length` are an `Int` specifying the maximum length,
   and a `Boolean` indicating whether the length is variable.
   Setting the `Boolean` to `true` sets the SQL column type to `VARCHAR`;
   setting it to `false` sets the type to `CHAR`.

2. We've used `O.Default` to give the `name` column a default value.
   This adds a `DEFAULT` clause to the column definition in the DDL statement.

3. We've used `O.SqlType` to control the exact type used by the database.
   The values allowed here depend on the database we're using.


### Exercises

#### Filtering Optional Columns

Sometimes you want to look at all the users in the database, and sometimes you want to only see rows matching a particular value.

Working with the optional email address for a user,
write a method that will take an optional value,
and list rows matching that value.

The method signature is:

~~~ scala
def filterByEmail(email: Option[String]) = ???
~~~

Assume we only have two user records: one with an email address of "dave@example.org",
and one with no email address.

We want `filterByEmail(Some("dave@example.org"))` to produce one row,
and `filterByEmail(None)` to produce two rows.

Tip: it's OK to use multiple queries.

<div class="solution">
We can decide on the query to run in the two cases from inside our application:

~~~ scala
def filterByEmail(email: Option[String]) =
  if (email.isEmpty) users
  else users.filter(_.email === email)
~~~

You don't always have to do everything at the SQL level.
</div>


#### Inside the Option

Build on the last exercise to match rows that start with the supplied optional value.
Recall that `Rep[String]` defines `startsWith`.

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

Not everyone has an email address, so perhaps when filtering it would be safer to only exclude rows that don't match our filter criteria.  That is, keep `NULL` addresses in the results.

Add Elena to the database...

~~~ scala
insert += User("Elena", Some("elena@example.org"))
~~~

...and modify `filterByEmail` so when we search for `Some("elena@example.org")` we only
exclude Dave, as he definitely doesn't match that address.

This time you can do this in one query.

<div class="solution">
This problem we can represent in SQL, so we can do it with one query:

~~~ scala
def filterByEmail(email: Option[String]) =
  users.filter(u => u.email.isEmpty || u.email === email)
~~~
</div>


#### Enforcement

What happens if you try adding a message for a user ID of `3000`?

For example:

~~~ scala
messages += Message(UserPK(3000L), "Hello HAL!", DateTime.now)
~~~


Note that there is no user in our example with an ID of 3000.
If you are using an editor rather than the REPL the file to open is
`chapter-05/src/main/scala/value_classes.scala`.



<div class="solution">
We get a runtime exception as we have violated referential integrity.
There is no row in the `user` table with a primary id of `3000`.
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
(messages.schema ++ users.schema ++ bills.schema).create
~~~

Additionally, provide queries to give the full details of users:

- who do have an outstanding bill; and
- who have no outstanding bills.

Hint: Slick provides `in` for SQL's `WHERE x IN (SELECT ...)` expressions.


<div class="solution">
There are a few ways to model this table regarding constraints and defaults.
Here's one way, where the default is on the database,
and the unique primary key is simply the user's `id`:

~~~ scala
case class Bill(userId: Long, amount: BigDecimal)

class BillTable(tag: Tag) extends Table[Bill](tag, "bill") {
  def userId = column[Long]("user", O.PrimaryKey)
  def amount = column[BigDecimal]("dollars", O.Default(12.00))
  def * = (userId, amount) <> (Bill.tupled, Bill.unapply)
  def user = foreignKey("fk_bill_user", userId, users)  ↩
                       (_.id, onDelete=ForeignKeyAction.Restrict)
}

lazy val bills = TableQuery[BillTable]
~~~

Exercise the code as follows:

~~~ scala
bills += Bill(daveId, 12.00)
println(exec(bills.result)

// Unique index or primary key violation:
// exec(bills += Bill(daveId, 24.00))

// Referential integrity constraint violation: "fk_bill_user:
// exec(users.filter(_.name === "Dave").delete)

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


## Custom Column Mappings

We want to work with types that have meaning to our application.
This means converting data from the simple types the database uses
to something more developer-friendly.

We've already seen Slick's ability to map
tuples and `HList`s of columns to case classes.
However, so far the fields of our case classes
have been restricted to simple types such as
`Int` and `String`,

Slick also lets us control how individual columns are mapped to Scala types.
For example, perhaps we'd like to use
[Joda Time][link-jodatime]'s `DateTime` class
for anything date and time related.
Slick doesn't provide native support for Joda Time,
but it's painless for us to implement it via Slick's
`ColumnType` type class:

```tut:book
import java.sql.Timestamp
import org.joda.time.DateTime
import org.joda.time.DateTimeZone.UTC

object CustomColumnTypes {
  implicit val jodaDateTimeType =
    MappedColumnType.base[DateTime, Timestamp](
      dt => new Timestamp(dt.getMillis),
      ts => new DateTime(ts.getTime, UTC)
    )
}
```

What we're providing here is two functions:

- one from a `DateTime` to
  a database-friendly `java.sql.Timestamp`; and

- one that does the reverse, taking a `Timestamp`
  and converting it to a `DataTime`.

Once we have declared this custom column type,
we are free to create columns containing `DateTimes`:

```tut:book
case class Message(
  senderId  : Long,
  content   : String,
  timestamp : DateTime,
  id        : Long = 0L)

class MessageTable(tag: Tag) extends Table[Message](tag, "message") {

  // Bring our implicit conversions into scope:
  import CustomColumnTypes._

  def id        = column[Long]("id", O.PrimaryKey, O.AutoInc)
  def senderId  = column[Long]("sender")
  def content   = column[String]("content")
  def timestamp = column[DateTime]("timestamp")

  def * = (senderId, content, timestamp, id) <>
    (Message.tupled, Message.unapply)
}

lazy val messages      = TableQuery[MessageTable]
lazy val insertMessage = messages returning messages.map(_.id)
```


<div class="callout callout-info">
**Reset Your Database**

If you've been following along in the REPL,
by now you're going to have a bunch of tables and rows.
Now is a good time to remove all of that.

You can exit the REPL and restart it.
H2 is holding the data in memory,
so turning it on and off again is one way to reset your database.

Alternatively, you can use an action:

```tut:book
val schemas = (users.schema ++
  messages.schema          ++
  occupants.schema         ++
  rooms.schema)

exec(schemas.drop)
```
</div>


Our modified definition of `MessageTable` allows
us to work directly with `Message`s containing `DateTime` timestamps,
without having to do cumbersome type conversions by hand:

```tut:book
val program = for {
  _ <- messages.schema.create
  _ <- users.schema.create
  daveId <- insertUser += User(None, "Dave")
  msgId  <- insertMessage += Message(
    daveId,
    "Open the pod bay doors, HAL.",
    DateTime.now)
} yield msgId

val msgId = exec(program)
```

Fetching the database row will automatically convert the `timestamp` field into the `DateTime` value we expect:

```tut:book
exec(messages.filter(_.id === msgId).result)
```

This model of working with semantic types is
immediately appealing to Scala developers.
We strongly encourage you to use `ColumnType` in your applications,
to help reduce bugs and let Slick take care of cumbersome type conversions.


### Value Classes {#value-classes}

We are currently using `Long`s to model primary keys.
Although this is a good choice at a database level,
it's not great for our application code.

The problem is we can make silly mistakes,
such as trying to look up a `User` by primary key using the primary key from a `Message`.
They are both `Long`s, but trying to compare them makes no sense.
And yet the code would compile, and could possibly return a result.
But it's likely to be the wrong result.

We can prevent these kinds of problems using types.
The essential approach is to model primary keys
using [value classes][link-scala-value-classes]:

```tut:book
case class MessagePK(value: Long) extends AnyVal
case class UserPK(value: Long) extends AnyVal
```

A value class is a compile-time wrapper around a value.
At run time, the wrapper goes away,
leaving no allocation or performance overhead[^vcpoly] in our running code.

[^vcpoly]: It's not totally cost free: there [are situations where a value will need allocation][link-scala-value-classes], such as when passed to a polymorphic method.

To use a value class we need to provide Slick with `ColumnType`s
to use these types with our tables.
This is the same process we used for Joda Time `DateTime`s:

```tut:book
implicit val messagePKColumnType =
  MappedColumnType.base[MessagePK, Long](_.value, MessagePK(_))

implicit val userPKColumnType =
   MappedColumnType.base[UserPK, Long](_.value, UserPK(_))
```

Defining all these type class instances can be time consuming,
especially if we're defining one for every table in our schema.
Fortunately, Slick provides a short-hand called `MappedTo`
to take care of this for us:

```tut:book
case class MessagePK(value: Long) extends AnyVal with MappedTo[Long]
case class UserPK(value: Long) extends AnyVal with MappedTo[Long]
```

When we use `MappedTo` we don't need to define a separate `ColumnType`.
`MappedTo` works with any class that:

 - has a method called `value` that
   returns the underlying database value; and

 - has a single-parameter constructor to
   create the Scala value from the database value.

Value classes are a great fit for the `MappedTo` pattern.

Let's redefine our tables to use our custom primary key types.
We will convert `User`...

```tut:book
case class User(name: String, id: UserPK = UserPK(0L))

class UserTable(tag: Tag) extends Table[User](tag, "user") {
  def id   = column[UserPK]("id", O.PrimaryKey, O.AutoInc)
  def name = column[String]("name")
  def * = (name, id) <> (User.tupled, User.unapply)
}

lazy val users = TableQuery[UserTable]
lazy val insertUser = users returning users.map(_.id)
```

...and `Message`:

```tut:book
case class Message(
  senderId : UserPK,
  content  : String,
  id       : MessagePK = MessagePK(0L))

class MessageTable(tag: Tag) extends Table[Message](tag, "message") {
  def id        = column[MessagePK]("id", O.PrimaryKey, O.AutoInc)
  def senderId  = column[UserPK]("sender")
  def content   = column[String]("content")

  def * = (senderId, content, id) <> (Message.tupled, Message.unapply)

  def sender = foreignKey("sender_fk", senderId, users) (_.id, onDelete=ForeignKeyAction.Cascade)
}

lazy val messages      = TableQuery[MessageTable]
lazy val insertMessage = messages returning messages.map(_.id)
```

Notice how we're able to be explicit:
the `User.id` and `Message.senderId` are `UserPK`s
and the `Message.id` is a `MessagePK`.

We can lookup values if we have the right kind of key:

```tut:book
users.filter(_.id === UserPK(0L))
```

...but if we accidentally try to mix our primary keys, we'll find we cannot:

```tut:book:fail
users.filter(_.id === MessagePK(0L))
```

Values classes are a low-cost way to make code safer and more legible.
The amount of code required is small,
however for a large database it can still be an overhead.
We can either use code generation to overcome this,
or generalise our primary key type by making it generic:

```tut:book
// Inside an object to compile in the REPL:
object GenericPKModule {
  final case class PK[A](value: Long) extends AnyVal with MappedTo[Long]

  case class User(
    name : String,
    id   : PK[UserTable])

  class UserTable(tag: Tag) extends Table[User](tag, "user") {
    def id    = column[PK[UserTable]]("id", O.AutoInc, O.PrimaryKey)
    def name  = column[String]("name")

    def * = (name, id) <> (User.tupled, User.unapply)
  }

  lazy val users = TableQuery[UserTable]

  val exampleQuery = 
    users.filter(_.id === PK[UserTable](0L))
}
```

With this approach we achieve type safety
without the boiler plate of many primary key type definitions.
Depending on the nature of your application,
this may be convenient for you.

The general point is that we can use the whole of the Scala type system
to represent primary keys, foreign keys, rows, and columns from our database.
This is enormously valuable and should not be overlooked.


### Modelling Sum Types

We've used case classes extensively for modelling data.
Using the language of _algebraic data types_,
case classes are "product types"
(created from conjunctions of their field types).
The other common form of algebraic data type is known as a _sum type_,
formed from a _disjunction_ of other types.
We'll look at modelling these now.

As an example let's add a flag to our `Message` class
to model messages as important, offensive, or spam.
The natural way to do this is establish a sealed trait
and a set of case objects:

```tut:book
sealed trait Flag
case object Important extends Flag
case object Offensive extends Flag
case object Spam extends Flag

case class Message(
  senderId : UserPK,
  content  : String,
  flag     : Option[Flag] = None,
  id       : MessagePK = MessagePK(0L))
```

There are a number of ways we could represent the flags in the database.
For the sake of the argument, let's use characters: `!`, `X`, and `$`.
We need a new custom `ColumnType` to manage the mapping:

```tut:book
implicit val flagType =
  MappedColumnType.base[Flag, Char](
    flag => flag match {
      case Important => '!'
      case Offensive => 'X'
      case Spam      => '$'
    },
    code => code match {
      case '!' => Important
      case 'X' => Offensive
      case '$' => Spam
    })
```

This is similar to the enumeration pattern from the last set of exercises.
In this case, however, the compiler can ensure we've covered all the cases.
If we add a new flag (`OffTopic` perhaps),
the compiler will issue warnings
until we add it to our `Flag => Char` function.
We can turn these compiler warnings into errors
by enabling the Scala compiler's `-Xfatal-warnings` option,
preventing us shipping the application until we've covered all bases.

Using `Flag` is the same as any other custom type:

```tut:book
class MessageTable(tag: Tag) extends Table[Message](tag, "message") {
  def id       = column[MessagePK]("id", O.PrimaryKey, O.AutoInc)
  def senderId = column[UserPK]("sender")
  def content  = column[String]("content")
  def flag     = column[Option[Flag]]("flag")

  def * = (senderId, content, flag, id) <> (Message.tupled, Message.unapply)

  def sender = foreignKey("sender_fk", senderId, users)(_.id, onDelete=ForeignKeyAction.Cascade)
}

lazy val messages = TableQuery[MessageTable]
```

We can insert a message with a flag easily:

```tut:book
val halId = UserPK(1L)

messages += Message(halId, "Just kidding - come on in! LOL.", Some(Important))
```

We can also query for messages with a particular flag.
However, we need to give the compiler a little help with the types:

```tut:book
messages.filter(_.flag === (Important : Flag))
```

The _type annotation_ here is annoying.
We can work around it in two ways:

First, we can define a "smart constructor" method
for each flag that returns it pre-cast as a `Flag`:

```tut:book
object Flags {
  val important : Flag = Important
  val offensive : Flag = Offensive
  val spam      : Flag = Spam

  val query = messages.filter(_.flag === Flags.important).result
}
```

Second, we can define some custom syntax to
build our filter expressions:

```tut:book
implicit class MessageQueryOps(message: MessageTable) {
  def isImportant = message.flag === (Important : Flag)
  def isOffensive = message.flag === (Offensive : Flag)
  def isSpam      = message.flag === (Spam      : Flag)
}

messages.filter(_.isImportant).result.statements.head
```

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
case class User(name: String,
                userRole: UserRole = Regular,
                id: UserPK = UserPK(0L))

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

In this Chapter we covered a lot of Slick's features
for defining database schemas.
We went into detail about defining tables and columns,
mapping them to convenient Scala types,
adding primary keys, foreign keys, and indices,
and customising Slick's DDL SQL.
We also discussed writing generic code
that works with multiple database back-ends,
and how to structure the database layer of your application
using traits and self-types.

The most important points are:

- We can separate the specific profile for our database (H2, Postgres, etc).
  We assemble a database layer from a number of traits,
  leaving the profile as an abstract field
  that can be implemented at runtime.

- We can represent rows in a variety of ways: tuples, `HList`s,
  and arbitrary classes and case classes via the `<>` method.

- We can represent individual values in columns
  using arbitrary Scala data types
  by providing `ColumnType`s to manage the mappings.
  We've seen numerous examples supporting
  typed primary keys such as `UserPK`,
  sealed traits such as `Flag`, and
  third party classes such as `DateTime`.

- Nullable values are typically represented as `Option`s in Scala.
  We can either define columns to store `Option`s directly,
  or use the `?` method to map non-nullable columns to optional ones.

- We can define simple primary keys using `O.PrimaryKey`
  and compound keys using the `primaryKey` method.

- We can define `foreignKeys`,
  which gives us a simple way of linking tables in a join.
  More on this next chapter.

Slick's philosophy is to keep models simple.
We model rows as flat case classes, ignoring joins with other tables.
While this may seem inflexible at first,
it more than pays for itself in terms of simplicity and transparency.
Database queries are explicit and type-safe,
and return values of convenient types.

In the next chapter we will build on the foundations of
primary and foreign keys and look at writing more
complex queries involving joins and aggregate functions.
