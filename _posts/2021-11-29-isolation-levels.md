---
layout: post
title:  "What developers find surprising about Postgres transactions"
date:   "2021-11-29 10:00:00 +0000"
image:  /assets/images/isolation-levels.png
hackernews: https://news.ycombinator.com/item?id=29379525
tags:
  - postgres
excerpt: |
  <p>
    When in a Postgres transaction, the data you read can change underneath you.
    Did you realise this? Many don't, for good reasons.
  </p>

---

> When should I use a transaction in Postgres? And why would I lock?

Is a question I was asked the other day, and one I’ve answered a few times
before.

When dealing with Postgres there are details of the answer that surprise people,
and even senior developers with lots of experience can be caught off-guard.

## When should I use a transaction in Postgres?

There is no common definition of a transaction, and in Postgres what your
transaction offers will depend on the [isolation
level](https://www.postgresql.org/docs/current/transaction-iso.html). This can
be understood as an adjustable toggle that controls how strong the guarantees
will be, usually at the cost of performance.

Postgres ships with a default isolation level of `read committed`, which I’ve
never had reason to change. This level means transactions can only ever read
data that has been committed to the database- ie, the user making the change did
it outside of a transaction or has issued a `COMMIT;`.

It follows that when you begin a transaction and have not yet committed, any
updates you make are only visible to you- they cannot be read by any other users
in the database.

That’s not all, though- `read committed` means during your transaction, you will
continue to read the most up-to-date committed changes in the database, even if
they were committed during your transaction.

Imagine we run:

```sql
/* 1 */ begin;
/* 2 */ select * from organisations where id = 'bananas';
/* 3 */ select * from organisations where id = 'bananas';
/* 4 */ commit;
```

Under a common mental model of transactions, you might imagine that when you
read the organisation in query (3), you’ll get the same result as in query (2).

That’s not the case in `read committed`- there is no guarantee that a different
transaction didn’t update `bananas` after (2), but before (3), causing your
version of `bananas` to change even while within your own transaction.

This phenomenon is called a non-repeatable read, when a transaction reading the
same data can receive different results. In my experience, most developers
believe transactions will prevent this, which can have nasty consequences.

So if `read committed` transactions don’t provide a stable snapshot of the
world, what do we use them for?

Transactions should be used to make one-or-more changes that should be either
accepted or rejected together (an atomic change) when it wouldn’t be appropriate
for other users of the database to see any in-between state.

If you want repeatable reads in a `read committed` world, you’ll need to add
some locking.

## And when should I lock?

The nonrepeatable read (reading something, then reading it again and getting a
different result) from our previous example could be an issue, if an application
isn't built to handle other users modifying the data until it's done with it.

[postgres/explicit-locking]: https://www.postgresql.org/docs/current/explicit-locking.html#LOCKING-ROWS

In `read committed` world, you can opt-into stronger defenses using an [explicit
row lock][postgres/explicit-locking]. Our example can be amended with a `FOR
UPDATE` modifier:

```sql
/* 1 */ begin;
/* 2 */ select * from organisations where id = 'bananas' for update;
/* 3 */ select * from organisations where id = 'bananas';
/* 4 */ commit;
```

In this circumstance, query (2) has acquired an update lock on `bananas` which
will block any other transaction from modifying the row until our transaction
commits.

If no one is permitted to modify the data, it follows that it cannot change
throughout our transaction, ensuring repeatable reads.

## Surprised?

This might be old news to some, but I think it’s normal not to know this.

[mysql/default]: https://dev.mysql.com/doc/refman/8.0/en/innodb-transaction-isolation-levels.html#isolevel_repeatable-read

For one, [MySQL ships by default with `repeatable read`][mysql/default],
so anyone moving from MySQL to Postgres needs to be trained to adjust their
expectations- even Staff engineers with decades of database experience could be
using the wrong mental model.

My personal experience suggests most engineers aren’t aware, or haven’t thought
about this. If your company uses Postgres and depends on data consistency, you
may want to shout louder about this- just saying “you know your data might
change during a transaction?” should be enough to get people’s attention!

----------

This post was written in practical terms, trying to avoid the details of other
isolation levels and how they are implemented. If you'd like to know more, take
a look at:

- [Postgres Concurrency Control](https://www.postgresql.org/docs/current/transaction-iso.html) docs are a good database-specific reference, with examples at each isolation level
- Brandur’s amazing [How Postgres Makes Transactions Atomic](https://brandur.org/postgres-atomicity) to understand how Postgres implements isolation levels
- [Designing Data-Intensive Applications](https://www.oreilly.com/library/view/designing-data-intensive-applications/9781491903063/) for an amazing foundation in isolation levels across a variety of technologies
