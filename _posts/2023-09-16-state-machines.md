---
layout: post
title:  "Use your database to power state machines"
date:   "2023-09-16 12:00:00 +0000"
image:  /assets/images/state-machines.png
tags:
  - engineering
excerpt: |
  <p>
    If you build a state machine on top of a relational database you can
    abstract concurrency problems away from your business logic and allow
    developers to write safe-by-default code without dealing with concurrency
    concerns.
  </p>
  <p>
    This post explains how to build a library that offers those protections, and
    how they work under-the-hood.
  </p>
---

Most people are familiar with state machines and know their value. The average
state machine library can help you model states, prevent invalid transitions,
and produce diagrams that help even non-technical people understand how the code
behaves.

This article isn't about making the case for state machines. It's about how you
take the concept of a state machine and have it work alongside your database
models, leveraging your relational database (say Postgres or MySQL) to help you
build concurrent-safe and efficient software.

[statesman]: https://github.com/gocardless/statesman

I first encountered this pattern when I joined GoCardless in 2015. Processing
bank payments is a multi-day affair and extremely stateful, so it's no surprise
that the team eventually built a library called [Statesman][statesman] that
provided a state machine powered by underlying transition tables.

Most of GoCardless' critical processes use Statesman, and by the time I left we
had transition tables with well over 10B rows. It became such an essential tool
that I'd argue it was a powerful competitive advantage. Statesman is even
reflected externally, such as in the GoCardless public API with endpoints
providing rich audit trails.

So if you use Ruby, grab Statesman and get going. But for those who want these
benefits but are non-Ruby'ers, you can implement a small library in your
language of choice in just a few hours provided you understand the nuances of
transition tables, locking, and edge cases.

That's what I did the other day at incident.io. Here's a guide so you can do it
too.

## Transition tables

Let's begin by saying that in most applications, you want to be capturing every
transition that a resource has made through a state machine and storing it for
later analysis. In some situations, you may even consider the history of
transitions to decide which state to transition to next.

That's why the first component of any database state machine will be creating a
table to contain transitions.

```sql
-- Assuming the payments table is already here.
create table payments (/* ... */);

create table payment_transitions (
  id text primary key default generate_ulid() not null,
  payment_id text not null references payments(id),
  to_state text not null,
  most_recent boolean not null,
  sort_key integer not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
```

Each transition row states:

- The parent resource it belongs to (`payment_id`)
- The state this transition is moving into (`to_state`)
- Whether this transition is the latest (`most_recent`)
- An ordinal to allow for logical ordering of transitions (`sort_key`)

Now we add two index-backed unique constraints that are going to ensure our
state machine's integrity.

```sql
create unique index idx_payment_transitions_by_parent_most_recent
on payment_transitions
using btree(payment_id, most_recent)
where most_recent;

create unique index idx_payment_transitions_by_parent_sort_key
on payment_transitions
using btree(payment_id, sort_key);
```

The first ensures we can only ever have a single transition that is
`most_recent` for any payment, a clear requirement if we ever want to sensibly
ask "what state is this payment in?". The second ensures we get no duplicates on
`sort_key`: less important, but useful to ensure all transitions can be strictly
ordered.

## Expressing the state machine in code

Now we have a table we'll use to store transitions, we need to build a library
that can be used to express the state machine in our codebase.

In the Go library we're using at incident.io, we start by expressing the
transition table as a domain model that our ORM can work with:

```go
type PaymentTransition struct {
  // ID is the unique ID of this transition
  ID string `json:"id" gorm:"type:text;primaryKey;default:generate_ulid()"`
  // PaymentID is a reference to the parent resource
  PaymentID string `json:"payment_id"`
  // ToState is where this transition was to
  ToState PaymentState `json:"to_state"`
  // MostRecent is true when this transition is the most recent
  MostRecent bool `json:"most_recent"`
  // SortKey provides ordinality over transitions
  SortKey int `json:"sort_key"`
  // CreatedAt is set upon transition creation
  CreatedAt time.Time `json:"created_at"`
  // UpdatedAt is set whenever this transition is modified
  UpdatedAt time.Time `json:"updated_at"`
}

func (PaymentTransition) Parent() Payment {
  return Payment{}
}

func (a PaymentTransition) State() PaymentState {
  return a.ToState
}

// ParentColumn tells our machine library what column refers
// to the parent resource.
func (PaymentTransition) ParentColumn() (structField, column string) {
  return "PaymentID", "payment_id"
}
```

You'll notice `PaymentState` is a new type, which we define as a Go enum value:

```go
type PaymentState string

const (
  PaymentStatePendingSubmission PaymentState = "pending_submission"
  PaymentStateSubmitted         PaymentState = "submitted"
  PaymentStatePaid              PaymentState = "paid"
  PaymentStateCancelled         PaymentState = "cancelled"
)
```

Finally, we have the parent resource (`Payment`) implement a `Machine()` method
that ties all this together and tells our library about valid transition paths:

```go
func (p *Payment) Machine() machine.Machine[PaymentTransition, Payment, PaymentState] {
  return machine.New[PaymentTransition, Payment, PaymentState](
    p, machine.Configure(
      machine.From(PaymentStatePendingSubmission).To(
        PaymentStateSubmitted,
      ),
      machine.From(PaymentStateSubmitted).To(
        PaymentStatePaid, PaymentStateCancelled,
      ),
    ),
  )
}
```

`machine.New` builds a config struct that records each of the states and where
they are permitted to transition into. In our example, that means
`pending_submission` is allowed to transition to `submitted`, but not to `paid`
or `cancelled`.

```go
package machine

type Config[State comparable] struct {
  states map[State][]State
}
```

## Executing a transition

Our code knows everything it needs to model transitions now, and we can
transition a payment like so:

```go
transition, err := payment.Machine().
  TransitionTo(domain.PaymentStatePendingSubmission).
  Execute(ctx, db)
```

Really simple, but what does this give us? Why is using our database for this
better than simply doing things in-memory?

Well, even when there are concurrent processes transitioning the same payment,
the transition will only be created if the source -> destination is permitted in
our configuration. That's extremely useful for most modern applications which
have many processes working at once, but want their developers to write code
that acts as if it's a single-process system.

For `Execute()` to provide this guarantee you need to know how your database is
configured and be careful about how you take locks. But assuming you're running
Postgres in `read committed` mode (the default) then you can copy this code and
know you're safe.

In SQL, as that's what `Execute()` is really running, the function looks like
so:

```sql
begin;

-- (1)
update payment_transitions
set most_recent = 'f'
where most_recent
and payment_id = 'PM123'
returning *;

-- (2)
/* use previous result to validate transition from -> to */

-- (3)
insert into payment_transitions (
  payment_id, sort_key, most_recent, to_state
)
values (
  'PM123', 20 /* previous sort_key + 10 */, 't', 'submitted'
);

commit;
```

The first update (1) will lock the previously most recent transition, and block
any competing transactions (this means they halt until the lock is released).

The first to win is returned the previous transition and can check that moving
from the previous state to the next desired state is permitted, and will
rollback the transaction if it is not. In the Go implementation I shared above,
that means checking the `Config` struct to make sure this is permitted.

Finally, if the transition is valid, we'll insert a new transition row for the
destination state with `most_recent` set and `sort_key` advanced from the
previous transition row, relying on the unique indexes to catch any conflicts.

That's how a successful transaction that was the first to attempt a transition
will run, and any subsequent transactions will follow one of two paths:

### (a) Initial transition fails

If the first transaction fails then we rollback, release the lock, the competing
transaction acquires it and proceeds as if the first transaction never occurred.

This reduces to "start again".

### (b) Initial transition succeeded

If the first transaction suceeded, the update will unlock but return zero rows
from a read committed Postgres.

This looks to us like either (i) there was no transition and we should assume
this is will be the initial entry for this parent or (ii) we've been beaten by a
competing transaction.

We proceed by pretending like it's the initial transition as in the case of:

- (i) We'd be correct, and we create the initial transition successfully.
- (ii) We're about to try creating another `most_recent` transition and our
  insert will fail against the `most_recent` unique index.

## Ergonomic APIs

Developers who use the machine APIs benefit from the concurrency protections
without needing to think too much about them.

When we hit conflicts, the library returns `ErrTransitionConflict` and we have a
helper that retries if this error is returned. That means you can 'solve'
concurrent processes racing against each other by just wrapping your code in a
retry, which would otherwise require someone to think carefully about their
concurrency model and bring that complexity into their normal application code.

With all your transitions in the database, it becomes efficient and easy to find
all X in state Y by leveraging database indexes. The API and resulting SQL looks
like this:

```go
/*
select
   *
from payments
join
  payment_transitions
  on payments.id = payment_transitions.payment_id
  and most_recent = 't';
*/
payments, err := domain.NewQuerier[domain.Payment](db).
  Joins(machine.InState[domain.PaymentTransition, domain.Payment](db,
    domain.PaymentStatePendingSubmission,
  )).
  Find(ctx)
```

We've also allowed `TransitionTo` to receive arbitrary partials that set
auxiliary fields on transition tables, so that you can track associated
metadata against transitions that need them.

An example would be to attach a submission ID whenever you move a payment to
submitted, where that will set a `submission_id` column on the resulting
transition row:

```go
transition, err := payment.Machine().
  TransitionTo(domain.PaymentStatePendingSubmission).
  With(
    domain.PaymentTransitionBuilder.SubmissionID(payload.SubmissionID),
  )
  Execute(ctx, db)
```

## Just try it

I've use banking examples in this post, but don't think this is limited to
payments. We use this at incident.io to:

- Power incident updates, where each update has a message, severity, status etc
  and `incident_updates` is the transition table.
- Track the status of alert sources so we can record when something was setup,
  activated, or deactivated and why that happened.
- Our nudges feature creates 'nudge runs' that are transitioned as we work them.

Provided you follow the instructions I've given, you'll inherit the concurrency
protections and if you try it out, I promise you'll soon realise their value.
Even if it's when your Data team notice how easy it is to build their models,
because there's much richer data available and arranged consistently than you
have before.

Low cost, high upside. Give it a shot.
