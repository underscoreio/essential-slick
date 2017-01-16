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

* an installed JDK 8 or better, along with a programmer's text editor or IDE.

The material presented focuses on Slick version 3.1. Examples use [H2][link-h2-home] as the relational database.

## How to Contact Us {-}

You can provide feedback on this text via:

* [our Gitter channel][link-underscore-gitter]; or

* email to [hello@underscore.io][link-email-underscore] using the subject line of "Essential Slick".

The [Underscore Newsletter][link-newsletter] contains announcements regarding this and other publications from Underscore.

You can follow us on Twitter as [\@underscoreio][link-twitter-underscore].

## Acknowledgements {-}

Many thanks to [Renato Cavalcanti ][link-renato], [Dave Gurnell][link-twitter-dave], [Kevin Meredith][link-meredith], [Joseph Ottinger][link-ottinger], [Yann Simon][link-simon], [Trevor Sibanda][link-trevor], and the team at [Underscore][link-underscore] for their invaluable contributions and proof reading.

## Conventions Used in This Book {-}

This book contains a lot of technical information and program code. We use the following typographical conventions to reduce ambiguity and highlight important concepts:

### Typographical Conventions {-}

New terms and phrases are introduced in *italics*. After their initial introduction they are written in normal roman font.

Terms from program code, filenames, and file contents, are written in `monospace font`.

References to external resources are written as [hyperlinks][link-underscore]. References to API documentation are written using a combination of hyperlinks and monospace font, for example: [`scala.Option`][link-scala-option].

### Source Code {-}

Source code blocks are written as follows. Syntax is highlighted appropriately where applicable:

~~~ scala
object MyApp extends App {
  println("Hello world!") // Print a fine message to the user!
}
~~~

Some lines of program code are too wide to fit on the page. In these cases we use a *continuation character* (curly arrow) to indicate that longer code should all be written on one line. For example, the following code:

~~~ scala
println("This code should all be written ↩
  on one line.")
~~~

should actually be written as follows:

~~~ scala
println("This code should all be written on one line.")
~~~


### REPL Output {-}

We use Scala comments to show REPL output. For example:

~~~ scala
2 * 13
// res0: Int = 26
~~~

If you're following along with the REPL, and copy and paste from the book we hope this will be useful.
It means if you accidentally copy more than you intended, the REPL will ignore the commented output.

We use the wonderful [tut][link-tut] to compile the vast majority of code in this text.  The REPL output is wrapped by LaTeX. This can be tricky to read, especially with long type signatures. So in some places we also duplicate and reformat the output. But the best way is to try the code out in the REPL for yourself.

### Callout Boxes {-}

We use three types of *callout box* to highlight particular content:

<div class="callout callout-info">
Tip callouts indicate handy summaries, recipes, or best practices.
</div>

<div class="callout callout-warning">
Advanced callouts provide additional information on corner cases or underlying mechanisms. Feel free to skip these on your first read-through---come back to them later for extra information.
</div>

<div class="callout callout-danger">
Warning callouts indicate common pitfalls and gotchas. Make sure you read these to avoid problems, and come back to them if you're having trouble getting your code to run.
</div>
