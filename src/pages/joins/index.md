# Joins

insert diagram here

~~~ scala
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

  case class Moon(name: String, planetId: Long, id: Long=0L)

  class MoonTable(tag: Tag) extends Table[Moon](tag, "moon") {
    def id = column[Long]("id", O.PrimaryKey, O.AutoInc)
    def name = column[String]("name")
    def planetId = column[Long]("planet_id")

    def * = (name, planetId, id) <> (Moon.tupled, Moon.unapply)

    def planet = foreignKey("planet_fk", planetId, planets)(_.id)

  }

  lazy val moons = TableQuery[MoonTable]
}
~~~

Now that we have more tables, our automatic schema creation code becomes a little more complicated:

~~~ scala
def exists[T <: Table[_]](table: TableQuery[T])(implicit session: Session) : Boolean =
  MTable.getTables(table.baseTableRow.tableName).firstOption.isDefined

def dropAndCreate(implicit session: Session) : Unit = {
  if (exists(moons)) moons.ddl.drop
  if (exists(planets)) planets.ddl.drop
  (planets.ddl ++ moons.ddl).create
}
~~~

Although `(planets.ddl ++ moons.ddl).drop` is smart enough to drop tables and constraints in the correct order, it will also try to drop tables that do not exists. This leads to a runtime error. To avoid that, we test and drop.

The resulting table creation SQL will be:


~~~ sql
create table "planet" (
  "name" VARCHAR(254) NOT NULL,
  "distance_au" DOUBLE PRECISION NOT NULL,
  "id" SERIAL NOT NULL PRIMARY KEY
)

create table "moon" (
  "name" VARCHAR(254) NOT NULL,
  "planet_id" BIGINT NOT NULL,
  "id" SERIAL NOT NULL PRIMARY KEY
)

alter table "moon" add constraint "planet_fk" foreign key("planet_id")
~~~

Inserting data does not change, except that we need to query for the ID of the planets for the moon-to-planet relationship:


~~~ sql
db.withSession {
  implicit session =>

    // Create the database table:
    dropAndCreate

    // Populate Planets:

    planets ++= Seq(
      Planet("Earth", 1.0)
      Planet("Mercury",  0.4),
      Planet("Venus",    0.7),
      Planet("Mars" ,    1.5),
      Planet("Jupiter",  5.2),
      Planet("Saturn",   9.5),
      Planet("Uranus",  19.0),
      Planet("Neptune", 30.0)
    )

    // We want to look up a planet by name to create the association
    def idOf(planetName: String) : Long =
      planets.filter(_.name === planetName).map(_.id).first

    val earthId = idOf("Earth")
    val marsId = idOf("Mars")

    moons ++= Seq(
      Moon("The Moon", earthId),
      Moon("Phobos", marsId),
      Moon("Deimos",  marsId)
    )
}
~~~

For the moons we execute two queries for the planet IDs, then three inserts.  The resulting database is:

~~~ sql
core-slick=# select * from moon;
   name   | planet_id | id
~~~~~~--+~~~~~~---+~~~
 The Moon |         1 |  1
 Phobos   |         4 |  2
 Deimos   |         4 |  3
(3 rows)
~~~

## Explicit Joins

~~~ scala
val query = for {
  (planet, moon) <- moons innerJoin planets on (_.planetId === _.id)
} yield (planet.name, moon.name)
~~~


~~~ sql
select x2."name", x3."name" from (select x4."name" as "name", x4."planet_id" as "planet_id", x4."id" as "id" from "moon" x4) x2 inner join (select x5."name" as "name", x5."distance_au" as "distance_au", x5."id" as "id" from "planet" x5) x3 on x2."planet_id" = x3."id"
~~~

## Implicit Joins

~~~ scala
val query = for {
  p <- planets
  m <- moons
  if m.planetId === p.id
} yield (p.name, m.name)
~~~

~~~ sql
select x2."name", x3."name" from "planet" x2, "moon" x3 where x3."planet_id" = x2."id"

~~~

t1.join(t2).on(condition)



