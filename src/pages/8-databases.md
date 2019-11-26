# Using Different Database Products {#altdbs}

As mentioned during the introduction, H2 is used throughout the book for examples.
However Slick also supports PostgreSQL, MySQL, Derby, SQLite, Oracle, and Microsoft Access.

There was a time when you needed a commercial license from Lightbend to use Slick in production with Oracle, SQL Server, or DB2.
This restriction was removed in early 2016[^slick-blog-open].
However, there was an effort to build free and open profiles, resulting in the FreeSlick project.
These profiles continue to be available, and you can find out more about this from the [FreeSlick GitHub page](https://github.com/smootoo/freeslick).

[^slick-blog-open]: [https://scala-slick.org/news/2016/02/01/slick-extensions-licensing-change.html](https://scala-slick.org/news/2016/02/01/slick-extensions-licensing-change.html).

## Changes

If you want to use a different database for the exercises in the book,
you will need to make changes detailed below.

In summary you will need to ensure that:

 * you have installed the database (details beyond the scope of this book);
 * a database is available with the correct name;
 * the `build.sbt` file has the correct dependency;
 * the correct JDBC driver is referenced in the code; and
 * the correct Slick profile is used.

Each chapter uses its own database---so these steps will need to be applied for each chapter.

We've given detailed instructions for two populate databases below.

## PostgreSQL

### Create a Database

Create a database named `chapter-01` with user `essential`. This will be used for all examples and can be created with the following:

~~~ sql
CREATE DATABASE "chapter-01" WITH ENCODING 'UTF8';
CREATE USER "essential" WITH PASSWORD 'trustno1';
GRANT ALL ON DATABASE "chapter-01" TO essential;
~~~

Confirm the database has been created and can be accessed:

~~~ bash
$ psql -d chapter-01 essential
~~~

### Update `build.sbt` Dependencies

Replace

~~~ scala
"com.h2database" % "h2" % "1.4.185"
~~~

with

~~~ scala
"org.postgresql" % "postgresql" % "9.3-1100-jdbc41"
~~~

If you are already in SBT, type `reload` to load this changed build file.
If you are using an IDE, don't forget to regenerate any IDE project files.

### Update JDBC References

Replace `application.conf` parameters with:

~~~ json
chapter01 = {
  connectionPool      = disabled
  url                 = jdbc:postgresql:chapter-01
  driver              = org.postgresql.Driver
  keepAliveConnection = true
  users               = essential
  password            = trustno1
}
~~~

### Update Slick Profile

Change the import from

```scala
slick.jdbc.H2Profile.api._
```

to

```scala
slick.jdbc.PostgresProfile.api._
```


## MySQL

### Create a Database

Create a database named `chapter-01` with user `essential`. This will be used for all examples and can be created with the following:

~~~ sql
CREATE USER 'essential'@'localhost' IDENTIFIED BY 'trustno1';
CREATE DATABASE `chapter-01` CHARACTER SET utf8 COLLATE utf8_bin;
GRANT ALL ON `chapter-01`.* TO 'essential'@'localhost';
FLUSH PRIVILEGES;
~~~

Confirm the database has been created and can be accessed:

~~~ bash
$ mysql -u essential chapter-01 -p
~~~

### Update `build.sbt` Dependencies

Replace

~~~ scala
"com.h2database" % "h2" % "1.4.185"
~~~

with

~~~ scala
"mysql" % "mysql-connector-java" % "5.1.34"
~~~

If you are already in SBT, type `reload` to load this changed build file.
If you are using an IDE, don't forget to regenerate any IDE project files.

### Update JDBC References

Replace `Database.forURL` parameters with:

~~~ json
chapter01 = {
  connectionPool      = disabled
  url                 = jdbc:mysql://localhost:3306/chapter-01
                                      &useUnicode=true
                                      &amp;characterEncoding=UTF-8
                                      &amp;autoReconnect=true
  driver              = com.mysql.jdbc.Driver
  keepAliveConnection = true
  users               = essential
  password            = trustno1
}
~~~

Note that we've formatted the `connectionPool` line to make it legible.
In reality all those `&` parameters will be on the same line.


### Update Slick DriverProfile

Change the import from 

```scala
slick.jdbc.H2Profile.api._
```

to

```scala
slick.jdbc.MySQLProfile.api._
```
