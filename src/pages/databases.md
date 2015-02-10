# Using Different Database Products {#altdbs}

As mentioned during the introduction H2 is used throughout the book for examples. However Slick also supports PostgreSQL, MySQL, Derby, SQLite, and Microsoft Access. To work with DB2, SQL Server or Oracle you need a commercial license. These are the closed source _Slick Drivers_ known as the _Slick Extensions_.

## Changes

If you want to use a different database for the exercises in the book,
you will need to make changes detailed below.

In summary you will need to ensure that:

 * a database is available with the correct name;
 * the `build.sbt` file has the correct dependency;
 * the correct JDBC driver is referenced in the code; and
 * the correct Slick driver is used.

Each chapter uses its own database---so these steps will need to be applied for each chapter.

We've given detailed instructions for two populate databases below.

## PostgreSQL

If it is not currently installed, it can be downloaded from the [PostgreSQL website][link-postgres-download].

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

Replace `Database.forURL` parameters with:

~~~ scala
"jdbc:postgresql:chapter-01", user="essential", password="trustno1", driver="org.postgresql.Driver"
~~~

### Update Slick Driver

Change the import from:

~~~ scala
import scala.slick.driver.H2Driver.simple._
~~~

to

~~~ scala
import scala.slick.driver.PostgresDriver.simple._
~~~

## MySQL

If it is not currently installed, it can be downloaded from the [MySQL website][link-mysql-download].

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

~~~ scala
"jdbc:mysql://localhost:3306/chapter-01&useUnicode=true&amp;characterEncoding=UTF-8&amp;autoReconnect=true",
user="essential", password="trustno1", driver="com.mysql.jdbc.Driver"
~~~

### Update Slick Driver

Change the import from

~~~ scala
import scala.slick.driver.H2Driver.simple._
~~~

to

~~~ scala
import scala.slick.driver.MySQLDriver.simple._
~~~

