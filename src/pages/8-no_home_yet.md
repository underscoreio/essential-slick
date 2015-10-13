#  No Home Yet
## Play framework intergration

You'll probably want to provide a way for people to interact with your lovely schema at some point,
possibly via the internet!
The [Play Framework][link-play] by Typesafe is a popular tool for developing just such interfaces.
A plugin called [Play Slick][link-play-slick] makes it relatively painless to integrate.


Let's look at the steps needed to in integrate our schema into a Play application with the Play Slick plugin.  Select the appropriate version of the plugin to use, based on the Play, Slick and Scala versions you are using.
The [Github project][link-play-slick-github] provides a handy table for you to do this.

Once that is determined, we'll need a few Play specifics.
Add the following to `plugins.sbt`:

~~~ scala
// Use the Play sbt plugin for Play projects
addSbtPlugin("com.typesafe.play" % "sbt-plugin" % "2.4.3")
~~~

Then we can enable the plugin in `build.sbt`:

~~~ scala
// Play
lazy val root = (project in file(".")).enablePlugins(PlayScala)
~~~

<div class="callout callout-info">
**This is not a play tutorial**
There is however an *excellent* book on play, called [Essential Play][link-essential-play].
</div>


Now, onto the bits we care about - The Play Slick plugin!
Add this to your `build.sbt` library dependencies:

~~~ scala
  "com.typesafe.play"   %% "play-slick"           % "1.1.0"
~~~

### Configuration

We need to make a few changes to the our `application.conf`, which originally looked like:

``` json
chapter05 = {
  connectionPool = disabled
  url = "jdbc:h2:mem:chapter05"
  driver = "org.h2.Driver"
  keepAliveConnection = true
}
```
**TODO is nodes the correct term?**

Play Slick expects slick datasources to be located under `slick.dbs` nodes.
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
        user     = "sa"
        password = ""
      }
    }
  }
}
```

It is worth noting we needed to declare both the JDBC and Slick drivers.

###Scala changes

Recall we used a self trait to signal we expected a `JDBCProfile` to be mixed in with our `Tables` trait?
Play Slick provides it's own way to signal the expectation, via the trait `HasDatabaseConfig[P <: BasicProfile]`.
We provide `HasDatabaseConfig` with a profile, by overriding the value `dbConfig`.

``` scala
  `DatabaseConfigProvider.get[JdbcProfile](Play.current)`
```

What is happening in the above snippet?
Based on the type ascription we can deduce the `get` method will return a `DbConfig` of kind `JdbcProfile`.


`Play.current` - is an implicit parameter, and therefore doesn't need to be supplied.
It does however help us grok where our database configuration from.
`Play` provides access to Play's global features,
`current` the current `Application` instance - meta information about the currently running application,
including configuration - `application.conf`.

**TODO:Jesus, wept taht was long winded.**

Our `Profile` trait and `Tables` self type are no longer needed and can be removed.
Neither do we need our `Schema` case class, as we are mixing in `HasDatabaseConfig` with our `Tables` trait.




### Calling Slick

Let's populate the schema as we have done throughout the book with the standard converstation.



``` scala
object Global extends GlobalSettings {

  //When the application starts up, populate the schema.
  override def onStart(app: Application) = Await.result(Schema.populate, Duration.Inf)

}
```

As the Play Slick plugin has integrated Slick with Plays lifecycle we don't need to worry about

``` scala
object Application extends Controller {

  //Display index page
  def index = Action { Ok(views.html.index()) }

  //Send a stream of messages to the client.
  //Don't construct your JSON via tuples, use case classes and an encoder.
  //TODO: Why is this an array of array?
  def messages = Action.async  {
    Schema.msgs.map{s =>
      Ok(
        Json.arr(s.map(t =>Json.obj("sender" -> t._1, "content" -> t._2)))
        )
    }
  }

}
```










