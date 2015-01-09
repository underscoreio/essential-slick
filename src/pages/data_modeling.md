# Data modeling
*Objectives: (a) provide the right way to work with data in slick; (b) introducing more query examples (update and delete)*

Brief overview of chapter objectives.
- Use exercises and examples to define some more of the Schema.
  - start with User

## Rows

<!-- I'm going to ignore HList for the time being as they seem overly complicated and not essential.-->
We model rows of a table using either tuples or case classes. In either case, they contain the types of the columns we wish to expose.  Let's look a simple example of both, we'll define a `user` so we don't need to store their name in the `message` table.

~~~ scala
  final type  TupleUser = (Long,String)

  final case class CaseUser(id:Long,name:String)
~~~

Nothing very magical happening here. There is a little more typing involved in defining the case class, but we get a lot more meaning using case classes.  A little more to be defined in the table definition when using case classes, which we will look at in the next section.

_TODO: Talk about types?_

##Tables

Now we have a row, we can define the table it comes from.  Let's looks at the definition of the `User` table and walk through what is involved.

~~~ scala
  final class TupleUserTable(tag: Tag) extends Table[TupleUser](tag, "user") {
    def id = column[Long]("id", O.PrimaryKey, O.AutoInc)
    def name = column[String]("name")
    def * = (id, name)
  }
  final class UserTable(tag: Tag) extends Table[User](tag, "user") {
    def id = column[Long]("id", O.PrimaryKey, O.AutoInc)
    def name = column[String]("name")
    def * = (id, name) <> (User.tupled,User.unapply)
  }
~~~

We've defined two versions of the the `User` table, one using a tuple, the other a case class.  As you can there is little difference between the two, the kind the `Table` class and the definition of the `*` method, we'll come back to this.

First let's look at how this class relates to the database table.  The name of the table is given as a parameter, in this case the `String` "user" --- `Table[User](tag, "user")`. An optional schema name can also be provided, if required by your database.

Next we define methods for each of the tables columns. These call the method `column` with it's type, name and zero of more options. This is rather self explainitory --- `name` has the type `String` and is mapped to a column `name`. It has no options, we'll explore column in the rest of this chapter.

Finally, we come back to `*`. It is the only method we are required to implement. It defines the default projection for the table.  That is the row object we defined earlier. If we are not using tuples we need to define how Slick will map between our row and projection. We do this using the `<>` operator, supplying two methods --- one to wrap a returned tuple into our type and another to unwrap our type into a tuple. In the `User` example `User.tupled` takes a tuple and returns a User, while `User.unapply` takes a user and returns an `Option` of `(Long,String)`.


<div class="callout callout-info">
**Expose only what you need**

We can hide information by excluding it from our row definition. The default projection controls what is returned and it is driven by our row definition.

</div>


From now on, we will use case classes in our examples as they are easier to reason about.

#Null columns

  - optional
  - extend Message to add to for direct messages.

##Row and column control (autoinc etc)



##Primary keys & value classes

  - create a type for message content.

##Custom types & mapping

  - explain `when` in Message


##Example using date and time?

##Virtual columns and server-side casts here?

##Exercises