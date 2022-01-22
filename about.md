---
layout: page
title: About
permalink: /about/
feature-img: assets/images/feature-london.jpg
---

[gocardless]: https://gocardless.com/
[incident.io]: https://incident.io/
[me@twitter]: https://www.twitter.com/lawrjones
[me@mailto]: mailto:lawrjone@gmail.com?subject=Hey!

I'm Lawrence, a Product Engineer working at [incident.io][incident.io], building
an incident response tool that can help respond and learn from incidents.

Before incident I worked as a Principal Engineer at [GoCardless][gocardless],
where I worked on a number of projects within both the SRE space and the
product.

This blog is about sharing what I've learned so other people can benefit, and
getting better at doing that sharing. The themes will be drawn from my work, so
expect technical subjects like Postgres and Kubernetes and broader themes like
incident response or career development.

If you enjoy what I write and want to hear more, follow me
[@lawrjones][me@twitter] where I'll post any new content. Similarly, if you have
any questions about my writing then don't hesistate to message- I love hearing
other people's perspective and am always up for a (remote or otherwise!) coffee.

## Open-Source Projects

For an idea of what I've worked on, here's a list of projects that I've worked
on which I've been able to open-source.

These include individual projects, personal efforts that have been adopted by my
company, and work that was done purely within my capacity as an employee.

### <a target="_blank" href="https://github.com/lawrencejones/pgsink">pgsink</a>

pgsink is a Postgres change-capture device that supports high-throughput and
low-latency capture to a variety of sinks.

- **Simplicity**: by default, everything will just work
- **Performance**: even extremely high volume or large Postgres databases should
  be streamable, without impact to existing database work
- **Durability**: no update should be lost

Not yet complete, but on a slow and steady march to v1. I expect other tools to
speed past me before I ever get there, but I'll only make this public when it's
really worth considering using.

Watch this space!

### <a target="_blank" href="https://github.com/gocardless/stolon-pgbouncer">stolon-pgbouncer</a>

stolon-pgbouncer extends a stolon PostgreSQL setup with PgBouncer connection
pooling and zero-downtime planned failover of the PostgreSQL primary.

### <a target="_blank" href="https://github.com/lawrencejones/theatre">theatre</a>

This project contains GoCardless Kubernetes extensions, mostly in the form of
operators and admission controller webhooks. The aim of this project is to
provide a space to write Kubernetes extensions where:

1. Doing the right thing is easy; it is difficult to make mistakes!
2. Each category of Kubernetes extension has a well defined implementation
   pattern
3. Writing meaningful tests is easy, with minimal boilerplate

### <a target="_blank" href="https://github.com/lawrencejones/pgsql-cluster-manager">pgsql-cluster-manager</a>

pgsql-cluster-manager extends a standard highly-available Postgres setup
(managed by Corosync and Pacemaker) enabling its use in cloud environments
where using using floating IPs to denote the primary node is difficult or
impossible.

In addition, pgsql-cluster-manager provides the ability to run zero-downtime
failover of the Postgres primary with a simple API trigger.

### <a target="_blank" href="https://github.com/lawrencejones/diggit">diggit</a>

The goal of Diggit is to provide a tool capable of generating insights about
code changes in the context of all those that came before them. This tool would
be run in the code review process to aid decisions about whether the proposed
change will have a positive impact on the system.

### <a target="_blank" href="https://github.com/gocardless/coach">coach</a>

Coach improves your controller code by encouraging:

- **Modularity**: No more tangled `before_filter`'s and interdependent concerns.
  Build Middleware that does a single job, and does it well.
- **Guarantees**: Work with a simple provide/require interface to guarantee that
  your middlewares load data in the right order when you first boot your app.
- **Testability**: Test each middleware in isolation, with effortless mocking of
  test data and natural RSpec matchers.
