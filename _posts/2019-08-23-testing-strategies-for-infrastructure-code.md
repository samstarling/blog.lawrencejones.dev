---
layout: post
title:  "Testing strategies for infrastructure code"
alternatives:
date:   "2019-09-01 11:00:00 +0000"
toc:    true
tags:
  - infrastructure
  - testing
audience: Software engineers who work on infrastructure projects
goals: Provide a useful strategy for approaching infrastructure testing
links: []
excerpt: ""
---

When I changed role to SRE, I was happily surprised that- despite warnings to
the contrary- I continued to write almost as much code as I had before. Maybe I
got lucky, or perhaps this change happened at a time when SRE was already
evolving to incorporate more software development; whatever the reason, there
was still opportunity to build great software projects that demanded strong
software engineering skills.

While development remained, the code I wrote was no longer modelling abstract
business systems or adding new product features. These new projects were about
building distributed systems, and leaky abstractions with byzantine failures
become the primary focus instead of something you consider as an afterthought.

---

Developing infrastructure code- maybe better termed 'distributed systems'- is a
bit different than other software. When I first changed role to SRE, one of the
things that I consistently found harder was how to approach testing for the code
I was now writing.

The projects I'd developed before becoming an SRE were at a higher level of
abstraction than what I now faced. Testing business logic around how payments
are handled in a system you control is just different ball game to, say,
verifying your software won't promote the wrong database in a network partition.

---

Ever since my move to SRE, a lot of the projects I've been building would
qualify as 'distributed systems'. In a vicious generalisation, this software is
characterised by deriving its primary value from successfully interacting with
other systems.

These systems tend to care deeply about real world nuances, byzantine failure
and leaky abstractions. Perhaps the best description of life in a distributed
system is [who will guard the gatekeepers](), highlighting the insanely shaky
building blocks our most critical software builds upon

With lots of trial and error, I've developed a
strategy for approaching testing when your software's primary value is to
interact with other systems.

While there is no 'right way' to test software, adopting this model has helped
me be consistent between projects. Consistency is key when on-boarding people
into new projects, and with testing especially, can help encourage writing the
right kind of tests by providing an obvious place to put them.



One of the projects that best follows this pattern is
[stolon-pgbouncer](https://github.com/gocardless/stolon-pgbouncer), a Golang
project that extends a [stolon](https://github.com/sorintlabs/stolon) Postgres
cluster with the ability to perform zero-downtime failover. I'll use examples
from this project to motivate each type of test, and while I encourage readers
to have a peek at the project itself, understanding what stolon-pgbouncer does
is not required to understand the rest of this post.
