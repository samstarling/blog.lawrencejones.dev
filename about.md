---
layout: page
title: About
permalink: /about/
feature-img: "assets/img/sample_feature_img_2.png"
---

I'm Lawrence, a Site Reliability Engineer at GoCardless. My team focuses on
scaling our payments API across the globe while providing a reliable and robust
service to our customers.

My writing will centre around the technical challenges I face on my day-to-day.
You can expect to see posts about Postgres, Kubernetes and general engineering
problems that find their way to an SREs desk. Hopefully this can become a
platform for sharing the more interesting technical highlights of an SREs role
within a scale-up organisation.

While I infrequently use Twitter, if you have questions or feedback about the
content then I'll happily field it at
[@lawrjones](https://www.twitter.com/lawrjones).

## Open-Source Projects

These include individual projects, individual efforts that have been adopted by
my company and work that was done purely within my capacity as an employee.

### [stolon-pgbouncer](https://github.com/gocardless/stolon-pgbouncer)

> stolon-pgbouncer extends a stolon PostgreSQL setup with PgBouncer connection
> pooling and zero-downtime planned failover of the PostgreSQL primary.

### [theatre](https://github.com/lawrencejones/theatre)

> This project contains GoCardless Kubernetes extensions, mostly in the form of
> operators and admission controller webhooks. The aim of this project is to
> provide a space to write Kubernetes extensions where:
> 
> 1. Doing the right thing is easy; it is difficult to make mistakes!
> 2. Each category of Kubernetes extension has a well defined implementation
>    pattern
> 3. Writing meaningful tests is easy, with minimal boilerplate

### [pgsql-cluster-manager](https://github.com/lawrencejones/pgsql-cluster-manager)

> pgsql-cluster-manager extends a standard highly-available Postgres setup
> (managed by Corosync and Pacemaker) enabling its use in cloud environments
> where using using floating IPs to denote the primary node is difficult or
> impossible. In addition, pgsql-cluster-manager provides the ability to run
> zero-downtime failover of the Postgres primary with a simple API trigger.

### [diggit](https://github.com/lawrencejones/diggit)

> The goal of Diggit is to provide a tool capable of generating insights about
> code changes in the context of all those that came before them. This tool
> would be run in the code review process to aid decisions about whether the
> proposed change will have a positive impact on the system.

### [coach](https://github.com/gocardless/coach)

> Coach improves your controller code by encouraging:
> 
> - Modularity - No more tangled before_filter's and interdependent concerns.
>   Build Middleware that does a single job, and does it well.
> - Guarantees - Work with a simple provide/require interface to guarantee that
>   your middlewares load data in the right order when you first boot your app.
> - Testability - Test each middleware in isolation, with effortless mocking of
>   test data and natural RSpec matchers.
