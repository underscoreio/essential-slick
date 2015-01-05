#  Using Case Classes


~~~ scala
object Tables extends {
  val profile = scala.slick.driver.PostgresDriver
} with Tables

trait Tables {

  val profile: scala.slick.driver.JdbcProfile
  import profile.simple._

  case class Planet(name: String, distance: Double, id: Long=0L)

  class PlanetTable(tag: Tag) extends Table[Planet](tag, "planet") {
    def id = column[Long]("id", O.PrimaryKey, O.AutoInc)
    def name = column[String]("name")
    def distance = column[Double]("distance_au")
    def * = (name, distance, id) <> (Planet.tupled, Planet.unapply)
  }

  lazy val planets = TableQuery[PlanetTable]
}

// Our application:

import Tables._

// session, queries, go here...
~~~

Initialisation pattern.

naming: PlanetRow, Planets v. Planet, PlanetTable


## Inserting data


~~~ scala
planets += Planet("Earth", 1.0)

planets ++= Seq(
  Planet("Mercury",  0.4),
  Planet("Venus",    0.7),
  Planet("Mars" ,    1.5),
  Planet("Jupiter",  5.2),
  Planet("Saturn",   9.5),
  Planet("Uranus",  19.0),
  Planet("Neptune", 30.0)
)
~~~


## Queries
