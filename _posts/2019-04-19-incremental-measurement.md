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
workers were busy- not only that, but the large blue spike at 16:05? It's time
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

Drawing a timeline of worker activity can make it clear how the moment we update
our metric affects what Prometheus sees. In the diagram below, we map the
timeline of two workers into chunks that represent jobs of varying duration. Two
Prometheus scrapes are labelled at 15s (red) and 30s (blue), with the jobs that
contribute to the metric value at each scrape coloured accordingly.

<figure>
  <img src="{{ "/assets/images/long-tasks-bias-diagram.svg" | prepend:site.baseurl }}" alt="diagram of bias"/>
</figure>

Irrespective of what they work, two fully occupied workers will perform 30s of
work in every 15s interval. As Prometheus doesn't see work until it's complete,
our metric implies 14s of work happened in the first interval and 42s in the
second. If every worker starts working long jobs, we'll report no work being
done until they end, even if that's hours later.

To demonstrate this effect, I created an experiment with ten workers working
jobs of varying duration half-normally distributed between 0.1s and 30s (see
[seed-jobs](https://gist.github.com/lawrencejones/f419e478106ab1ecbe007e7d9a9ca937#file-seed-jobs)).
Despite each worker performing a constant rate of work, graphing the job worked
metric results in a spiky graph that jumps above and below the real measurement
of 10s per second of work:

<figure>
	<a target="_blank" href="https://snapshot.raintank.io/dashboard/snapshot/r9cBxt26Bs1PBI3mqfTS72Cf55dSmeTn">
  	<img src="{{ "/assets/images/long-tasks-experiment-bias.png" | prepend:site.baseurl }}" alt="work by worker with biased measurement"/>
	</a>
  <figcaption>
    Work by worker with biased measurement- under and over reporting
  </figcaption>
</figure>

This biased metric will record no work while we work the longest of jobs, and
place spikes of activity only after they've subsided. But as if this wasn't bad
enough, there's an even more insidious problem with the long-lived jobs that so
screw with our metrics.

Whenever a long-lived job is terminated, say if Kubernetes evicts the pod or a
node dies, what happens with the metrics? As we update metrics only after
completing the job, as far as the metrics are concerned, all that work **never
happened**.

## Restoring trust

Metrics aren't meant to lie to you. Beyond the existential crisis prompted by
your laptop whispering mistruths, observability tooling that misrepresents the
state of the world is a trap and not fit-for-purpose.

Thankfully this is fixable. The crux of this bias is that Prometheus taking a
measurement happens independently of workers updating metrics. If we can ask
workers to update metrics whenever Prometheus scrapes them, just before they
return scrape results, then we'll ensure Prometheus is always up-to-date with
on-going activity.

### Introducing... MetricTracer

One solution to the time-of-measurement bias is a `MetricTracer`, an abstraction
designed to take long-running duration measurements while incrementally updating
the associated Prometheus metric.

```ruby
class MetricTracer
  def trace(metric, labels, &block)
    ...
  end

  def collect(traces = @traces)
    ...
  end
end
```

Tracers provide a `trace` method which takes a Prometheus metric and the work
you want to track. `trace` will execute the given block and guarantee that calls
to `tracer.collect` during execution will incrementally update the associated
metric with however long had elapsed since the last call to `collect`.

We need to hook the tracer into the workers to track the job duration and the
endpoint serving our Prometheus scrape. Starting with workers, we initialise a
new tracer and ask it to trace the execution of `acquire_job.run`.

```ruby
class Worker
  def initialize
    @tracer = MetricTracer.new(self)
  end

  def work
    @tracer.trace(JobWorkedSecondsTotal, labels) { acquire_job.run }
  end

  # Tell the tracer to flush (incremental) trace progress to metrics
  def collect
    @tracer.collect
  end
end
```

At this point, the tracer will only ever update the job worked seconds metric at
the end of the job run, as we did in our original metric implementation. We need
to ask the tracer to update our metric before we serve the Prometheus scrape,
which we can do by configuring a Rack middleware.

```ruby
# config.ru
# https://rack.github.io/

class WorkerCollector
  def initialize(@app, workers: @workers); end

  def call(env)
    workers.each(&:collect)
    @app.call(env) # call Prometheus::Exporter
  end
end

# Rack middleware DSL
workers = start_workers # Array[Worker]

# Run the collector before serving metrics
use WorkerCollector, workers: workers
use Prometheus::Middleware::Exporter
```

Rack is a Ruby webserver interface that allows chaining several actions into a
single endpoint. The above `config.ru` defines a Rack app that, whenever it
receives a request, will first call `collect` on all the workers, then have the
Prometheus client render scrape results. 

Returning to our diagram, this means we update the metric whenever the job ends
or we receive a scrape. The jobs that span across scrapes contribute fairly on
either side, as shown by the jobs straddling the 15s scrape time splitting their
duration evenly. Regardless of the size of our jobs, we've incremented the
metric by 30s (2 x 15s) for each scrape interval.

<figure>
  <img src="{{ "/assets/images/long-tasks-diagram-tracer.svg" | prepend:site.baseurl }}" alt="diagram of tracer collection"/>
</figure>

### Is it better?

Using the tracer has a night-and-day impact on how worker activity is recorded.
Unlike the original measurements where our activity was spiky, with peaks that
exceeded the number of workers we were running and periods of total silence,
re-running our experiment with ten workers produces a graph that clearly shows
each worker contributing evenly to the reported work.


<figure>
	<a target="_blank" href="https://snapshot.raintank.io/dashboard/snapshot/r9cBxt26Bs1PBI3mqfTS72Cf55dSmeTn">
  	<img src="{{ "/assets/images/long-tasks-experiment-before-after.png" | prepend:site.baseurl }}" alt="comparison of biased vs tracer results"/>
	</a>
  <figcaption>
    Comparison of biased (left) and tracer managed (right) metrics, taken from
    the same worker experiment
  </figcaption>
</figure>

In comparison to the outright misleading and chaotic graph from our original
measurements, metrics managed by the tracer are stable and consistent. Not only
do we accurately assign work to each scrape but we are now indifferent to
violent worker death: Prometheus will have tracked the metric up until the
worker disappears, ensuring we don't lose that information if the worker goes
away.

## Can I use this?

TODO

Most of the code snippets have been extracted from GoCardless' fork of
[chanks/que](https://github.com/chanks/que), a Postgres queuing system that has
been instrumented to the hilt with Prometheus metrics, using a `MetricTracer` to
ensure accurate accounting of every part of a worker's lifecycle.

I've collected some of the code used in this post into a
[Gist](https://gist.github.com/lawrencejones/f419e478106ab1ecbe007e7d9a9ca937),
including a full reference implementation of the `MetricTracer`. Any feedback
or corrections are welcome- reach out on Twitter or [open a
PR](https://github.com/lawrencejones/blog.lawrencejones.dev).

---

<figure>
  <img src="{{ "/assets/images/long-tasks-que.png" | prepend:site.baseurl }}" alt="time spent by job class for que"/>
  <figcaption>
    Results from production across many workers
  </figcaption>
</figure>
