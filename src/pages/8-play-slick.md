# Play Framework Intergration

You'll probably want to provide a way for people to interact with your lovely schema at some point --- possibly via the internet!
The [Play Framework][link-play] by Typesafe is a popular tool for developing just such an interface.
A plugin called [Play Slick][link-play-slick] makes doing so relatively painless.

<div class="callout callout-info">
**Run the Code**

By now, you know the drill.
You'll find the code for this section in the _play-slick-example_ folder over at [the associated GitHub repository][link-example].

From there start SBT and at the SBT `>` prompt run:

~~~
~run
~~~

You can then navigate to `http://localhost:9000/`, the tidle means any changes you will be automagically recompiled and you can refresh your browser and see the effect.
</div>

<!--  I don't this this is needed:
Let's look at the steps needed to integrate with Play using the Play Slick Plugin.
-->

## Dependencies

### Play

Play has it's own `sbt` plugin which adds the Play console, dependencies and functionality like live reloading.
To include this add the following to `plugins.sbt` in `project`:

~~~ scala
addSbtPlugin("com.typesafe.play" % "sbt-plugin" % "2.4.3")
~~~

<!-- THIS IS AN ASSUMPTION -->
To have the dependenices added our project we need to enable the plugin in`build.sbt`:

~~~ scala
lazy val root = (project in file(".")).enablePlugins(PlayScala)
~~~

If you interested in knowing more about Play there is an *excellent* book --- [Essential Play][link-essential-play].


### Play Slick Plugin

Now, onto the bits we care about --- The Play Slick plugin!
This is a library dependency added to our `build.sbt`:

~~~ scala
  "com.typesafe.play"   %% "play-slick"           % "1.1.0"
~~~

<div class="callout callout-info">
**Plugin Version**

The [Github project][link-play-slick-github] provides a handy table to determine which version of the plugin is appropriate for your project. For Essential Slick, we are using the latest available version of the plugin - `1.1.0`.
</div>


## Configuration

We need to make a few changes to the our `application.conf`, which originally looked like:

``` json
chapter05 = {
  connectionPool = disabled
  url = "jdbc:h2:mem:chapter05"
  driver = "org.h2.Driver"
  keepAliveConnection = true
}
```

Play Slick expects Slick datasources to be located under `slick.dbs` nodes.
By convention Play Slick expects the database to lablled `default`.
This can be changed, see [Database configuration][link-play-slick-dbconfig] for more information on how to override this.

``` json
slick {
  dbs {
    default {
      driver = "slick.driver.H2Driver$",
      db {
        driver   = "org.h2.Driver"
        url      = "jdbc:h2:mem:play"
      }
    }
  }
}
```

It is worth noting we needed to declare both the JDBC and Slick drivers.

###Scala changes

Let's review our schema implementation:

``` scala

  trait Profile {
    val profile: slick.driver.JdbcProfile
  }

  trait Tables {
    this: Profile =>

    import profile.api._

....
  }
  case class Schema(val profile: JdbcProfile) extends Tables with Profile
```

We have defined a `trait` to hold our slick profile and mixed this into our `Tables` definitions as a self type --- giving us access to the contents of the  profile.
We bring the `Profile` and `Tables` traits together in our `Schema` case class which provides a concrete implementation of the profile.
This is sometimes known as the cake pattern ---  less a bakery of doom and more a boulangerie of tastiness, at least in our case.
<!-- Feel free to remove the last sentence, it tickled me at the time. -->


Using Play Slick we will replace how we signal the expectation the `Tables` trait needs a Slick Profile, using the Play Slick trait `HasDatabaseConfig`.
We'll also need to update our import, we can see both below:

``` scala
  trait Tables {
    this: HasDatabaseConfig[JdbcProfile] =>

    import driver.api._
```

`HasDatabaseConfig` is doing a little more than our `Profile` case class,
it provides access to our database via `db` as well as the Slick profile via `driver`.

Our next change, is a little larger, but is mostly content shuffling.
The recipe for our cake has changed a little,
our `Schema` is no longer a case class, but a case object.
This is because we are no longer passing in a Profile,
but rather mixing in the `HasDatabaseConfig` trait.
We are also providing a way to get a concrete implemenation of `DatabaseConfig`,
using  `DatabaseConfigProvider`!

``` scala
  case object Schema extends HasDatabaseConfig[JdbcProfile] with Tables {
    //We use DatabaseConfigProvider to retrieve a database config
    protected val dbConfig = DatabaseConfigProvider.get[JdbcProfile](Play.current)

    //and import the appropriate driver API
    import driver.api._
```

What is happening in the above snippet?
We have provide `HasDatabaseConfig` with a profile, by overriding the value `dbConfig`.
`DatabaseConfigProvider` is used to retrieve a DatabaseConfig based on `application.conf`.

<div>
**DatabaseConfigProvider**

`Play.current` - is an implicit parameter, and therefore doesn't need to be supplied.
It does however help us grok where our database configuration from.
`Play` provides access to Play's global features,
`current` the current `Application` instance - meta information about the currently running application,
including configuration - `application.conf`.

<!-- **TODO:Jesus, wept taht was long winded.**-->
</div>

Finally, we need to provide access to runnable versions of our database queries in our `Schema` case object.

~~~ scala
    def populate    = db.run(schemaPopulate)
    def msgs        = db.run(namedMessages.result)
~~~

With this all in place, we can start using slick in our play application!

** Note **

Our `Profile` trait and `Tables` self type are no longer needed and can be removed.


### Calling Slick

Let's populate the schema as we have done throughout the book with the standard converstation.

``` scala
object Global extends GlobalSettings {

  //When the application starts up, populate the schema.
  override def onStart(app: Application) = Await.result(Schema.populate, Duration.Inf)

}
```

And, provide a way for people to view the messages:


``` scala
object Application extends Controller {

  //Display index page
  def index = Action { Ok(views.html.index()) }


  //Don't construct your JSON via tuples, use case classes and an encoder.
  def messages = Action.async  {
    Schema.msgs.map{s =>
      Ok(
        JsArray(s.map(t =>Json.obj("sender" -> t._1, "content" -> t._2)))
        )
    }
  }

}
```

As the Play Slick plugin has integrated Slick with Plays lifecycle we don't need to worry about sessions.
