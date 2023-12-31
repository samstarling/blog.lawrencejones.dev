---
layout: post
title:  "My most impactful code"
date:   "2022-03-19 12:00:00 +0000"
image:  /assets/images/most-impactful.png
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

## Setting the scene

I rejoined GoCardless in 2016 when the company was 80 people, with 20
engineers across 3 teams.

GoCardless is a payments company offering an API similar to Stripe's, with a
focus on bank-to-bank payments. In the most simple terms, GC receives requests
to create payments, batches them and sends them to the clearing houses for
processing.

The team I joined was Core Payments & Internal Tools (CPIT), whose key
responsibility was to safeguard the payment process. As is traditional in
start-ups, we had began to hit scaling issues around the batch processes that
submitted to the banks, and everyone was very concerned.

Batch processing being key to CPIT, our team were deep in discussion about the
scaling challenge. This being the peak of micro-service hype, there was an
suggestion that our Ruby on Rails monolith was incapable of scaling and that
we'd need a new service that we'd speak to over a message broker, with event
sourcing, etc.

Having arrived late to the conversation, I didn't fully get the concerns about
the monolith. I'd worked at GC a year before during my internship and come away
a big fan: I thought the codebase was solid, enjoyed the simplicitly of a single
service, and felt more infrastructure might make things worse -- not better.

Late one evening, I began to dig into the bad pipeline. This was a batch job
that started at 4pm (our payment submission cutoff) then found and batched all
payments for that daily submission, eventually producing some CSVs which we'd
upload to our bank providers.

The cause of our concern was on high volume days (~200k payments) this process
could take up-to 4hrs, which meant we risked missing the 7pm deadline to submit
files for that day to the banks.

## The code

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
technique for each of the async Que workers, bulding an abstraction to easily
change single-threaded code into a multi-threaded work-group.

I started drafting what that might look like, assuming we built an abstraction
on top of the Que job queue called QueCommit:

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
could transactionally enqueue the batch jobs and have the coordinator
(QueCommit) wait until they finished.

All QueCommit had to do was poll the queue (jobs are stored in Postgres, so a
simple `select * from que_jobs where id = ?`) to check when all outstanding jobs
have finished, then raise an exception if any of them failed.

This worked really, really well. The database wasn't anywhere near capacity and
could support several concurrent batchers without saturation, meaning you'd get
about Nx speed-ups for however many workers we used: for us, that meant about
5-10x improvements.

## That's all?

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

That was short-term, but QueCommit's longevity surprised me.

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

## Hard to quantify

While I'm confident QueCommit is one of the most impactful contributions I've
made, impact over this timescale is really hard to quantify.

As an example, GoCardless continues to run one of the world's largest Ruby on
Rails monoliths. I still believe QueCommit helped avoid a premature splitting of
that monolith, and it's my opinion that running on a monolithic has been a huge
help for GC to scale their business.

But I could make arguments for the other case, too. Because GC so successfully
scaled their monolith, the most painful problems they face now are how to
split it in order to handle the next 10x growth. Maybe without QueCommit, we'd
have been forced to break things up sooner, and perhaps that would have been
better?

I'm not convinced, but that's the issue with complex outcomes like this: we'll
never really know.

Either way, watching QueCommit evolve while GC rebuilt itself several times over
has been a great lesson for me. It's one of the many benefits you get by joining
an early stage company and sticking around, where you get to see which of your
bets come through. I'm certainly grateful for it.
