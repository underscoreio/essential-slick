## Custom Types

~~~ scala
class SupplierId(val value: Int) extends AnyVal

case class Supplier(id: SupplierId, name: String,
 city: String)

implicit val supplierIdType = MappedColumnType.base
 [SupplierId, Int](_.value, new SupplierId(_))

class Suppliers(tag: Tag) extends
 Table[Supplier](tag, "SUPPLIERS") {
 def id = column[SupplierId]("SUP_ID", ...)
 ...
}
~~~


~~~ scala
class SupplierId(val value: Int) extends MappedTo[Int]

case class Supplier(id: SupplierId, name: String,
 city: String)

class Suppliers(tag: Tag) extends
 Table[Supplier](tag, "SUPPLIERS") {
 def id = column[SupplierId]("SUP_ID", ...)
 ...
}
~~~




## Dates and Time

Joda! See https://mackler.org/LearningSlick2/



