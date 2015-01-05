## Queries Compose

Reuse. Only runs when you say.  Keep to a `Query` for as long as possible.


## Drop and Take

planets.drop(2).take(3)


## Unions

(q1 union q2).run without dups, or ++ for union all


## Calling Functions

~~~ scala
  val dayOfWeek = SimpleFunction[Int]("day_of_week")

    val q1 = for {
      (dow, q) <- salesPerDay.map(s => (dayOfWeek2(s.day), s.count)).groupBy(_._1)
    } yield (dow, q.map(_._2).sum)
~~~


## Query Extensions

E.g., pagination or byName("Mars")




## Dynamic Queries

need to upper case everything??

~~~ scala
implict.... dynamicSort(keys: String*) : Query[T,E] = {
  keys match {
    case nil = query
    case h :: t =>
      dynamicSortImpl(t).sortBy( table => )
      // split h on . to get asc desc
    h match {
      case name :: Nil =>  table.column[String](name).asc
      case _ => ???

  }
}
}
~~~

danger... access to user supplied input!!

~~~ scala
dynamicSort("street.desc", "city.desc")
~~~


## Aggregations

counts, grouping and all that.

max, min, sum, avg

broupBy

## Virtual Columns and Server Side Casts

def x = whatever

`asColumnOf[Double]`
