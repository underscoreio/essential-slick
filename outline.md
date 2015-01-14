# Essential Slick

- The things you wish you knew before you started using Slick
- We want to get developers up and running with Slick.
- We want them to structure their applications the way you do in reality.
- We want them to see the features they'll need to use programming our way of programming.
- In part based on our experiences with clients.
- Not comprehensive; defer to the Slick Reference documentation.

## Introduction

- About this text, prerequisites, versions etc.
- Conventions etc

## The Basics

_Objectives: get readers a working environment where they can try things out. Touch on all the concepts, indicate we'll look at them later, but not hide anything. Show one way of working for this chapter, indicating there are other ways._

- High-level orientation (short)
  - not an ORM
  - basic concepts

- Introducing an example
  - a RDBMS
  - sbt
  - key concepts
  - simple queries

- Exercises


## Manipulating Data

- Insert

- Update

- Delete

- Exercises


## Data modeling

_Objectives: (a) provide the right way to work with data in slick; (b)  introducing more query examples (update and delete)_

- Application Structure
  - traits and driver imports

- Rows
  - Case classes, tuples, HLists

- Tables
  - Null columns
  - Row and column control (autoinc etc)
  - Primary keys & value classes

- Custom types & mapping
  - Enumerations
  - Arbitrary classes?

- Exercises

## Joins [and queries?]

_Objective Show how joins can be established and general querying magic. Lots of pictures in this chapter._

- implicit v explicit
- one to one
- one to many
- many to one
- inner/outer/auto joins
- union etc
- aggregations?

- Exercises (or possibly throughout)


## Query composition

_Objectives: demonstrate thinking in terms of queries and composing them_

- Not sure of sections yet, but demonstrating pimping for pagination and the like (a.k.a query extensions)
- sorting etc

- Exercises


## Testing

- ???


## Schema management

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


