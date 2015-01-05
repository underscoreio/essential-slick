# Essential Slick

## 1. Introduction

- About this text, prerequisites, versions etc.
- Conventions etc

## 2. The Basics

_Objectives: get readers a working environment where they can try things out, and set scene for examples later in text_

- High-level orientation (short)
  - not an ORM
  - basic concepts

- Introducing an example
  - a RDBMS (it'll be postgres)
  - sbt
  - table
  - inserting data
  - simple queries

- Exercises

## 3. Data modeling

_Objectives: (a) provide the right way to work with data in slick; (b)  introducing more query examples (update and delete)_

- Rows
  - Case classes, tuples, HLists  
  
- Tables 
  - Null columns
  - Row and column control (autoinc etc)
  - Primary keys & value classes

- Custom types & mapping

- Example using date and time?

- Virtual columns and server-side casts here?

- Exercises


## 4. Joins [and queries?]

_Objective Show how joins can be established and general querying magic. Lots of pictures in this chapter. _ 

- implicit v explicit
- one to one
- one to many
- many to one
- inner/outer/auto joins
- union etc
- aggregations?

- Exercises (or possibly throughout)



## 5. Query composition

_Objectives: demonstrate thinking in terms of queries and composing them_

- Not sure of sections yet, but demonstrating pimping for pagination and the like (a.k.a query extensions)
- sorting etc

- Exercises


## 6. Testing

- ???


## 7. Schema management

_Objective: prescribe a way for working with schemas_

- Code generation (database is the truth)
- Schema generation (code is the truth)
  - maybe using Liquibase, and pointing out the limitations of what Slick ships with


----

# BELOW HERE IS OUT OF SCOPE

Maybe in the second edition?

## Compiled queries and optimization 

## Appendix A: integration with Play 2.x

## Appendix B: integration with x


