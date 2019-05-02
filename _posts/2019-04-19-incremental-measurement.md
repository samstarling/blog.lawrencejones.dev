---
layout: post
title:  "Avoid time-of-measurement bias using Prometheus"
date:   "2019-04-19 11:00:00 +0000"
tags:
  - prometheus
  - observability

audience: Basic to advanced Prometheus users who use metrics in their work
goals: Understand time-of-measurement bias, know how a MetricTracer might help
links:
  - https://snapshot.raintank.io/dashboard/snapshot/PFfWQ21fQgeQkF7FGhR4zsiOGOnNFpOr?orgId=2
  
excerpt: |
  TODO

---

Most applications run a 'worker tier' or some deployment that processes
asynchronous work. The work can be varied, from jobs that take just milliseconds
to large hour-long batches. The only common theme is these jobs are essential
for the health of the system, often doing the heavy lifting that makes your
product worth anyone's time.

It's important to measure systems like this to find issues before they affect
users and to debug them when they do. When something breaks and you suspect it's
a problem in the queue, one of the most important questions you can ask is:

> What are the workers doing- what jobs are they working?

When investigating an incident involving workers like this I found myself
totally unable to answer this question despite workers exposing metrics about
their activity. Digging deeper, it became clear that the instrumentation was
subject to a bias so significant that measurements were actively misleading.

This post explores what and how we should measure this system so we can properly
answer these questions. The most simple implementation- the one I fought with
during the incident- will give results that are worse than useless. We'll
understand this bias through experimentation and conclude with an approach that
can be used to ensure reliable measurements.

## The incident

Alerts were firing about dropped requests and the HTTP dashboard confirmed it-
queues were building and requests timing out. About two minutes later pressure
flooded out the system and normality was restored.

Looking closer, our API servers had stalled waiting on the database to respond,
causing all activity to grind to an abrupt halt. The prime suspect wielding
enough capacity to hit the database like this was the asynchronous worker tier,
so you naturally ask what on earth were the workers doing?

The workers expose a Prometheus metric that tracks how they spend their time. It
looks like this:

```
# HELP job_worked_seconds_total Sum of the time spent processing each job class
# TYPE job_worked_seconds_total counter
job_worked_seconds_total{job}
```

By tracking the sum of seconds spent working each job type, the rate at which
the metric changes can identify how much worker time has been consumed. An
increase of 15 over an interval of 15s implies a single continuously occupied
worker (one second for every second that elaspes) while an increase of 30 would
imply two workers, etc.

Graphing worker activity during this incident should show us what we were up to.
Doing so results in this sad graph, with the time of incident (16:02-16:04)
marked with an appropriately alarming red arrow:

<figure>
  <img src="{{ "/assets/images/long-tasks-hole-in-metrics.png" | prepend:site.baseurl }}" alt="hole in worker metrics around incident"/>
  <figcaption>
    Worker activity at time of incident with a notable gap
  </figcaption>
</figure>

As the person debugging this mess, it hurt me to see the graph flatline at
exactly the time of the incident. I'd already checked the logs so I knew the
workers were busy- not only that, but that large blue spike at 16:05? It's time
spent working webhooks, for which we run twenty dedicated workers. How could ten
single threaded workers spend 45s per second working?

## Where it all went wrong

The incident graph is lying to us by both hiding and over-reporting work
depending on where you take the measurement. Understanding why requires us to
consider the implementation of the metric tracking and how that interacts with
Prometheus taking the measurements.

Starting with how workers take measurements, we can sketch an implementation of
the worker process below. Notice that workers will only update the metric after
the job has finished running.

```ruby
class Worker
  JobWorkedSecondsTotal = Prometheus::Client::Counter.new(...)

  def work
    job = acquire_job
    start = Time.monotonic_now
    job.run
  ensure # run after our main method block
    duration = Time.monotonic_now - start
    JobWorkedSecondsTotal.increment(by: duration, labels: { job: job.class })
  end
end
```

Prometheus (with its pull-based metrics philosophy) makes a GET request to each
worker every 15s to record the metric values at the request time. As workers
constantly update the job worked metric, over time we can plot how this value
has changed.

We start seeing our over/under-reporting issue when jobs take longer than the
interval Prometheus scrapes (15s). Imagine a job that takes 1m to execute:
Prometheus will scrape the worker four times in that interval, but the metric
value will only be updated after the fourth scrape.

TODO: Drawing a timeline of worker activity can make it clear how this 
This can be shown if we draw out a timeline of workers including the
jobs they were processing. 

<figure>
  <img src="{{ "/assets/images/long-tasks-bias-diagram.svg" | prepend:site.baseurl }}" alt="diagram of bias"/>
</figure>

---

## What to measure?

If you run Prometheus (or similar) you might decide a single metric is required
to find an answer, something like:

```
# HELP job_worked_seconds_total Sum of the time spent processing each job class
# TYPE job_worked_seconds_total counter
job_worked_seconds_total{job}
```

With this metric tracking the sum of seconds spent working on each job type, the
rate at which it changes can tell us how much worker time has been consumed. An
increase of 15 over an interval of 15s implies a single continuously occupied
worker (one second for every second that elaspes) while an increase of 30 would
imply two workers, etc.

We can use Prometheus' [`rate`](https://prometheus.io/docs/prometheus/latest/querying/functions/#rate)
function to find this value. Expressing this equation in PromQL...

```
# Worker time spent per job, measured over 15s
sum by (job) (rate(job_worked_seconds_total[15s]))
```

In theory `job_worked_seconds_total` will give us what we need, but our results
will be wrong depending on how we implement the tracking. Let's examine two
possible implementations and see how they fare.

## Setup

For testing, we'll use a toy queuing system with 10 workers that select from a
queue of jobs. Each job will be given a pre-determined duration half-normally
distributed between 0.1s and 30s (see [`seed-jobs`](
https://gist.github.com/lawrencejones/f419e478106ab1ecbe007e7d9a9ca937#file-seed-jobs)).

Metrics are scraped from each worker every 5s, and we'll default to a 15s
interval when calculating rates. Our implementation works if we can produce a
graph that clearly shows our 10 workers starting work, then continuing until
they clear the queue:

<figure>
  <img src="{{ "/assets/images/long-tasks-ideal.png" | prepend:site.baseurl }}" alt="ideal time spent per job"/>
  <figcaption>
    Our ideal graph of 10 workers clearing the queue
  </figcaption>
</figure>

## Approach 1: Simple

In the most simple approach, we'll have workers time their jobs and increment
the metric after they complete it.

```ruby
class Worker
  JobWorkedSecondsTotal = Prometheus::Client::Counter.new(...)

  def work
    job = acquire_job
    start = Time.monotonic_now
    job.run
  ensure # run after our main method block
    duration = Time.monotonic_now - start
    JobWorkedSecondsTotal.increment(by: duration, labels: { job: job.class })
  end
end
```

This looks most like standard Prometheus counter usage and matches how you're
probably instrumenting HTTP requests. Running our experiment yields some
interesting results:

<figure>
  <img src="{{ "/assets/images/long-tasks-naive.png" | prepend:site.baseurl }}" alt="time spent by job class for naive approach"/>
  <figcaption>
    <code>
      sum by (job) (rate(job_worked_seconds_total[15s]))
    </code>
  </figcaption>
</figure>

Wait a second... there were 10 workers in this experiment, right? So how could
we possibly do more than 10s of work in a 15s interval? Recalling our ideal
graph, we expected a sharp increase to 10 workers (or worker seconds per second,
if you please) followed by a decline when we clear the queue.

Let's take a closer look at how updating our metric interacts with Prometheus
recording its measurement.

<figure>
  <img src="{{ "/assets/images/long-tasks-bias-diagram.svg" | prepend:site.baseurl }}" alt="diagram of bias"/>
</figure>

The diagram pictures two workers processing jobs of varying duration (4s, 10s,
etc), with red and blue lines marking Prometheus scraping our metrics. Our
implementation updates `job_worked_seconds_total` only after jobs have
completed, leading to job durations only contributing to the scrape after they
complete.

This means our first scrape (red) will capture only 4s + 10s of work, despite
both workers continuously working. The missing 16s (30s - 14s) of activity then
contributes to the next scrape (blue), causing the spikes we see in our graph.

Larger rate intervals will smooth this effect, allowing us to more clearly see
the 10 individual workers:

<figure>
  <img src="{{ "/assets/images/long-tasks-naive-1m.png" | prepend:site.baseurl }}" alt="time spent by job class for naive approach with 1m interval"/>
  <figcaption>
    <code>
      sum by (job) (rate(job_worked_seconds_total[1m]))
    </code>
  </figcaption>
</figure>

This bias becomes much worse when jobs significantly exceed the rate interval.
Sadly, jobs tend to slow when systems are malfunctioning- when you really need
pin-point accurate metrics. For most async worker systems this is so significant
an effect that your metrics become useless, and it's worth remembering that
conventional HTTP metrics are subject to the same (if less noticeable) skew.

## Pre-emptive

The above time-of-measurement issue is caused by metric values becoming stale
while jobs are running. Especially with Prometheus' pull model, we can do better
by pre-emptively updating metric values prior to each scrape request, ensuring
our metrics are up-to-date.

### MetricTracer

We want to incrementally update our Prometheus metric values in a thread
separate from whatever task is processing; let's create an abstraction called
`MetricTracer`
([source](https://gist.github.com/lawrencejones/f419e478106ab1ecbe007e7d9a9ca937#file-metric_tracer-rb))
which can do just this. The tracer is initialised with an empty collection of
traces, where a trace is an on-going measurement with an associated metric,
labels and last-measured time.

```ruby
class MetricTracer
  Trace = Struct.new(:metric, :labels, :time)

  def initialize
    @lock = Mutex.new # safety for concurrent accesses to @traces
    @traces = []      # all on-going traces
  end

  # def trace(metric, labels, &block)
  # def collect(traces = @traces)
end
```

The tracer exposes two public methods, `trace` and `collect`. We'd call `trace`
from code intending to measure a task, while `collect` is called to flush
measurements to Prometheus metrics, something we'll do just prior to returning
our metric results to a scrape request.

We'll focus on `trace` first, which wraps private methods `start` and `stop`.
Respectively, these methods create and remove an on-going trace from our
`@traces` collection. Each trace records the time our tracer last flushed the
progress to its associated Prometheus metric- this allows us to detect the delta
that hasn't yet been recorded whenever we update the associated metric.

```ruby
class MetricTracer
  def trace(metric, labels, &block)
    start(metric, labels)
    block.call
  ensure
    stop(metric, labels)
  end

  private

  def start(metric, labels = {})
    @traces << Trace.new(metric, labels, Time.monotonic_now)
  end

  # Removes on-going trace and updates the associated metric
  def stop(metric, labels = {})
    matching, @traces = @traces.partition do |trace|
      trace.metric == metric && trace.labels == labels
    end

    collect(matching) # not yet defined, see below
  end
end
```

The `collect` method is where we flush our trace values into Prometheus metrics.
For each of the traces, we calculate the time elapsed since we last performed a
`collect` and increment our counter values appropriately. This method is called
whenever we're about to serve our metrics endpoint (`/scrape`) ensuring the
metric values are maximally up-to-date.

```ruby
class MetricTracer
  def collect(traces = @traces)
    now = Time.monotonic_now
    traces.each do |trace|
      # How long has elapsed since we last updated this metric
      time_since_measure = now - trace.time
      # Increment our metric with the delta
      trace.metric.increment(by: time_since_measure, labels: trace.labels)
      # Update our 'last measured' time for subsequent collects
      trace.time = now
    end
  end
end
```

### Using the tracer

Now we have the `MetricTracer`, we can adapt our `Worker` to track
job durations incrementally. We'll expose a `collect_metrics` method that
delegates to the `tracer` for forcing metric updates.

```ruby
class Worker
  def initialize
    @tracer = MetricTracer.new(self)
  end

  def work
    @tracer.trace(JobWorkedSecondsTotal, labels) { acquire_job.run }
  end

  # Tell the tracer to flush (incremental) trace progress to metrics
  def collect_metrics
    @tracer.collect
  end
end
```

The final puzzle piece is to call `collect_metrics` on the workers whenever we
receive a scrape request. Assuming some fluency in the [Rack](https://rack.github.io/)
DSL, it should look something like this:

```ruby
class WorkerCollector
  def initialize(@app, workers: @workers); end

  def call(env)
    workers.each(&:collect_metrics)
    @app.call(env) # call Prometheus::Exporter
  end
end

# Rack middleware DSL
workers = start_workers # Array[Worker]

# Run the collector before serving metrics
use WorkerCollector, workers: workers
use Prometheus::Middleware::Exporter
```

### Is it better?

Using pre-emptive approach has a night-and-day impact on how worker activity
looks when graphed. Unlike the naive measurements where the rate was dominated
by the time-of-measurement bias, the rate (green) is almost exactly the number
of workers we're running and doesn't fluctuate despite the varied jobs worked/s
(yellow).

<figure>
  <img src="{{ "/assets/images/long-tasks-preemptive.png" | prepend:site.baseurl }}" alt="time spent by job class for pre-emptive approach"/>
  <figcaption>
    <code>
      sum by (job) (rate(job_worked_seconds_total[15s]))
    </code>
  </figcaption>
</figure>

## In the wild

The pre-emptive approach works for our experimental setup and has also been
applied to production systems. Most of the code snippets have been extracted
from GoCardless' fork of [chanks/que](https://github.com/chanks/que), a Postgres
queuing system that has been instrumented to the hilt with Prometheus metrics,
with every second of work accounted for.

<figure>
  <img src="{{ "/assets/images/long-tasks-que.png" | prepend:site.baseurl }}" alt="time spent by job class for que"/>
  <figcaption>
    Results from production across many workers
  </figcaption>
</figure>

While more complex than the naive approach, I believe trust in your metrics is
worth the additional complexity an approach like the trace brings. It means we
can answer with certainty questions like asked at the start of the article (what
are the workers doing?), and an uncertain answers are often worse than having no
answer at all.

I've collected some of the code used in this post into a
[Gist](https://gist.github.com/lawrencejones/f419e478106ab1ecbe007e7d9a9ca937).
This includes a full reference implementation of the `MetricTracer`, inclusive
of synchronisation which was omitted from the article for brevity. Any feedback
or corrections are welcome- reach out on Twitter or [open a
PR](https://github.com/lawrencejones/blog.lawrencejones.dev).
