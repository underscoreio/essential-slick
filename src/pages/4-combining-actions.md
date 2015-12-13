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


----------------------------------------------------------------------------------------------------
Method              Arguments                       Result Type      Notes
------------------- -----------------------------   ---------------- ------------------------------
`map`               `T => R`                        `DBIO[R]`        Execution context required

`flatMap`           `T => DBIO[R]`                  `DBIO[R]`        _ditto_

`filter`            `T => Boolean`                  `DBIO[T]`        _ditto_

`named`             `String`                        `DBIO[T]`

`zip`               `DBIO[R]`                       `DBIO[(T,R)]`

`asTry`                                             `DBIO[Try[T]]`

`andThen` or `>>`   `DBIO[R]`                       `DBIO[Unit]`     Example in Chapter 1.

`andFinally`        `DBIO[_]`                       `DBIO[T]`

`cleanUp`           `Option[Throwable]=>DBIO[_]`    `DBIO[T]`        Execution context required

`failed`                                            `DBIO[Throwable]`
----------------------------------------------------------------------------------------------------

: Combinators on action instances of `DBIOAction`, specifically a `DBIO[T]`.
  Types simplified.


----------------------------------------------------------------------------------------------------------
Method       Arguments                       Result Type                    Notes
------------ ------------------------------- ------------------------------ ------------------------------
`sequence`   `TraversableOnce[DBIO[T]]`      `DBIO[TraversableOnce[T]]`

`seq`        `DBIO[_]*`                      `DBIO[Unit]`                   Combines actions, ignores results

`from`       `Future[T]`                     `DBIO[T]`

`successful` `V`                             `DBIO[V]`

`failed`     `Throwable`                     `DBIO[Nothing]`

`fold`       `(Seq[DBIO[T]], T)  (T,T)=>T`   `DBIO[T]`                      Execution context required
----------------------------------------------------------------------------------------------------------

: Combinators on `DBIO` object, with types simplified.

## Combinators in Detail


<div class="callout callout-warning">
**Combined Actions Are Not Automatically Transactions**

By default, when you combine actions together you do not get a single transaction.  At the [end of this chapter][Transactions] we'll see that it's very easy to run combined actions in a transaction with `db.run(actions.transactionally)`.
</div>


### `andThen` (or `>>`)

The simplest way to run one action after another is perhaps `andThen`.
The combined actions are both run, but only the result of the second is returned:

~~~ scala
val reset: DBIO[Int] =
  messages.delete andThen messages.size.result

exec(reset)
// res1: Int = 0
~~~

The result of the first query is ignored, so we cannot use it.
Later we will see how `flatMap` allows us to use the result to make choices about which action to run next.

### `DBIO.seq`

If you have a bunch of actions you want to run, you can use `DBIO.seq` to combine them:

~~~ scala
val reset: DBIO[Unit] =
  DBIO.seq(messages.delete, messages.size.result)
~~~

This is rather like combining the actions with `andThen`, but even the last value is discarded.


### `map`

Mapping over an action is a way to set up a transformation of a value from the database.
The transformation will run on the result of the action when it is returned by the database.

As an example, we can create an action to return the content of a message, but reverse the text:

~~~ scala
val text: DBIO[Option[String]] =
  messages.map(_.content).result.headOption

val backwards: DBIO[Option[String]] =
  text.map( optionalContent => optionalContent.map(_.reverse) )

exec(backwards)
// res1: Option[String] =
//  Option[String] = Some(?LAH ,em daer uoy oD .LAH ,olleH)
~~~

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

~~~ scala
text.map(os => os.map(_.length))
// res2: slick.dbio.DBIOAction[
//   Option[Int],
//   slick.dbio.NoStream,
//   slick.dbio.Effect.All
// ]
~~~

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
error: Cannot find an implicit ExecutionContext. You might pass
  an (implicit ec: ExecutionContext) parameter to your method
  or import scala.concurrent.ExecutionContext.Implicits.global.
~~~

The Slick manual discusses this in the section on [Database I/O Actions][link-ref-actions].
</div>


### `DBIO.successful` and `DBIO.failed`

When combining actions you will sometimes need to create an action that represents a simple value.
Slick provides `DBIO.successful` for that purpose:

~~~ scala
val v: DBIO[Int] = DBIO.successful(100)
// v: slick.dbio.DBIO[Int] = SuccessAction(100)
~~~

We'll see an example of this when we discuss `flatMap`.

And for failures, the value is a `Throwable`:

~~~ scala
val v: DBIO[Nothing] =
  DBIO.failed(new RuntimeException("pod bay door unexpectedly locked"))
// v: slick.dbio.DBIO[Nothing] = FailureAction(
//  java.lang.RuntimeException: pod bay door unexpectedly locked)
~~~

This has a particular role to play inside transactions, which we cover later in this chapter.


<div class="callout callout-info">
**Error: value successful is not a member of object slick.dbio.DBIO**

Due to a [bug][link-scala-type-alias-bug] in Scala you may experience something like the above error when using `DBIO` methods on the REPL with Slick 3.0. This is resolved in Slick 3.1.

If you do encounter it, and have to stay with Slick 3.0,
you can carry on by writing your code in a `.scala` source file and running it from SBT.
</div>


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

~~~ scala
val delete: DBIO[Int] =
  messages.delete

def insert(count: Int) =
  messages += Message("NOBODY", s"I removed ${count} messages")
~~~

The first thing `flatMap` allows us to do is run these actions in order:

~~~ scala
import scala.concurrent.ExecutionContext.Implicits.global

val resetMessagesAction: DBIO[Int] =
  delete.flatMap{ count => insert(count) }

exec(resetMessagesAction)
// res1: Int = 1
~~~

This single action produces the two SQL expressions you'd expect:

~~~ sql
delete from "message";
insert into "message" ("sender","content")
  values ('NOBODY', 'I removed 4 messages');
~~~

Beyond sequencing, `flatMap` also gives us control over which actions are run.
To illustrate this we will change `resetMessagesAction` to not insert a message if no messages were removed in the first step:

~~~ scala
val resetMessagesAction: DBIO[Int] =
  delete.flatMap {
    case 0 => DBIO.successful(0)
    case n => insert(n)
  }
~~~

We've decided a result of `0` is right if no message was inserted.
But the point here is that `flatMap` gives us arbitrary control over how actions can be combined.

Occasionally the compiler will complain about a `flatMap` and need your help to figuring out the types.
Recall that `DBIO[T]` is an alias for `DBIOAction[T,S,E]`, encoding streaming and effects.
When mixing effects, such as inserts and selects, you may need to explicitly specify the type parameters to apply to the resulting action:

~~~ scala
query.flatMap[Int, NoStream, Effect.All] { result => ... }
~~~

...but in many cases the compiler will figure these out for you.


<div class="callout callout-info">
**Do it in the database if you can**

Combining actions to sequence queries is a powerful feature of Slick.
However, you may be able to reduce multiple queries into a single database query.
If you can do that, you're probably better off doing it.

As an example, you could implement "insert if not exists" like this:

~~~ scala
// Not the best way:
def insertIfNotExists(m: Message): DBIO[Int] = {
  val alreadyExists =
    messages.filter(_.content === m.content).result.headOption
  alreadyExists.flatMap {
    case Some(m) => DBIO.successful(0)
    case None    => messages += m
  }
}
~~~

...but as we saw earlier in ["More Control over Inserts"](#moreControlOverInserts) you can achieve the same effect with a single SQL statement.

One query can often (but doesn't always) perform better than a sequence of queries. You mileage may vary.
</div>



### `DBIO.sequence`

Despite the similarity in name to `DBIO.seq`, `DBIO.sequence` has a different purpose.
It takes a sequence of `DBIO`s and gives back a `DBIO` of a sequence.
That's a bit of a mouthful, but an example may help.

At the end of the last chapter we attempted to update rows based on their current value.
Here we'll say we want to reverse the text of every message.
We start with this:

~~~ scala
def reverse(msg: Message): DBIO[Int] =
  messages.filter(_.id === msg.id).
  map(_.content).
  update(msg.content.reverse)
~~~

That's a straightforward method that returns an update action for one message.
We can apply it to every message....

~~~ scala
// Don't do this
val updates: DBIO[Seq[DBIO[Int]]] =
  messages.result.
  map(msgs => msgs.map(reverse))
~~~

...which will give us an action that returns actions!
Note the crazy type signature.

You can find yourself in this awkward situation when you're trying to do something like a join, but not quite.
The puzzle is how to run this kind of a beast.

This is where `DBIO.sequence` saves us.
Rather than produce many actions via `msgs.map(reverse)` we use `DBIO.sequence` to return a single action:

~~~ scala
val updates: DBIO[Seq[Int]] =
  messages.result.
  flatMap(msgs => DBIO.sequence(msgs.map(reverse)))
~~~

The difference is:

- we've wrapped the `Seq[DBIO]` with `DBIO.sequence` to give a single `DBIO[Seq[Int]]`; and
- we use `flatMap` to combine the sequence with the original query.

The end result is a sane type which we can run like any other action.

Of course this one action turns into many SQL statements:

~~~ sql
select "sender", "content", "id" from "message"
update "message" set "content" = ? where "message"."id" = 1
update "message" set "content" = ? where "message"."id" = 2
update "message" set "content" = ? where "message"."id" = 3
update "message" set "content" = ? where "message"."id" = 4
~~~


### `DBIO.fold`

Recall that many Scala collections support `fold` as a way to combine values:

~~~ scala
List(3,5,7).fold(1) { (a,b) => a * b }
// res1: Int = 105
~~~

You can do the same kind of thing in Slick:
when you need to run a sequence of actions, and reduce the results down to a value, you use `fold`.

As an example, suppose we have a number of reports to run.
We want to summarize all these reports to a single number.

~~~ scala
val report1: DBIO[Int] = ...
val report2: DBIO[Int] = ...

val reports: List[DBIO[Int]] =
  report1 :: report2 :: Nil
~~~

We can `fold` those `reports` with a function.

But we also need to consider our starting position:

~~~ scala
val default: Int = 0
~~~

Finally we can produce an action to summarize the reports:

~~~ scala
val summary: DBIO[Int] =
  DBIO.fold(reports, default) {
    (total, report) => total + report
}
~~~

`DBIO.fold` is a way to combine actions, such that the results are combined by a function you supply.
As with other combinators, your function isn't run until we execute the action itself.
In this case all our reports are run, and the sum of the values reported.


### `zip`

We've seen how `DBIO.seq` combines actions and ignores the results.
We've also seen that `andThen` combines actions and keeps one result.
If you want to keep both results, `zip` is the combinator for you:

~~~ scala
val countAndHal: DBIO[(Int, Seq[Message])] =
  messages.size.result zip messages.filter(_.sender === "HAL").result

exec(countAndHall)
// res1: (Int, Seq[Example.Message]) =
//  (4,
//   Vector(
//    Message(HAL,Affirmative, Dave. I read you.,8),
//    Message(HAL,I'm sorry, Dave. I'm afraid I can't do that.,10)
//   )
// )
~~~

The action returns a tuple representing the results of both queries.


### `andFinally` and `cleanUp`

The two methods `cleanUp` and `andFinally` act a little like Scala's `catch` and `finally`.

`cleanUp` runs after an action completes, and has access to any error information as an `Option[Throwable]`:

~~~ scala
// Let's record problems we encounter:
def log(err: Throwable): DBIO[Int] =
  messages += Message("SYSTEM", err.getMessage)

// Pretend this is important work which might fail:
val work =
  DBIO.failed(new RuntimeException("Boom!"))

val action =
  work.cleanUp {
    case Some(err) => log(err)
    case None      => DBIO.successful(0)
  }

exec(action)
// java.lang.RuntimeException: Boom!
//  ... 45 elided

exec(messages.filter(_.sender === "SYSTEM").result)
// res1: Seq[Example.MessageTable#TableElementType] =
//  Vector(Message(SYSTEM,Boom!,11))
~~~

Notice the result is still the original exception, but `cleanUp` has produced a side-effect for us.

Both `cleanUp` and `andFinally` run after an action, regardless of whether it succeeds or fails.
`cleanUp` runs in response to a previous failed action; `andFinally` runs all the time, regardless of success or failure, and has no access to the `Option[Throwable]` that `cleanUp` sees.

### `asTry`

Calling `asTry` on an action changes the action's type from a `DBIO[T]` to a `DBIO[Try[T]]`.
This means you can work in terms of Scala's `Success[T]` and `Failure` instead of exceptions.

Suppose we had an action that might throw an exception:

~~~ scala
val work =
  DBIO.failed(new RuntimeException("Boom!"))
~~~

We can place this inside `Try` by combining the action with `asTry`:

~~~ scala
exec(work.asTry)
// res1: scala.util.Try[Nothing] =
//  Failure(java.lang.RuntimeException: Boom!)
~~~

And successful actions will evauluate to a `Success[T]`:

~~~ scala
exec(messages.size.result.asTry)
// res2: scala.util.Try[Int] =
//  Success(4)
~~~


## Logging Queries and Results

With actions combined together, it's useful to see the queries that are being executed.

We've seen how to retrieve the SQL of a query using `insertStatement` and similar methods on a query,
or the `statements` method on an action.
These are useful for experimenting with Slick, but sometimes we want to see all the queries *when Slick executes them*.
We can do that by configuring logging.

Slick uses a logging interface called [SLF4J][link-slf4j]. We can configure this to capture information about the queries being run. The `build.sbt` files in the exercises use an SLF4J-compatible logging back-end called [Logback][link-logback], which is configured in the file *src/main/resources/logback.xml*. In that file we can enable statement logging by turning up the logging to debug level:

~~~ xml
<logger name="slick.jdbc.JdbcBackend.statement" level="DEBUG"/>
~~~

This causes Slick to log every query, even modifications to the schema:

~~~
DEBUG slick.jdbc.JdbcBackend.statement - Preparing statement: ↩
  delete from "message" where "message"."sender" = 'HAL'
~~~

We can change the level of various loggers, as shown in the table below:

-------------------------------------------------------------------------------------------------------------------
Logger                                 Effect
-------------------------------------  ----------------------------------------------------------
`slick.jdbc.JdbcBackend.statement`     Logs SQL sent to the database as described above.

`slick.jdbc.StatementInvoker.result`   Logs the first few results of each query.

`slick.session`                        Logs session events such as opening/closing connections.

`slick`                                Logs everything! Equivalent to changing all of the above.
-------------------------------------  ----------------------------------------------------------

: Slick loggers and their effects.

The `StatementInvoker.result` logger, in particular, is pretty cute:

~~~
SI.result - /--------+----------------------+----\
SI.result - | sender | content              | id |
SI.result - +--------+----------------------+----+
SI.result - | HAL    | Affirmative, Dave... | 2  |
SI.result - | HAL    | I'm sorry, Dave. ... | 4  |
SI.result - \--------+----------------------+----/
~~~




## Transactions {#Transactions}

So far each of the changes we've made to the database have run independently of the others. That is, each insert, update, or delete query we run can succeed or fail independently of the rest.

We often want to tie sets of modifications together in a *transaction* so that they either *all* succeed or *all* fail. We can do this in Slick using the `transactionally` method.

As an example, let's re-write the script. We want to make sure the script changes all complete or nothing changes:

~~~ scala
def updateContent(id: Long) =
  messages.filter(_.id === id).map(_.content)

exec {
  (updateContent(2L).update("Wanna come in?") andThen
   updateContent(3L).update("Pretty please!") andThen
   updateContent(4L).update("Opening now.") ).transactionally
}

exec(messages.result)
// res1: Seq[Example.MessageTable#TableElementType] = Vector(
//   Message(Dave,Hello, HAL. Do you read me, HAL?,1),
//   Message(HAL,Wanna come in?,2),
//   Message(Dave,Pretty please!,3),
//   Message(HAL,Opening now.,4))
~~~

The changes we make in the `transactionally` block are temporary until the block completes, at which point they are *committed* and become permanent.

To manually force a rollback you need to call `DBIO.failed` with an appropriate exception.

~~~ scala
val willRollback = (
  (messages += Message("HAL",  "Daisy, Daisy..."))                   >>
  (messages += Message("Dave", "Please, anything but your singing")) >>
  DBIO.failed(new Exception("agggh my ears"))                        >>
  (messages += Message("HAL", "Give me your answer do"))
  ).transactionally

exec(willRollback.asTry)
// scala.util.Try[Int] =
//  Failure(java.lang.Exception: agggh my ears)
~~~

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

In Chapter 1 we create a schema and populate the database as separate actions.
Use your newly found knowledge to combine them.

This exercise expects to start with an empty database.
If you're already in the REPL and the database exists,
you'll need to drop the table first:

~~~ scala

val drop:     DBIO[Unit]        = messages.schema.drop
val create:   DBIO[Unit]        = messages.schema.create
val populate: DBIO[Option[Int]] = messages ++= testData

exec(drop)
exec(create)
exec(populate)
~~~~

<div class="solution">
~~~ scala
exec( drop andThen create andThen populate)
~~~
</div>

### First!

Create a method that will insert a message, but if it is the first message in the database,
automatically insert the message "First!" before it.

Your method signature should be:

~~~ scala
def insert(m: Message): DBIO[Int]
~~~

Use your knowledge of the `flatMap` action combinator to achieve this.

<div class="solution">
There are two elements to this problem:

1. being able to use the result of a count, which is what `flatMap` gives us; and
2. combining two inserts via `andThen`.

~~~ scala
import scala.concurrent.ExecutionContext.Implicits.global

def insert(m: Message): DBIO[Int] =
    messages.size.result.flatMap {
      case 0 =>
        (messages += Message(m.sender, "First!")) andThen (messages += m)
      case n =>
        messages += m
    }

// Throw away all the messages:
exec(messages.delete)
// res1: Int = 3

// Try out the method:
exec {
  insert(Message("Me", "Hello?"))
}
// res2: Int = 1

// What's in the database?
exec(messages.result).foreach(println)
// Message(Me,First!,7)
// Message(Me,Hello?,8)
~~~
</div>

### There Can be Only One

Implement `onlyOne`, a method that guarantees that an action will return only one result.
If the action returns anything other than one result, the method should fail with an exception.

Below is the method signature and two test cases:

``` scala
def onlyOne[T](xs:DBIO[Seq[T]]):DBIO[T] = ???
```

In the example there is only one message that contains the word "Sorry", so we expect `onlyOne` to return that row:

``` scala
val happy = messages.filter(_.content like "%sorry%").result

exec(onlyOne(happy))
//res25: Example.MessageTable#TableElementType =
// Message(HAL, I'm sorry, Dave. I'm afraid I can't do that., 4)
```

However, there are two messages containing the word "I". In this case `onlyOne` will fail:

``` scala
val boom  = messages.filter(_.content like "%I%").result
exec(onlyOne(boom))
//java.lang.RuntimeException: Expected 1 result, not 2
//  ...
```

Hints: The signature of `onlyOne` is telling us we will take an action that produces a `Seq[T]` and return an action that produces a `T`.
That tells us we need an action combinator here.
That fact that the method may fail means we want to use `DBIO.successful` and `DBIO.failed` in there somewhere.

<div class="solution">

You may not have seen `+:` before: it is `cons` for `Seq`.

~~~ scala
  def onlyOne[T](action:DBIO[Seq[T]]):DBIO[T] = action.flatMap{ xs =>
    xs match {
      case x +: Nil =>
        DBIO.successful(x)
      case ys       =>
        DBIO.failed(
          new RuntimeException(s"Expected 1 result, not ${ys.length}")
        )
    }
  }

exec(onlyOne(boom))
//java.lang.RuntimeException: Expected 1 result, not 2
//  ...

exec(onlyOne(happy))
// Message(HAL, I'm sorry, Dave. I'm afraid I can't do that., 4)
~~~
</div>


### Let's be Reasonable

Some _fool_ is throwing exceptions in our code, destroying our ability to reason about it.
Implement `exactlyOne` which wraps `onlyOne` encoding the possibility of failure using types rather than exceptions.

Then rerun the test cases.

<div class="solution">
There are several ways we could have implemented this, the simplest is using `asTry`

~~~ scala
def exactlyOne[T](action:DBIO[Seq[T]]):DBIO[Try[T]] = onlyOne(action).asTry


exec(exactlyOne(happy))
// res26: scala.util.Try[Example.MessageTable#TableElementType] =
//   Success(Message(HAL,I'm sorry, Dave. I'm afraid I can't do that.,4))


exec(exactlyOne(boom))
// res27: scala.util.Try[Example.MessageTable#TableElementType] =
//   Failure(java.lang.RuntimeException: Expected 1 result, not 2)



~~~
</div>


### Filtering

There is a `DBIO` `filter` method, but it produces a runtime exception if the filter predicate is false.
It's like `Future`'s `filter` method in that respect. We've not found a situation where we need it.

However, we can create our own kind of filter.
It can take some alternative action when the filter predicate fails.

The signature could be:

~~~ scala
def myFilter[T]
  (action: DBIO[T])
  (p: T => Boolean)
  (alternative: => T) = ???
~~~

If you're not comfortable with the `[T]` type parameter,
or the by name parameter on `alternative`,
just use `Int` instead:

~~~ scala
def myFilter
  (action: DBIO[Int])
  (p: Int => Boolean)
  (alternative: Int) = ???
~~~

Go ahead and implement `myFilter`.

We have an example usage from the ship's marketing department.
They are happy to report the number of chat messages, but only if that number is at least 100:

~~~ scala
val marketingCount = exec(
  myFilter(messages.size.result)( _ > 100)(100)
)
~~~

<div class="solution">
This is a fairly simple example of using `map`:

~~~ scala
import scala.concurrent.ExecutionContext.Implicits.global

def myFilter[T]
  (action: DBIO[T])
  (p: T => Boolean)
  (alternative: => T) =
    action.map {
      case t if p(t) => t
      case _ => alternative
    }
~~~


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

~~~ scala
final case class Room(name: String, connectsTo: String)

final class FloorPlan(tag: Tag) extends Table[Room](tag, "floorplan") {
  def name       = column[String]("name")
  def connectsTo = column[String]("next")
  def * = (name, next) <> (Room.tupled, Room.unapply)
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
~~~

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

Write a method `unfold` that will take any room name as a starting point, and a query to find the next room, and will follow all the connections until there are no more connecting rooms.

The signature of `unfold` _could_ be:

~~~ scala
def unfold(
  z: String,
  f: String => DBIO[Option[String]]
  ): DBIO[Seq[String]]
~~~

... where `z` is the starting ("zero") room, and `f` will lookup the connecting room.

If `unfold` is given `"Podbay"` as a starting point it should return an action which, when run, will produce: `Seq("Podbay", "Galley", "Computer", "Engine Room")`.

<div class="solution">

The trick here is to recognize that:

1. this is a recursive problem, so we need to define a stopping condition;

2. we need `flatMap` to pass a value long; and

3. we need to accumulate results from each step.

The solution below is generalized with `T` rather than having a hard-coded `String` type.

~~~ scala
def unfold[T]
  (z: T, acc: Seq[T] = Seq.empty)
  (f: T => DBIO[Option[T]]): DBIO[Seq[T]] =
  f(z).flatMap {
    case None    => DBIO.successful(acc :+ z)
    case Some(t) => unfold(t, acc :+ z)(f)
  }

val path: DBIO[Seq[String]] =
  unfold("Podbay") {
     roomName => floorplan
          .filter(_.name === roomName)
          .map(_.connectsTo).result.headOption
   }

println( exec(path) )
// List(Podbay, Galley, Computer, Engine Room)
~~~
</div>
