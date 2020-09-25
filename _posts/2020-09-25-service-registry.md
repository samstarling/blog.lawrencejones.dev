---
layout: post
title:  "Why you need a service registry"
date:   "2020-09-25 12:00:00 +0000"
tags:
  - infrastructure
excerpt: |
  As a teams infrastructure estate grows, it becomes increasingly beneficial to
  create a global registry of all people, services and components.

---

Building a service registry, a structure that tracks all people, services and
systems that interact with your infrastructure, can be extremely powerful.

If you pick the right format, it can be the glue between totally distinct
toolchains. Placing the registy at the heart of all your other tools, you no
longer need to worry about keeping it up-to-date: the registry defines what is
created, rather than describing it. By creatively distributing the registry so
every developer, infrastructure component or one-off script has access by
default, you'll find use cases for this data everywhere.

# What is it?

- Jsonnet library, producing a json structure
- Example service metadata.jsonnet

# Provisioning infrastructure

- Everything can consume json, so you can use this everywhere
- Service registries that describe become stale, use yours to define
- Example service

## Kubernetes

- Define your service, allow the infrastructure to respond
- Provision Kubernetes namespace, rbac, ArgoCD application
- If you've specified a linked Google Cloud Platform project, we'll deploy a
  Config Connector for your namespace

## Google Cloud Platform

- When every resource is tracked in the registry, you can perform complex
  queries to project relationships between resources
- From every service entry, we can find any environments that are linked against
  a GCP project, then create Google IAM permissions for the users on that
  service
- We can create jsonnet files that are views over the registry, and use them to
  answer questions about what permissions are granted to what people, while
  allowing the registry to be the authority

# Tooling

- Making sure you can easily access the registry is key to enabling use cases.

## Discovery

- Go package that tries well known locations, ensuring we can pull it from many
  different environments with minimal config
- Either require this package or use the `utopia registry` command for scripting

## Improving UX

- Now our dev tools have the registry, we can drop assumptions about where or
  how things are deployed, and make more specific decisions
- Loads of developer commands (consoles) no longer require a `--context`
  parameter
- Add resources where needed: logging indices, so we can power `utopia logs`
  command

## Monitoring and alerting

- The data structure is well understood, which means you can translate it into
  other formats
- Template Prometheus recording rules that create a `gocardless_service` time
  series with team and alert channel labels, by mapping over services in the
  registry
- Now we can automatically join common alerts (Kubernetes pod crash-looping)
  onto team specific channels, allowing automatic routing of alerts

# Closing

We're about to release a total reimagining of our infrastructure tools, and the
service registry has been an essential piece of that puzzle. We continue to find
novel uses for this data, and are excited about how we can provide a more
cohesive experience for our developers, through better integrated tooling.

We like how having a registry has made us think- give it a try, and you might
too.
