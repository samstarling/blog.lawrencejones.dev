---
layout: post
title:  "In fintech, always keep the receipts"
date:   "2022-10-03 12:00:00 +0000"
image:  /assets/images/todo.png
tags:
  - fintech
  - engineering
excerpt: |
  TODO

---

Something you learn when writing financial software is you to always, always,
keep the receipts.

In engineering terms, this means building systems that preserve the
chain-of-custody around money flows, and can easily draw lines from a
transaction back to the process that initiated it.

Spending time in that environment teaches you to approach and think about
problems differently. In fact, it's so formative that I've noticed interview
candidates with payments or banking backgrounds will propose very similar
solutions to technical problems, despite coming from totally different
companies.

Some things you have to learn the hard way, but I think a lot of these
ways-of-working can be taught, and would be useful to those in fintech and
outside of it.

I'm going to try doing just that, by walking you through how you might solve an
incident in a payments company, loosely based on a real example. I'll connect
the engineering principles to the real-world constraints they address, leaving
an impression of how you might think when a software bug could cost you
millions.

---

Imagine you work for a payments company, where your customers are merchants who
take payments from their own customers.

One of your customers has gone into administration. As the payment provider, you
must work with the appointed administrator and insurance companies to issue
refunds to this merchant's customers who had bought services that they can no
longer make use of.

In terms of scale, we're looking at:

- ~$1B of payments
- ~2M customers
- ~20M payments (~10 payments per customer)

Thankfully this merchant was insured, which means the funds are available to
provide the refunds, but there is a process required to authorise payout:

1. Administrator provides a batch of customers eligible for a refund
2. We locate those customers in our system and payments elegible for refunding
3. Administrator and insurer sign-off on the refund batch, both in terms of
   customers impacted and dollar-amount
4. We execute the refund

The administrator is having a great time learning how messy the merchant's books
had been, so we'll need to repeat a this process several times until all
customers are refunded.

So that's the brief, where do you start?

## Design your pipeline

Most payment processes are modelled as pipelines, where your transaction/etc
moves through several stages of processing.

Our system is no different, and is going to be a pipeline that:

- Receives CSV of customer IDs from the administrator
- Generate batches of eligible payments
- Batch eligible payments for submission
- Generate files for each submission batch
- Send each submission file to the bank for processing

- Advantages of pipelines:
  - Can insert explicit gates
  - Acknowledges that entities are lost between each stage without totally
    crashing
  - Can be restarted from any individual stage

## Trust nobody

- Each stage should verify its input, so that if any stage was to malfunction,
  the next can help catch the errors
- Build invariants into the system, such as database indexes

## Plan for failure

- Build mechanisms to restart or redo each stage, if something fails downstream
- Pipelines that have to be re-run from the start are fragile, as you may need
  to regenerate results quickly
- Similarly, pipelines that can't explicitly void results can leave you second
  guessing the safety or viability of retries. Make sure you can void any
  intermediate result and a re-run of the pipeline will re-build whatever is yet
  to be done but is not void (pending, complete, void).

---

- Break a pipeline into parts
- Store any intermediate working, e.g. payment batches
- Any external output should also be stored, and checksummed
- All calculations should be incremental, and restartable
- Plan for failure by allowing recalculation from different stages

- Significant incident that requires refunding $1B to thousands of recipients
- Existing payments in the system
- Regulatory oversight of batches, with approval required before sending
- External system that had limits on submission file format

```
create table batches (
  id bigint primary key,
  external_batch_id text not null,
  filtered_batch_id text not null,
  filtered_batch_checksum text not null,
  voided_at timestamptz,
);

create table batch_refunds (
  id bigint primary key,
  batch_id bigint references batches(id) not null,
  payment_id text references payments(id) not null,
);
```
- Batch
  - has many Credits
  - 

- Plan
  - Data team provide a list of customers that are eligible for refund
  - Provide CSV of customer IDs to system, filter for customer payments which
    are available to be refunded
  - Track membership into a batch as a join table, 
