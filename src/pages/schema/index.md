## Structuring the Schema


~~~ scala
object Tables extends {
  val profile = scala.slick.driver.PostgresDriver
} with Tables

trait Tables {

  val profile: scala.slick.driver.JdbcProfile
  import profile.simple._

  class Planet(tag: Tag) extends Table[(Int,String,Double)](tag, "planet") {
    def id = column[Int]("id", O.PrimaryKey, O.AutoInc)
    def name = column[String]("name")
    def distance = column[Double]("distance_au")
    def * = (id, name, distance)
  }

  lazy val planets = TableQuery[Planet]
}

// Our application:

import Tables._

// session, queries, go here...
~~~

### Connecting, Transactions, Sessions

While we're restructuring, we'll move the `Database.forURL` code into a method:
[source,scala]
~~~ scala
object Tables extends {
    val profile = scala.slick.driver.PostgresDriver
} with Tables {
  val db = Database.forURL("jdbc:postgresql:core-slick",
               user="core", password="trustno1",
               driver = "org.postgresql.Driver")
}
~~~

This will allow us to run `db.withSession` anywhere we want to interact with the database.

You can think of a session as the connection to the database. You need it anytime you want to run a query, or lookup database metadata.

The session comes from a `Database` which you can create in a number of ways:

* `forDataSource` - when working with a `javax.sql.DataSource`

* `forName` - if you are using JNDI.

* `forURL` - which is what we've been using.

The `withSession` method ensures that the session is closed once the method returns. This means you don't have to worry about closing connections.  It also means you must not "leak sessions" out of the method, for example by returning the session object (even inside a `Future`).

Inside a session, each interaction with the database happens in "auto commit" mode.  If you want to manage transactions yourself, use the session object to create a transaction:


~~~ scala
session.withTransaction {
 // Queries here as usual
}
~~~

The transaction will commit at the end of the block unless an exception is thrown, or you call `session.rollback` at any point.


### Exercises

* Create a transaction to delete Earth, but rollback inside the transaction.  Check the database still contains Earth.

* In the following code, will you see "Almost done..." printed?


~~~ scala
session.withTransaction {
    planets.delete
    session.rollback()
    println("Almost done...")
}
~~~



