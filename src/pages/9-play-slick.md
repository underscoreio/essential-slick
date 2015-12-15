# Play Framework Integration

You'll probably want to provide a way for people to interact with your lovely schema at some point---possibly via the internet!
The [Play Framework][link-play] is a popular tool for developing just such an interface.
A plugin called [Play Slick][link-play-slick] makes doing so relatively painless.
The Play Slick plugin integrates Slick with Play's lifecycle, ensuring all resources are freed when an application is stopped.

## Overview

To use the plugin we need to make three changes:

 - sbt configuration,
 - application configuration, and
 - code.

 Don't panic, these are all small changes.

<div class="callout callout-info">
**Run the Code**

By now, you know the drill.
You'll find the code for this section in the _play-slick-example_ folder over at [the associated GitHub repository][link-example].

From there start SBT and at the SBT `>` prompt run:

~~~
~run
~~~

You can then navigate to `http://localhost:9000/`.  The tilde symbol means any changes you make will be automagically recompiled and you can refresh your browser and see the effect.
</div>


## sbt Configuration

We need to tell sbt about Play and the Play Slick plugin.


### Play

Play has its own sbt plugin which adds the following capabilities Play console,
dependencies and functionality such as live reloading to sbt.
To include this add the following to `plugins.sbt` in the `project` directory:

~~~ scala
addSbtPlugin("com.typesafe.play" % "sbt-plugin" % "2.4.3")
~~~

We also need to enable the plugin for a given project in `build.sbt`:

~~~ scala
lazy val root = (project in file(".")).enablePlugins(PlayScala)
~~~

If you interested in learning Play Underscore has an excellent book---[Essential Play][link-essential-play].


### Play Slick Plugin

Now, on to the bits we care about---The Play Slick plugin!
This is a library dependency added to our `build.sbt`:

~~~ scala
  "com.typesafe.play" %% "play-slick" % "1.1.0"
~~~

<div class="callout callout-info">
**Plugin Version**

The [project][link-play-slick-github] provides a handy table to determine which version of the plugin is appropriate for your project. For Essential Slick, we are using the latest available version of the plugin `1.1.0`.
</div>


## Application Configuration


Play Slick expects Slick datasources to be located under `slick.dbs` with the database to labeled `default`.
Leaving  `application.conf` as follows:

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

It is worth noting we needed to declare __both__ the JDBC and Slick drivers.
If you want to use a label other than `default` for a database,
the [Database configuration][link-play-slick-dbconfig] outlines how to do this.

###Code

Let's review our schema implementation:

``` scala

  trait Profile {
    val profile: slick.driver.JdbcProfile
  }

  trait Tables {
    this: Profile =>

    import profile.api._

    ...
  }
  case class Schema(val profile: JdbcProfile) extends Tables with Profile
```
<!--
TODO: Tables has changed names, update it from Dave's branch once merged in.
-->


We have defined a trait to hold our Slick profile and mixed this into our `Tables` definitions.
Giving us access to the contents of the profile.
We bring the `Profile` and `Tables` traits together in our `Schema` case class which provides a concrete implementation of the profile.
This is sometimes known as the cake pattern---less a bakery of doom and more a boulangerie of tastiness, at least in our case.
<!-- Feel free to remove the last sentence, it tickled me at the time. -->




Play Slick has its own self type for our `Tables` trait called `HasDatabaseConfig`:

``` scala
  trait Tables {
    this: HasDatabaseConfig[JdbcProfile] =>

    import driver.api._
```
__Note__: The import exposing the profile functionality has also changed.


`HasDatabaseConfig` is doing a little more than our `Profile` case class.
It also provides access to our database via the method `db` as well as the Slick profile via `driver`.

Our next change, is a little larger, but is mostly content shuffling.
The recipe for our cake has changed a little,
our `Schema` is no longer a case class, but a case object.
This is because we are no longer passing in a Profile,
but rather mixing in the `HasDatabaseConfig` trait.
We are also providing a way to get a concrete implementation of `DatabaseConfig`,
using  `DatabaseConfigProvider`.

``` scala
  case object Schema extends HasDatabaseConfig[JdbcProfile] with Tables {
    //We use DatabaseConfigProvider to retrieve a database config
    protected val dbConfig =
      DatabaseConfigProvider.get[JdbcProfile](Play.current)

    //and import the appropriate driver API
    import driver.api._
```

What is happening in the above snippet?
We have provided `HasDatabaseConfig` with a profile, by overriding the value `dbConfig`.
`DatabaseConfigProvider` is used to retrieve a DatabaseConfig based on `application.conf`.

### DatabaseConfigProvider

`Play` provides access to Play's global features,
`current` is the current `Application` instance.
This meta information about the currently running application,
including configuration `application.conf`.
`Play.current` is an implicit parameter and doesn't need to be supplied.
It does however help us grok where our database configuration is from.

Finally, we need to provide access to runnable versions of our database queries in our `Schema` case object.

~~~ scala
    def populate    = db.run(schemaPopulate)
    def msgs        = db.run(namedMessages.result)
~~~

With this all in place, we can start using Slick in our Play application!

**Note**

Our `Profile` trait and the `Tables` self type are no longer needed and can be removed.


### Calling Slick

Let's populate the schema as we have done throughout the book with the standard conversation.

``` scala
object Global extends GlobalSettings {

  //When the application starts up, populate the schema.
  override def onStart(app: Application) =
    Await.result(Schema.populate, Duration.Inf)

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

