# Preface {-}

## What is Slick? {-}

[Slick][link-slick] is a Scala library for working with relational databases.
That means it allows you to model a schema, run queries, insert data, and update data.

Using Slick you write queries in Scala and they are type checked by the compiler.
This makes working with a database like working with regular Scala collections.

We've seen that developers using Slick for the first time often need help getting the most from it.
For example, key concepts that need to be known include:

- _queries_: which compose using combinators such as `map`, `flatMap`, and `filter`;

- _actions_: the things you can run against a database, which themselves compose; and

- _futures_: which are the result of actions, and also support a set of combinators.

We've produced _Essential Slick_ as a guide for those who want to get started using Slick.
This material is aimed at beginner-to-intermediate Scala developers. You need:

* a working knowledge of Scala
  (we recommend [Essential Scala][link-essential-scala] or an equivalent book);

* experience with relational databases
  (familiarity with concepts such as rows, columns, joins, indexes, SQL); and

* an installed JDK 8 or later, along with a programmer's text editor or IDE.

The material presented focuses on Slick version 3.2. Examples use [H2][link-h2-home] as the relational database.

## How to Contact Us {-}

You can provide feedback on this text via:

* [issues][link-book-issues] and [pull requests][link-book-pr] on the [source repository][link-book-repo] for this text;

* [our Gitter channel][link-underscore-gitter]; or

* email to [hello@underscore.io][link-email-underscore] using the subject line of "Essential Slick".

The [Underscore Newsletter][link-newsletter] contains announcements regarding this and other publications from Underscore.

You can follow us on Twitter as [\@underscoreio][link-twitter-underscore].

