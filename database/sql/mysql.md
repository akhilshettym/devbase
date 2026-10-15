# MySQL Mastery Lab

This lab is designed as a **single serialized MySQL 8.x database** that you can run from top to bottom. It uses a realistic enterprise ERP domain so that the SQL concepts appear in realistic relationships instead of isolated toy examples.

## Recommended order

| Phase | What you learn |
|---|---|
| 00–03 | Database creation, DDL, data types, keys, foreign keys, constraints, metadata |
| 04–05 | INSERT, UPDATE, DELETE, upserts, SELECT, filtering, sorting, pagination, NULL |
| 06–07 | Functions, CASE, JSON, aggregation, GROUP BY, HAVING, ROLLUP |
| 08–10 | Joins, anti-joins, set operations, subqueries, EXISTS |
| 11–12 | CTEs, recursive CTEs, window functions, ranking, running totals |
| 13–15 | Views, temporary tables, CTAS, transactions, savepoints, row locking |
| 16–19 | Stored procedures, functions, triggers, events, prepared statements |
| 20–22 | Indexing, EXPLAIN, EXPLAIN ANALYZE, generated columns, advanced DML, data quality |
| 23–24 | Optional database administration and capstone problems |

## What is intentionally covered

The script covers the SQL concepts most useful for becoming strong with MySQL: DDL, DML, constraints, primary/composite/foreign keys, one-to-one/one-to-many/many-to-many/self-referencing relationships, joins, set operators, aggregates, grouping, NULL semantics, conditional expressions, string/date/numeric functions, JSON, generated columns, CTEs, recursive CTEs, window functions, views, temporary tables, CTAS, transactions, savepoints, isolation, row locks, stored routines, triggers, events, prepared statements, indexes, EXPLAIN, EXPLAIN FORMAT=JSON, EXPLAIN ANALYZE, information_schema, and common data-quality patterns.

MySQL 8.0.31+ is assumed for `INTERSECT` and `EXCEPT`; the overall script targets current MySQL 8.x syntax.

## Important notes

1. The first statement drops `mysql_mastery_lab`. Run this against a dedicated learning server/database only.
2. The event section creates an event, but the event will only execute automatically when the MySQL event scheduler is enabled and the account has the needed privilege.
3. The user/role/grant section is commented out because it needs administrative privileges and should not be run blindly on a shared server.
4. The script deliberately uses transactions and rollbacks around destructive demonstrations so the later exercises retain their data.
5. `EXPLAIN ANALYZE` output depends on your MySQL version, optimizer statistics, hardware, and data distribution.

## Suggested mastery workflow

Run one section at a time. After each concept, modify the query rather than only reading the answer. For example, after learning `GROUP BY`, change the grouping dimensions; after learning window functions, change the partitioning/order; after learning recursive CTEs, rewrite the hierarchy query to show depth, chain, or subtree size.

Once the main script is complete, solve the 20 capstone challenges at the end without looking up solutions first.

## Official MySQL references

- MySQL 8.4 Reference Manual: https://dev.mysql.com/doc/refman/8.4/en/
- CTEs: https://dev.mysql.com/doc/refman/8.4/en/with.html
- Window functions: https://dev.mysql.com/doc/refman/8.4/en/window-functions.html
- Views: https://dev.mysql.com/doc/refman/8.4/en/create-view.html
- EXPLAIN: https://dev.mysql.com/doc/refman/8.4/en/using-explain.html
