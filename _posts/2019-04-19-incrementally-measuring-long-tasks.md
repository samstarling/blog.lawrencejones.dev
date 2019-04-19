---
layout: post
title:  "Incrementally measuring long-running tasks"
date:   "2019-04-19 11:00:00 +0000"
tags:
  - prometheus
  - observability
excerpt: |
  TODO

---

Imagine you have async workers processing jobs from a queue. These workers
consume very different types of job, some processing in milliseconds while
others can take almost 30m to process.

You'll want to measure this system, right? These workers are essential to your
systems running smoothly, doing all the heavy lifting behind the machines that
make your product worth anyones time. One of the most useful questions we can
ask about this system is:

> At any moment, what jobs are workers working, and how much time is spent on
> each job?

You run Prometheus (or something similar) and have a good feeling you can answer
this with just one metric, something like:

```
job_worked_seconds_total{job}
```

If the `job_worked_seconds_total` counter represents the number of seconds
having been worked for a specific job class, then we can use Prometheus' `rate`
function to identify which jobs were being worked at any given time. For those
unfamiliar with `rate`, it translates to the derivative of a time series, or
'rate of change'.

In theory this metric will do the job, but our results will be wrong and
actively misleading depending on how we implement the tracking. Let's step
through three different implementations and evaluate each for simplicitly vs
correctness.

## Naive

## Asynchronous

## Proactive
