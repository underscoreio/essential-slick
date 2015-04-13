# Query Composition

TODO: Intro, what you are going to learn.


## Sorting

To order a query use either of the methods `sorted` or `sortWith`.
Both methods take one or more columns

val msgs =  messages.sorted( m => (m.ts,m.id))
select x2."sender", x2."content", x2."ts", x2."id", x2."to", x2."room", x2."readBy" from "message" x2 order by x2."ts", x2."id"



val msgs =  messages.sorted( m => (m.roomId.desc,m.ts.asc))


- and other things we've not discussed that convert query => query.

## Query Extensions

- pimp your queries
- examples: pagination

## Auto Join

- need to re-watch and see if this is relevant here:
https://skillsmatter.com/skillscasts/4577-patterns-for-slick-database-applications
15:23 in
table1.joinOn(table2) : Query[(T1,T2),(Ta,Tb)]

## Compiled Queries

- Motivate: Save query compile time
- Example.


## Take Home Points