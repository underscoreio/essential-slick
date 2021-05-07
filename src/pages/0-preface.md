# Preface {-}

## What is Slick? {-}

[Slick][link-slick] is a Scala library for working with relational databases.
That means it allows you to model a schema, run queries, insert data, and update data.

Using Slick, you can write queries in Scala, giving you typed-checked database access.
The style of queries makes working with a database similar to working with regular Scala collections.

We've seen that developers using Slick for the first time often need help getting the most from it.
For example, you need to know a few key concepts, such as:

- _queries_: which compose using combinators such as `map`, `flatMap`, and `filter`;

- _actions_: the things you can run against a database, which themselves compose; and

- _futures_: which are the result of actions, and also support a set of combinators.

We've produced _Essential Slick_ as a guide for those who want to get started using Slick.
This material is aimed at beginner-to-intermediate Scala developers. You need:

* a working knowledge of Scala
  (we recommend [Essential Scala][link-essential-scala] or an equivalent book);

* experience with relational databases
  (familiarity with concepts such as rows, columns, joins, indexes, SQL);

* an installed JDK 8 or later, along with a programmer's text editor or IDE; and

* the [sbt][link-sbt] build tool.

The material presented focuses on Slick version 3.3. Examples use [H2][link-h2-home] as the relational database.

## How to Contact Us {-}

You can provide feedback on this text via:

* [issues][link-book-issues] and [pull requests][link-book-pr] on the [source repository][link-book-repo] for this text;

* [our Gitter channel][link-underscore-gitter]; or

* email to [hello@underscore.io][link-email-underscore] using the subject line of "Essential Slick".

## Getting help using Slick {-}

If you have questions about using Slick, ask a question on the [Slick Gitter channel][link-slick-gitter] or use the ["slick" tag at Stackoverflow][link-slick-so].


