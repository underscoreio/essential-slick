## Getting Started

This section will cover setting up an environment so as to be able to execute examples and particpate in the exercises.  Commands to be executed on the filesystem are assumed to be rooted in a directory `essential-slick`.

### Requirements

    * Postgres 9
    * JDK 7
    * SBT 13.5

### Database Configuration

As mentioned during the introduction PostgresSQL version 9 is used throughout the book for examples. If it is not currently installed, it can be downloaded from the [Postgres][link-postgres-download] website.


A database named `essential-slick` with user `essential` will be used for all examples and can be created with the following:

~~~ sql
CREATE DATABASE "essential-slick" WITH ENCODING 'UTF8';
CREATE USER "essential" WITH PASSWORD 'trustno1';
GRANT ALL ON DATABASE "essential-slick" TO essential;
~~~

Confirm the database has been created and can be accessed:

~~~ bash
$ psql -d essential-slick essential
~~~

<div class="callout callout-info">
Slick supports PostgreSQL, MySQL, Derby, H2, SQLite, and Microsoft Access.

To work with DB2, SQL Server or Oracle you need a commercial license. These are the closed source _Slick Drivers_ known as the _Slick Extensions_.
</div>


### An SBT Project

To use Slick create a regular Scala project and reference the Slick dependencies.  This can be accomplished using SBT by creating a file `build.sbt` with the contents below:

~~~ scala
name := "essential-slick"

version := "1.0"

scalaVersion := "2.11.4"

libraryDependencies += "com.typesafe.slick" %% "slick" % "2.0.3"

libraryDependencies += "ch.qos.logback" % "logback-classic" % "1.1.2"

libraryDependencies += "org.postgresql" % "postgresql" % "9.3-1101-jdbc41"
~~~


(To do: explain the dependencies)


Once `build.sbt` is created, SBT can be run and the dependencies will be fetched.

<div class="callout callout-info">
If working with IntelliJ IDEA or the Eclipse Scala IDE, the _essential-slick-example_ project includes the plugins to generate the IDE project files:

~~~ scala
sbt> eclipse
~~~

or

~~~ scala
sbt> gen-idea
~~~~

The projects can then be opened in an IDE.  For Eclipse, this is _File -> Import -> Existing Project_ menu.
</div>
