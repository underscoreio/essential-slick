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

### REPL Output {-}

We use Scala comments to show REPL output. For example:

~~~ scala
2 * 13
// res0: Int = 26
~~~

If you're following along with the REPL, and copy and paste from the book we hope this will be useful.
It means if you accidentally copy more than you intended, the REPL will ignore the commented output.

We use the [mdoc][link-mdoc] to compile the majority of code in this text.
The REPL output is wrapped by LaTeX.
This can be tricky to read, especially with long type signatures.
So in some places we also duplicate and reformat the output.
But the best way is to try the code out in the REPL for yourself.

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
