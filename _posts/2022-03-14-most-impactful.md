---
layout: post
title:  "My most impactful code"
date:   "2022-03-19 12:00:00 +0000"
image:  /assets/images/todo.png
draft:  true
hackernews: TODO
tags:
  - engineering
excerpt: |
  <p>
    Asked for my most impactful code contribution, I discuss a small change that
    had short and long-lasting impact, far beyond what I originally intended.
  </p>

---

At a team dinner over Mexican food and margaritas, someone asked "what was the
most impactful code you ever wrote?".

I hadn't considered this before and was surprised I had an answer ready. Though
whether the impact was a net positive is something I'm not certain of.

# Setting the scene

I rejoined GoCardless in 2016 when the company was 80 people, with 20
engineers across 3 teams.

For those who don't know, GoCardless is a payments company offering an API
similar to Stripe's, with a focus on bank-to-bank payments. In the most simple
terms, GC receives requests to create payments, batches them and sends them to
the clearing houses for processing.

The team I joined was Core Payments & Internal Tools (CPIT), whose key
responsibility was to safeguard the payment process. As is traditional in
start-ups, we had began to hit scaling issues around the batch processes that
submitted to the banks, and everyone was very concerned about it.

Batch processing being key to CPIT, our team were deep in discussion about how
the scaling challenge. This being the time of micro-service hype, there was an
implicit suggestion that our Ruby on Rails monolith was incapable of scaling
with our payment volume, and that we'd need to break out a new service that we
spoke to over a message broker, event sourcing, all that jazz.

Having arrived late to the conversation, I didn't grok the concerns about the
monolith. I'd worked at GC a year before for my internship, and I confess I
quite liked the monolith! I thought the codebase was really solid, enjoyed the
simplicitly of a single service, and felt more infrastructure might make things
worse -- not better.

Late one evening, I began to dig into the bad pipeline. This was a batch job
that started at 4pm (our payment submission cutoff) then found and batched all
payments for that daily submission, eventually producing some CSVs which we'd
upload to our bank providers.

The cause of our concern was on high volume days (~200k payments) this process
could take up-to 4hrs, which meant we risked missing the 7pm deadline to submit
files for that day to the banks.

# The code

Of the various jobs in this pipeline, the process that found and transitioned
the payments was responsible for the majority of the runtime. In psuedocode, it
looked like this:


```ruby
def run
  PaymentForSubmission.for(date: Date.today).
    find(batch_size: 500).
    each { |payment| payment.mark_as_submitted! }
end
```

This was running for hours, processing payments one-at-a-time. But wait...
we're doing this one at a time? We want this to be fast, but we're using a
single Ruby process and database connection to get it done?

[que]: https://github.com/que-rb/que

While we had async workers based on a Ruby library called [Que][que], there
wasn't an easy abstraction for sequencing jobs after they'd been enqueued. Given
each part of the batch processing pipeline (finding, transitioning, batching)
needed to complete before we started the next, just throwing work into the queue
wasn't going to work.

[openmp]: https://openmp.org/

So we'd found the problem _behind_ the problem: our pipelines were
single-threaded because we had no easy mechanism to parallelise them. Having
used tools like [OpenMP][openmp] before, I thought we could adapt a similar
technique for each of the async Que workers, buulding an abstraction to easily
change single-threaded code into a multi-threaded work-group.

I started drafting what that might look like:

```ruby
# The top-level job that finds and enqueues sub-jobs:
class MarkPaymentsAsSubmitted < Que::Job
  def self.run
    batch_job = MarkPaymentsAsSubmittedBatch
    commit = QueCommit.new(batch_job, payment_batches, parallelism: 3)
    commit.wait do |remaining|
      log(msg: "Polling for remaining...", remaining_batches: remaining)
    end
  end

  def payment_batches
    PaymentForSubmission.for(date: Date.today).
      in_batches(batch_size: 500).
      map { |batch| batch.pluck(:id) }
  end
end

# This job processes a single batch, and is enqueued by QueCommit:
class MarkPaymentsAsSubmittedBatch < Que::Job
  def run(payment_ids)
    Payment.find(payment_ids).
      each { |payment| payment.mark_as_submitted! }
  end
end
```

I figured if you split the work into one job for loading the batches and
coordinating, and another that does the work of transitioning the payments, we
could use a hypothetical `QueCommit` construct to transactionally enqueue all
those batch jobs and wait until they finished.

All QueCommit had to do was poll the queue (jobs are stored in Postgres, so a
simple `select * from que_jobs where id = ?`) to check when all outstanding jobs
have finished, then raise an exception if any of them failed.

This worked really, really well. The database wasn't anywhere near capacity and
could support several concurrent batchers without saturation, meaning you'd get
about Nx speed-ups for however many workers we used: for us, that meant about
5-10x improvements.

# That's all?

Yeah, that's it. Building QueCommit took an evening and the next day, and
gradually changing pipeline jobs to use it was something I did in my spare time
over the next few weeks.

It might not seem that impactful, but in the short-term, this was huge. Adding
concurrency to the pipeline meant the largest volume days would peak at 1.5hrs,
well before we risked crossing the bank deadlines.

Without the pressure of "this can't scale, and our critical pipeline will fall
over!" the multi-month plan to extract banking code into a separate service for
performance reasons lost wind, and only reappeared a couple of years later in a
different guise.

That was short-term, but QueCommit's longevity amazed me.

As GC continued to grow, QueCommit became the go-to solution for scaling these
batch jobs. I'd since moved into the SRE team and no longer worked on the app,
but watched as the abstraction spread over the codebase. People had even
discovered the more subtle bits of the code -- optimisations like handling
single batch workloads differently, and using heuristics to sort the batches --
and started tweaking them for their use case.

By the time I left GoCardless in 2021, QueCommit was used in more than thirty
batch processes, most of which were critical to GC's operation. Despite being
five years old and handling 20x the load it was created for, the implementation
was mostly unchanged.

# Hard to quantify

While I'm confident QueCommit is one of the most impactful contributions I've
made, impact over this timescale is really hard to quantify.

As an example, GoCardless continues to run one of the world's largest Ruby on
Rails monoliths. I still believe QueCommit helped avoid a premature splitting of
that monolith, but perhaps tackling that split earlier would have been better in
the long term: maybe GC would be a productive micro-service company by now, and
paid that debt off long ago?

Equally, supporting Que required us to build significant Postgres expertise
inside the GoCardless engineering function. That expertise biased us to prefer
Postgres as a technology, even when it demanded a lot of upfront investment from
us. An alternate reality would've seen us shift to something like Cloud Spanner
and avoid the long-tail of Postgres scaling the company now faces.

So impactful yes, but I'll never know if the net outcome was positive. Either
way, watching how QueCommit evolved while GC rebuilt itself several times over
has been a great lesson for me, and one I'm grateful to have from my tenure at
GoCardless.
