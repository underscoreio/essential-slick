# More on Joins

## Outer Joins

`leftJoin` - dealing with NULL values

map all columns to option types via `.?` (nullable column)

slick will do this for you one day.

## Auto Join

https://skillsmatter.com/skillscasts/4577-patterns-for-slick-database-applications

15:23 in

table1.joinOn(table2) : Query[(T1,T2),(Ta,Tb)]

via implicit joinCondition for T1,T2

