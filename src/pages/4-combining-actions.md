```scala mdoc:invisible
import slick.jdbc.H2Profile.api._

case class Message(
  sender:  String,
  content: String,
  id:      Long = 0L)

class MessageTable(tag: Tag) extends Table[Message](tag, "message") {

  def id      = column[Long]("id", O.PrimaryKey, O.AutoInc)
  def sender  = column[String]("sender")
  def content = column[String]("content")

  def * = (sender, content, id).mapTo[Message]
}

lazy val messages = TableQuery[MessageTable]

import scala.concurrent.{Await,Future}
import scala.concurrent.duration._

val db = Database.forConfig("chapter04")

def exec[T](action: DBIO[T]): T = Await.result(db.run(action), 2.seconds)

def freshTestData = Seq(
  Message("Dave", "Hello, HAL. Do you read me, HAL?"),
  Message("HAL",  "Affirmative, Dave. I read you."),
  Message("Dave", "Open the pod bay doors, HAL."),
  Message("HAL",  "I'm sorry, Dave. I'm afraid I can't do that.")
)

exec(messages.schema.create andThen (messages ++= freshTestData))
```
# Combining Actions {#combining}

At some point you'll find yourself writing a piece of code made up of multiple actions.
You might need a simple sequence of actions to run one after another;
or you might need something more sophisticated where one action depends on the results of another.

In Slick you use _action combinators_ to turn a number of actions into a single action.
You can then run this combined action just like any single action.
You might also run these combined actions in a _transaction_.

This chapter focuses on these combinators.
Some, such as `map`, `fold`, and `zip`, will be familiar from the Scala collections library.
Others, such as `sequence` and `asTry` may be less familiar.
We will give examples of how to use many of them in this chapter.

This is a key concept in Slick.
Make sure you spend time getting comfortable with combining actions.

## Combinators Summary

The temptation with multiple actions might be to run each action, use the result, and run another action.
This will require you to deal with multiple `Future`s.
We recommend you avoid that whenever you can.

Instead, focus on the actions and how they combine together, not on the messy details of running them.
Slick provides a set of combinators to make this possible.

Before getting into the detail, take a look at the two tables below. They list out the key methods available on an action,
and also the combinators available on `DBIO`.


--------------------------------------------------------------------
Method              Arguments                       Result Type     
------------------- -----------------------------   ----------------
`map` (EC)           `T => R`                        `DBIO[R]`        

`flatMap` (EC)       `T => DBIO[R]`                  `DBIO[R]`

`filter` (EC)         `T => Boolean`                  `DBIO[T]`

`named`             `String`                        `DBIO[T]`

`zip`               `DBIO[R]`                       `DBIO[(T,R)]`

`asTry`                                             `DBIO[Try[T]]`

`andThen` or `>>`   `DBIO[R]`                       `DBIO[R]`

`andFinally`        `DBIO[_]`                       `DBIO[T]`

`cleanUp` (EC)       `Option[Throwable]=>DBIO[_]`    `DBIO[T]`

`failed`                                            `DBIO[Throwable]`
----------------------------------------------------------------------

: Combinators on action instances of `DBIOAction`, specifically a `DBIO[T]`.
  Types simplified.
  (EC) Indicates an execution context is required.


---------------------------------------------------------------------------
Method       Arguments                       Result Type                   
------------ ------------------------------- ------------------------------
`sequence`   `TraversableOnce[DBIO[T]]`      `DBIO[TraversableOnce[T]]`

`seq`        `DBIO[_]*`                      `DBIO[Unit]`                   

`from`       `Future[T]`                     `DBIO[T]`

`successful` `V`                             `DBIO[V]`

`failed`     `Throwable`                     `DBIO[Nothing]`

`fold` (EC)   `(Seq[DBIO[T]], T)  (T,T)=>T`   `DBIO[T]`
----------------------------------------------------------------------------

: Combinators on `DBIO` object, with types simplified.
  (EC) Indicates an execution context is required.

## Combinators in Detail

### `andThen` (or `>>`)

The simplest way to run one action after another is perhaps `andThen`.
The combined actions are both run, but only the result of the second is returned:

```scala mdoc
val reset: DBIO[Int] =
  messages.delete andThen messages.size.result

exec(reset)
```

The result of the first query is ignored, so we cannot use it.
Later we will see how `flatMap` allows us to use the result to make choices about which action to run next.

<div class="callout callout-warning">
**Combined Actions Are Not Automatically Transactions**

By default, when you combine actions together you do not get a single transaction.
At the [end of this chapter][Transactions] we'll see that it's very easy to run combined actions in a transaction with:

```scala
db.run(actions.transactionally)
```
</div>

### `DBIO.seq`

If you have a bunch of actions you want to run, you can use `DBIO.seq` to combine them:

```scala mdoc:silent
val resetSeq: DBIO[Unit] =
  DBIO.seq(messages.delete, messages.size.result)
```

This is rather like combining the actions with `andThen`, but even the last value is discarded.


### `map`

Mapping over an action is a way to set up a transformation of a value from the database.
The transformation will run on the result of the action when it is returned by the database.

As an example, we can create an action to return the content of a message, but reverse the text:

```scala mdoc
// Restore the data we deleted in the previous section
exec(messages ++= freshTestData)

import scala.concurrent.ExecutionContext.Implicits.global

val text: DBIO[Option[String]] =
  messages.map(_.content).result.headOption

val backwards: DBIO[Option[String]] =
  text.map(optionalContent => optionalContent.map(_.reverse))

exec(backwards)
```

Here we have created an action called `backwards` that, when run, ensures a function
is applied to the result of the `text` action.
In this case the function is to apply `reverse` to an optional `String`.

Note that we have made three uses of `map` in this example:

- an `Option` `map` to apply `reverse` to our `Option[String]` result;
- a `map` on a query to select just the `content` column; and
- `map` on our action so that the result will be transform when the action is run.

Combinators everywhere!

This example transformed an `Option[String]` to another `Option[String]`.
As you may expect if `map` changes the type of a value, the type of `DBIO` changes too:

```scala mdoc
text.map(os => os.map(_.length))
```

Note that the first type parameter on the `DBIOAction` is now `Option[Int]` (as `length` returns an `Int`), not `Option[String]`.

<div class="callout callout-info">
**Execution Context Required**

Some methods require an execution context and some don't. For example, `map` does, but `andThen` does not.
What gives?

The reason is that `map` allows you to call arbitrary code when joining the actions together.
Slick cannot allow that code to be run on its own execution context,
because it has no way to know if you are going to tie up Slicks threads for a long time.

In contrast, methods such as `andThen` which combine actions without custom code can be run on Slick's own execution context.
Therefore, you do not need an execution context available for `andThen`.

You'll know if you need an execution context, because the compiler will tell you:

~~~
Cannot find an implicit ExecutionContext. You might pass
  an (implicit ec: ExecutionContext) parameter to your method
  or import scala.concurrent.ExecutionContext.Implicits.global.
~~~

The Slick manual discusses this in the section on [Database I/O Actions][link-ref-actions].
</div>


### `DBIO.successful` and `DBIO.failed`

When combining actions you will sometimes need to create an action that represents a simple value.
Slick provides `DBIO.successful` for that purpose:

```scala mdoc:silent
val ok: DBIO[Int] = DBIO.successful(100)
```

We'll see an example of this when we discuss `flatMap`.

And for failures, the value is a `Throwable`:

```scala mdoc:silent
val err: DBIO[Nothing] =
  DBIO.failed(new RuntimeException("pod bay door unexpectedly locked"))
```

This has a particular role to play inside transactions, which we cover later in this chapter.

### `flatMap`

Ahh, `flatMap`. Wonderful `flatMap`.
This method gives us the power to sequence actions and decide what we want to do at each step.

The signature of `flatMap` should feel similar to the `flatMap` you see elsewhere:

~~~ scala
// Simplified:
def flatMap[S](f: R => DBIO[S])(implicit e: ExecutionContext): DBIO[S]
~~~

That is, we give `flatMap` a function that depends on the value from an action, and evaluates to another action.

As an example, let's write a method to remove all the crew's messages, and post a message saying how many messages were removed.
This will involve an `INSERT` and a `DELETE`, both of which we're familiar with:

```scala mdoc:silent
val delete: DBIO[Int] =
  messages.delete

def insert(count: Int) =
  messages += Message("NOBODY", s"I removed ${count} messages")
```

The first thing `flatMap` allows us to do is run these actions in order:

```scala mdoc
import scala.concurrent.ExecutionContext.Implicits.global

val resetMessagesAction: DBIO[Int] =
  delete.flatMap{ count => insert(count) }

exec(resetMessagesAction)
```

The `1` we see is the result of `insert`, which is the number of rows inserted.

This single action produces the two SQL expressions you'd expect:

``` sql
delete from "message";
insert into "message" ("sender","content")
  values ('NOBODY', 'I removed 4 messages');
```

Beyond sequencing, `flatMap` also gives us control over which actions are run.
To illustrate this we will produce a variation of `resetMessagesAction` which will not insert a message if no messages were removed in the first step:

```scala mdoc:silent:silent
val logResetAction: DBIO[Int] =
  delete.flatMap {
    case 0 => DBIO.successful(0)
    case n => insert(n)
  }
```

We've decided a result of `0` is right if no message was inserted.
But the point here is that `flatMap` gives us arbitrary control over how actions can be combined.

Occasionally the compiler will complain about a `flatMap` and need your help to figuring out the types.
Recall that `DBIO[T]` is an alias for `DBIOAction[T,S,E]`, encoding streaming and effects.
When mixing effects, such as inserts and selects, you may need to explicitly specify the type parameters to apply to the resulting action:

``` scala
query.flatMap[Int, NoStream, Effect.All] { result => ... }
```

...but in many cases the compiler will figure these out for you.


<div class="callout callout-info">
**Do it in the database if you can**

Combining actions to sequence queries is a powerful feature of Slick.
However, you may be able to reduce multiple queries into a single database query.
If you can do that, you're probably better off doing it.

As an example, you could implement "insert if not exists" like this:

```scala mdoc:silent:silent
// Not the best way:
def insertIfNotExists(m: Message): DBIO[Int] = {
  val alreadyExists =
    messages.filter(_.content === m.content).result.headOption
  alreadyExists.flatMap {
    case Some(m) => DBIO.successful(0)
    case None    => messages += m
  }
}
```

...but as we saw earlier in ["More Control over Inserts"](#moreControlOverInserts) you can achieve the same effect with a single SQL statement.

One query can often (but doesn't always) perform better than a sequence of queries.
Your mileage may vary.
</div>



### `DBIO.sequence`

Despite the similarity in name to `DBIO.seq`, `DBIO.sequence` has a different purpose.
It takes a sequence of `DBIO`s and gives back a `DBIO` of a sequence.
That's a bit of a mouthful, but an example may help.

Let's say we want to reverse the text of every message (row) in the database.
We start with this:

```scala mdoc:silent
def reverse(msg: Message): DBIO[Int] =
  messages.filter(_.id === msg.id).
  map(_.content).
  update(msg.content.reverse)
```

That's a straightforward method that returns an update action for one message.
We can apply it to every message...

```scala mdoc:silent
// Don't do this
val manyUpdates: DBIO[Seq[DBIO[Int]]] =
  messages.result.
  map(msgs => msgs.map(reverse))
```

...which will give us an action that returns actions!
Note the crazy type signature.

You can find yourself in this awkward situation when you're trying to do something like a join, but not quite.
The puzzle is how to run this kind of beast.

This is where `DBIO.sequence` saves us.
Rather than produce many actions via `msgs.map(reverse)` we use `DBIO.sequence` to return a single action:

```scala mdoc:silent
val updates: DBIO[Seq[Int]] =
  messages.result.
  flatMap(msgs => DBIO.sequence(msgs.map(reverse)))
```

The difference is:

- we've wrapped the `Seq[DBIO]` with `DBIO.sequence` to give a single `DBIO[Seq[Int]]`; and
- we use `flatMap` to combine the sequence with the original query.

The end result is a sane type which we can run like any other action.

Of course this one action turns into many SQL statements:

```sql
select "sender", "content", "id" from "message"
update "message" set "content" = ? where "message"."id" = 1
update "message" set "content" = ? where "message"."id" = 2
update "message" set "content" = ? where "message"."id" = 3
update "message" set "content" = ? where "message"."id" = 4
```

### `DBIO.fold`

Recall that many Scala collections support `fold` as a way to combine values:

```scala mdoc
List(3,5,7).fold(1) { (a,b) => a * b }

1 * 3 * 5 * 7
```

You can do the same kind of thing in Slick:
when you need to run a sequence of actions, and reduce the results down to a value, you use `fold`.

As an example, suppose we have a number of reports to run.
We want to summarize all these reports to a single number.

```scala mdoc:silent
// Pretend these two reports are complicated queries
// that return Important Business Metrics:
val report1: DBIO[Int] = DBIO.successful(41)
val report2: DBIO[Int] = DBIO.successful(1)

val reports: List[DBIO[Int]] =
  report1 :: report2 :: Nil
```

We can `fold` those `reports` with a function.

But we also need to consider our starting position:

```scala mdoc:silent
val default: Int = 0
```

Finally we can produce an action to summarize the reports:

```scala mdoc
val summary: DBIO[Int] =
  DBIO.fold(reports, default) {
    (total, report) => total + report
}

exec(summary)
```

`DBIO.fold` is a way to combine actions, such that the results are combined by a function you supply.
As with other combinators, your function isn't run until we execute the action itself.
In this case all our reports are run, and the sum of the values reported.


### `zip`

We've seen how `DBIO.seq` combines actions and ignores the results.
We've also seen that `andThen` combines actions and keeps one result.
If you want to keep both results, `zip` is the combinator for you:

```scala mdoc
val zip: DBIO[(Int, Seq[Message])] =
  messages.size.result zip messages.filter(_.sender === "HAL").result

// Make sure we have some messages from HAL:
exec(messages ++= freshTestData)

exec(zip)
```

The action returns a tuple representing the results of both queries:
a count of the total number of messages, and the messages from HAL.


### `andFinally` and `cleanUp`

The two methods `cleanUp` and `andFinally` act a little like Scala's `catch` and `finally`.

`cleanUp` runs after an action completes, and has access to any error information as an `Option[Throwable]`:

```scala mdoc:silent
// An action to record problems we encounter:
def log(err: Throwable): DBIO[Int] =
  messages += Message("SYSTEM", err.getMessage)

// Pretend this is important work which might fail:
val work = DBIO.failed(new RuntimeException("Boom!"))

val action: DBIO[Int] = work.cleanUp {
  case Some(err) => log(err)
  case None      => DBIO.successful(0)
}
```

The result of running this `action` is still the original exception...

```scala mdoc:crash
exec(action)
```

...but `cleanUp` has produced a side-effect for us:

```scala mdoc
exec(messages.filter(_.sender === "SYSTEM").result)
```

```scala mdoc:invisible
{
  val c = exec(messages.filter(_.sender === "SYSTEM").length.result)
  assert(c == 1, s"Expected one result not $c")
}
```

Both `cleanUp` and `andFinally` run after an action, regardless of whether it succeeds or fails.
`cleanUp` runs in response to a previous failed action; `andFinally` runs all the time, regardless of success or failure, and has no access to the `Option[Throwable]` that `cleanUp` sees.

### `asTry`

Calling `asTry` on an action changes the action's type from a `DBIO[T]` to a `DBIO[Try[T]]`.
This means you can work in terms of Scala's `Success[T]` and `Failure` instead of exceptions.

Suppose we had an action that might throw an exception:

```scala mdoc:silent
val tryAction = DBIO.failed(new RuntimeException("Boom!"))
```

We can place this inside `Try` by combining the action with `asTry`:

```scala mdoc
exec(tryAction.asTry)
```

And successful actions will evaluate to a `Success[T]`:

```scala mdoc
exec(messages.size.result.asTry)
```


## Logging Queries and Results

With actions combined together, it's useful to see the queries that are being executed.

We've seen how to retrieve the SQL of a query using `insertStatement` and similar methods on a query,
or the `statements` method on an action.
These are useful for experimenting with Slick, but sometimes we want to see all the queries *when Slick executes them*.
We can do that by configuring logging.

Slick uses a logging interface called [SLF4J][link-slf4j]. We can configure this to capture information about the queries being run. The `build.sbt` files in the exercises use an SLF4J-compatible logging back-end called [Logback][link-logback], which is configured in the file *src/main/resources/logback.xml*. In that file we can enable statement logging by turning up the logging to debug level:

``` xml
<logger name="slick.jdbc.JdbcBackend.statement" level="DEBUG"/>
```

This causes Slick to log every query, including modifications to the schema:

```
DEBUG slick.jdbc.JdbcBackend.statement - Preparing statement:
  delete from "message" where "message"."sender" = 'HAL'
```

We can change the level of various loggers, as shown in the table below.

-----------------------------------------------------------------------------------------------------------------------------
Logger                                                             Will log...
-----------------------------------------------------------------  ----------------------------------------------------------
`slick.jdbc.JdbcBackend.statement`                                 SQL sent to the database.

`slick.jdbc.JdbcBackend.parameter`                                 Parameters passed to a query.

`slick.jdbc.StatementInvoker.result`                               The first few results of each query.

`slick.session`                                                    Session events such as opening/closing connections.

`slick`                                                            Everything!
-----------------------------------------------------------------  ----------------------------------------------------------

: Slick loggers and their effects.

The `StatementInvoker.result` logger, in particular, is pretty cute.
Here's an example from running a select query:

```
result - /--------+----------------------+----\
result - | sender | content              | id |
result - +--------+----------------------+----+
result - | HAL    | Affirmative, Dave... | 2  |
result - | HAL    | I'm sorry, Dave. ... | 4  |
result - \--------+----------------------+----/
```

The combination of `parameter` and `statement` can show you the values bound to `?` placeholders.
For example, when adding rows we can see the values being inserted:

```
statement - Preparing statement: insert into "message" 
   ("sender","content")  values (?,?)
parameter - /--------+---------------------------\
parameter - | 1      | 2                         |
parameter - | String | String                    |
parameter - |--------+---------------------------|
parameter - | Dave   | Hello, HAL. Do you rea... |
parameter - | HAL    | I'm sorry, Dave. I'm a... |
parameter - \--------+---------------------------/
```



## Transactions {#Transactions}

So far each of the changes we've made to the database have run independently of the others. That is, each insert, update, or delete query we run can succeed or fail independently of the rest.

We often want to tie sets of modifications together in a *transaction* so that they either *all* succeed or *all* fail. We can do this in Slick using the `transactionally` method.

As an example, let's re-write the movie script. We want to make sure the script changes all complete or nothing changes. We can do this by finding the old script text and replacing it with some new text:

```scala mdoc
def updateContent(old: String) =
  messages.filter(_.content === old).map(_.content)

exec {
  (updateContent("Affirmative, Dave. I read you.").update("Wanna come in?") andThen
   updateContent("Open the pod bay doors, HAL.").update("Pretty please!") andThen
   updateContent("I'm sorry, Dave. I'm afraid I can't do that.").update("Opening now.") ).transactionally
}

exec(messages.result).foreach(println)
```

The changes we make in the `transactionally` block are temporary until the block completes, at which point they are *committed* and become permanent.

To manually force a rollback you need to call `DBIO.failed` with an appropriate exception.

```scala mdoc
val willRollback = (
  (messages += Message("HAL",  "Daisy, Daisy..."))                   >>
  (messages += Message("Dave", "Please, anything but your singing")) >>
  DBIO.failed(new Exception("agggh my ears"))                        >>
  (messages += Message("HAL", "Give me your answer do"))
  ).transactionally

exec(willRollback.asTry)
```

The result of running `willRollback` is that the database won't have changed.
Inside of transactional block you would see the inserts until `DBIO.failed` is called.

If we removed the `.transactionally` that is wrapping our combined actions, the first two inserts would succeed,
even though the combined action failed.

## Take Home Points

Inserts, selects, deletes and other forms of Database Action can be combined using `flatMap` and other combinators.
This is a powerful way to sequence actions, and make actions depend on the results of other actions.

Combining actions avoid having to deal with awaiting results or having to sequence `Future`s yourself.

We saw that the SQL statements executed and the result returned from the database can be monitored by configuring the logging system.

Finally, we saw that actions that are combined together can also be run inside a transaction.

## Exercises

### And Then what?

In Chapter 1 we created a schema and populated the database as separate actions.
Use your newly found knowledge to combine them.

This exercise expects to start with an empty database.
If you're already in the REPL and the database exists,
you'll need to drop the table first:

```scala mdoc
val drop:     DBIO[Unit]        = messages.schema.drop
val create:   DBIO[Unit]        = messages.schema.create
val populate: DBIO[Option[Int]] = messages ++= freshTestData

exec(drop)
```

<div class="solution">
Using the values we've provided, you can create a new database with a single action:

```scala mdoc:invisible
exec(drop.asTry >> create)
```
```scala mdoc
exec(drop andThen create andThen populate)
```

If we don't care about any of the values we could also use `DBIO.seq`:

```scala mdoc
val allInOne = DBIO.seq(drop,create,populate)
val result = exec(allInOne)
```
</div>

### First!

Create a method that will insert a message, but if it is the first message in the database,
automatically insert the message "First!" before it.

Your method signature should be:

```scala
def prefixFirst(m: Message): DBIO[Int] = ???
```

Use your knowledge of the `flatMap` action combinator to achieve this.

<div class="solution">
There are two elements to this problem:

1. being able to use the result of a count, which is what `flatMap` gives us; and

2. combining two inserts via `andThen`.

```scala mdoc
import scala.concurrent.ExecutionContext.Implicits.global

def prefixFirst(m: Message): DBIO[Int] =
  messages.size.result.flatMap {
    case 0 =>
      (messages += Message(m.sender, "First!")) andThen (messages += m)
    case n =>
      messages += m
    }

// Throw away all the messages:
exec(messages.delete)

// Try out the method:
exec {
  prefixFirst(Message("Me", "Hello?"))
}

// What's in the database?
exec(messages.result).foreach(println)
```
</div>

### There Can be Only One

Implement `onlyOne`, a method that guarantees that an action will return only one result.
If the action returns anything other than one result, the method should fail with an exception.

Below is the method signature and two test cases:

```scala
def onlyOne[T](ms: DBIO[Seq[T]]): DBIO[T] = ???
```

You can see that `onlyOne` takes an action as an argument, and that the action could return a sequence of results.
The return from the method is an action that will return a single value.

In the example data there is only one message that contains the word "Sorry", so we expect `onlyOne` to return that row:

```scala mdoc
val happy = messages.filter(_.content like "%sorry%").result
```
```scala
// We expect... 
// exec(onlyOne(happy))
// ...to return a message.
```

However, there are two messages containing the word "I". In this case `onlyOne` should fail:

```scala mdoc
val boom  = messages.filter(_.content like "%I%").result
```
```scala
// If we run this...
// exec(onlyOne(boom))
// we want a failure, such as:
// java.lang.RuntimeException: Expected 1 result, not 2
```

Hints:

- The signature of `onlyOne` is telling us we will take an action that produces a `Seq[T]` and return an action that produces a `T`. That tells us we need an action combinator here.

- That fact that the method may fail means we want to use `DBIO.successful` and `DBIO.failed` in there somewhere.

<div class="solution">
The basis of our solution is to `flatMap` the action we're given into a new action with the type we want:

```scala mdoc:silent
def onlyOne[T](action: DBIO[Seq[T]]): DBIO[T] = action.flatMap { ms =>
  ms match {
    case m +: Nil => DBIO.successful(m)
    case ys       => DBIO.failed(
        new RuntimeException(s"Expected 1 result, not ${ys.length}")
      )
  }
}
```

If you've not seen `+:` before: it is "cons" for `Seq` (a standard part of Scala, equivalent to `::` for `List`).

Our `flatMap` is taking the results from the action, `ms`, and in the case it is a single message, we return it.
In the case it's something else, we fail with an informative message.

```scala mdoc
exec(populate)
```

```scala mdoc:crash
exec(onlyOne(boom))
```

```scala mdoc
exec(onlyOne(happy))
```
</div>

### Let's be Reasonable

Some _fool_ is throwing exceptions in our code, destroying our ability to reason about it.
Implement `exactlyOne` which wraps `onlyOne` encoding the possibility of failure using types rather than exceptions.

Then rerun the test cases.

<div class="solution">
There are several ways we could have implemented this.
Perhaps the simplest is using `asTry`:

```scala mdoc
import scala.util.Try
def exactlyOne[T](action: DBIO[Seq[T]]): DBIO[Try[T]] = onlyOne(action).asTry

exec(exactlyOne(happy))
```

```scala mdoc
exec(exactlyOne(boom))
```
</div>


### Filtering

There is a `DBIO` `filter` method, but it produces a runtime exception if the filter predicate is false.
It's like `Future`'s `filter` method in that respect. We've not found a situation where we need it.

However, we can create our own kind of filter.
It can take some alternative action when the filter predicate fails.

The signature could be:

```scala
def myFilter[T](action: DBIO[T])(p: T => Boolean)(alternative: => T) = ???
```

If you're not comfortable with the `[T]` type parameter,
or the by name parameter on `alternative`,
just use `Int` instead:

```scala
def myFilter(action: DBIO[Int])(p: Int => Boolean)(alternative: Int) = ???
```

Go ahead and implement `myFilter`.

We have an example usage from the ship's marketing department.
They are happy to report the number of chat messages, but only if that number is at least 100:

```scala
myFilter(messages.size.result)( _ > 100)(100)
```

<div class="solution">
This is a fairly straightforward example of using `map`:

```scala mdoc:silent
def myFilter[T](action: DBIO[T])(p: T => Boolean)(alternative: => T) =
  action.map {
    case t if p(t) => t
    case _         => alternative
  }
```
</div>

### Unfolding

This is a challenging exercise.

We saw that `fold` can take a number of actions and reduce them using a function you supply.
Now imagine the opposite: unfolding an initial value into a sequence of values via a function.
In this exercise we want you to write an `unfold` method that will do just that.

Why would you need to do something like this?
One example would be when you have a tree structure represented in a database and need to search it.
You can follow a link between rows, possibly recording what you find as you follow those links.

As an example, let's pretend the crew's ship is a set of rooms, one connected to just one other:

```scala mdoc
case class Room(name: String, connectsTo: String)

class FloorPlan(tag: Tag) extends Table[Room](tag, "floorplan") {
  def name       = column[String]("name")
  def connectsTo = column[String]("next")
  def * = (name, connectsTo).mapTo[Room]
}

lazy val floorplan = TableQuery[FloorPlan]

exec {
  (floorplan.schema.create) >>
  (floorplan += Room("Outside",     "Podbay Door")) >>
  (floorplan += Room("Podbay Door", "Podbay"))      >>
  (floorplan += Room("Podbay",      "Galley"))      >>
  (floorplan += Room("Galley",      "Computer"))    >>
  (floorplan += Room("Computer",    "Engine Room"))
}
```

For any given room it's easy to find the next room. For example:

~~~ sql
SELECT
  "connectsTo"
FROM
  "foorplan"
WHERE
  "name" = 'Podbay'

-- Returns 'Galley'
~~~

Write a method `unfold` that will take any room name as a starting point,
and a query to find the next room,
and will follow all the connections until there are no more connecting rooms.

The signature of `unfold` _could_ be:

```scala
def unfold(
  z: String,
  f: String => DBIO[Option[String]]
): DBIO[Seq[String]] = ???
```

...where `z` is the starting ("zero") room, and `f` will lookup the connecting room (an action for the query to find the next room).

If `unfold` is given `"Podbay"` as a starting point it should return an action which, when run, will produce: `Seq("Podbay", "Galley", "Computer", "Engine Room")`.

You'll want to accumulate results of the rooms you visit.
One way to do that would be to use a different signature:

```scala
def unfold(
  z: String,
  f: String => DBIO[Option[String]],
  acc: Seq[String] = Seq.empty
): DBIO[Seq[String]] = ???
```

<div class="solution">

The trick here is to recognize that:

1. this is a recursive problem, so we need to define a stopping condition;

2. we need `flatMap` to sequence queries ; and

3. we need to accumulate results from each step.

In code...

```scala mdoc:silent
def unfold(
  z: String,
  f: String => DBIO[Option[String]],
  acc: Seq[String] = Seq.empty
): DBIO[Seq[String]] =
  f(z).flatMap {
    case None    => DBIO.successful(acc :+ z)
    case Some(r) => unfold(r, f, acc :+ z)
  }
```

The basic idea is to call our action (`f`) on the first room name (`z`).
If there's no result from the query, we're done.
Otherwise we add the room to the list of rooms, and recurse starting from the room we just found.

Here's how we'd use it:

```scala mdoc
def nextRoom(roomName: String): DBIO[Option[String]] =
  floorplan.filter(_.name === roomName).map(_.connectsTo).result.headOption

val path: DBIO[Seq[String]] = unfold("Podbay", nextRoom)

exec(path)
```

```scala mdoc:invisible
{
  val r = exec(path)
  assert(r == List("Podbay", "Galley", "Computer", "Engine Room"), s"Expected 4 specific rooms, but got $r")
}
```
</div>
