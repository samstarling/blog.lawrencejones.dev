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
created, rather than describing it.

By creatively distributing the registry so every developer, infrastructure
component or one-off script has access by default, you'll find use cases for
this data everywhere.

As part of a revamp of our infrastructure tooling, we've introduced a service
registry into GoCardless. This post explains how we built the registry and some
of the use cases we've found for it.

# What is it?

The GoCardless service registry is a Jsonnet library, stored as a file inside
the same Git repository that contains our infrastructure configuration. Jsonnet,
for those not familiar, is an extension to JSON that aims to support flexible
reuse and customisation of data structures.

Jsonnet files evaluate to JSON, and the service registry is no different:

```console
$ jsonnet registry.jsonnet
{
  "clusters": [...],
  "services": [...],
  "teams": [...],
  "projects": [...],
  ...,
}
```

Perhaps you thought a service registry was a webserver, maybe hooked up to a
database, serving the data via a REST API? That wouldn't be strange, and there
are many systems that do just that, but I'd suggest the approach of a single
JSON/Jsonnet file has several advantages:

- It's just data, and your registry is only as good as the data you put in it.
  Especially as you begin, any time building an API or hosting a service is a
  distraction from establishing the right data model for your infrastructure
- If you've already adopted Git-ops workflows, tracking changes to the registry
  in Git should feel very natural
- JSON files are so universally compatible that you'll be able to use this
  anywhere

From the output of the `jsonnet registry.jsonnet` command, you can see we're
tracking our Kubernetes `clusters`, any `services` that we run, organisation
`teams` who interact with the services, and Google Cloud Platform `projects`.

You don't need to start by tracking all these types, but the simplicity of a
Jsonnet library means it costs very little to add a new type. We began with
`services`, then wanted to ensure no service referenced an invalid team. It was
a natural evolution to add `teams`, and this pattern has happened many times
over.

## Service entry (make-it-rain)

Our registry began as a list of services, where each service had a
`metadata.jsonnet` that generated its service entry.

For the purpose of this post, imagine we have a (fake) service called
`make-it-rain`, which has a service entry that looks like this:

```jsonnet
// Example service called make-it-rain, powering a dashboard of falling
// gold coins whenever anyone takes a payment via GoCardless.
//
// Banking teams love money, which is why they created this dashboard.
// It's officially owned by banking-integrations, but core-banking
// sometimes optimise the React code.
//
// It consumes data about new payments from Google Pub/Sub, and has a
// separate Google Cloud Platform project for each of its environments,
// of which there are two: staging and production.
service.new('make-it-rain', 'gocardless/make-it-rain') +
service.mixin.withTeam('banking-integrations') +
service.mixin.withGoogleServices([
  'pubsub.googleapis.com',
]) +
service.mixin.withEnvironments([
  environment.map(
    // By default, every environment should have banking-integrations as
    // admins, and core-banking as operators (they provide on-call cover
    // for the falling gold coins).
    environment.mixin.rbac.withAdmins('banking-integrations') +
    environment.mixin.rbac.withOperators('core-banking'),
    function(environment) [
      environment.new('staging') +
      environment.mixin.withGoogleProject('gc-prd-make-it-stag-833e') +
      environment.mixin.withTargets([
        argocd.new(context='compute-staging-brava', namespace='make-it-rain'),
      ]),
      // Unlike most services, the production environment should permit
      // a non-engineering team to open consoles. Sometimes we take a
      // manual payment outside of GoCardless, and banking-operations
      // open a make-it-rain console and run a script, so we don't miss
      // any gold coins.
      environment.new('production') +
      environment.mixin.rbac.withOperatorsMixin('banking-operations') +
      environment.mixin.withGoogleProject('gc-prd-make-it-prod-1eb1') +
      environment.mixin.withTargets([
        argocd.new(context='compute-banking', namespace='make-it-rain'),
      ]),
    ],
  ),
])
```

Take a moment to read the Jsonnet- this produces a JSON structure that
you can see [here](TODO). It includes a definition of the service and
all its environments, with a list of deployment targets for each
environment that defines where the deployment lives.

There's some configuration of team permissions and Google Cloud Platform
references- we'll see how we can use them next.

# Provisioning infrastructure

Once you have a list of service entries like make-it-rain, we can use it
to tightly integrate with all the rest of our infrastructure tools.

Most infrastructure teams deal with many (in my mind, too many) tools.
The GoCardless team provisions infrastructure with terraform, manages
virtual machines with Chef, and Kubernetes and resources with Jsonnet
templating. Other teams may use far more.

Thankfully, our service registry is plain ol' JSON, and easily consumed
by all of these tools. This means we can start using the registry to
define, not just describe, what infrastructure we create.

## Kubernetes

When someone creates a service like make-it-rain, we'll import their entry into
the registry. Our CD pipelines will detect a registry change and begin
provisioning core resources required for every service.

First, we have a Jsonnet templated cluster service that we use to create
privileged Kubernetes cluster resources, such as namespaces. As the templating
imports the registry as just another Jsonnet file, it will detect we're missing
a namespace (`make-it-rain`) in the `compute-staging-brava` and
`compute-banking` clusters, and automatically create them.

After we have a namespace, we'll create the supporting resources.  Included in
this are resource quotas, limiting the amount of cluster resource make-it-rain
could consume- these limits can be tweaked or overriden in the cluster service
Jsonnet:

```jsonnet
// utopia/services/cluster/instances/compute-staging.jsonnet
cluster {
  spaces+: {
    'make-it-rain'+: {
      quota+: {
        spec+: {
          // These React apps are getting crazy...
          hard+: { cpu: '32', memory: '32Gi' },
        },
      },
    },
  },
}
```

Permissions are one of the more complicated things about managing Kubernetes
clusters. Especially when aiming for a Devops workflow, with application
engineers empowered to care for their own Kubernetes resources, you want to
establish a consistent permission model up-front, as consistent mental models
allow you to explain your security stance during audits, and help engineers work
across multiple projects.

Your registry, being the authoritive definition of service RBAC, can be used to
power your Kubernetes RBAC and enforce that consistency. Looking at our
make-it-rain production environment, we can see the RBAC fields:

```json
{
  "type": "Service",
  "spec": {
    "name": "make-it-rain",
    "repository": "gocardless/make-it-rain",
    "team": "banking-integrations",
    "environments": [
      {
        "type": "Environment",
        "spec": {
          "name": "staging",
          "rbac": {
            "admins": [
              "banking-integrations"
            ],
            "operators": [
              "core-banking"
            ],
            "viewers": []
          }
        }
      },
      ...
    ]
  }
}
```

We made a decision to model just three roles for a service, viewer, operator and
admin. We also thought it would be great if all human permission grants were
derived from these role members, on the service environments.

Now we have this data in the registry, we can:

- Identify the list of teams who are viewers, operators, or admins for any
  services that exist within each cluster namespace
- Use these lists to create `RoleBinding`s in the service namespace, which grant
  the permissions in practice

We implement this in a single file, `cluster/app/spaces-rbac.jsonnet`, which
allows us to map over all namespaces in a cluster and provision the
`RoleBinding` Kubernetes resources. Jsonnet is great for this type of data
manipulation, proving–yet again!–how using a static registry does not limit your
ability to manipulate the data.

## Google Cloud Platform

- When every resource is tracked in the registry, you can perform complex
  queries to project relationships between resources
- From every service entry, we can find any environments that are linked against
  a GCP project, then create Google IAM permissions for the users on that
  service
- We can create jsonnet files that are views over the registry, and use them to
  answer questions about what permissions are granted to what people, while
  allowing the registry to be the authority

It's not just Kubernetes resources in Jsonnet, though. GoCardless is a heavy
user of Google Cloud Platform, and if this permission model is sound, we should
be able to apply it to our Cloud estate too.

For this, we have a terraform project called `registry` which loads our
`registry.jsonnet` using the Jsonnet terraform provider. Just as with Kubernetes
resources, we query into the registry to derive the GCP permissions required for
each of our service environments.

Looking at the make-it-rain staging environment, you'll notice a `googleProject`
field:

```console
{
  "type": "Service",
  "spec": {
    "name": "make-it-rain",
    "repository": "gocardless/make-it-rain",
    "team": "banking-integrations",
    "environments": [
      {
        "type": "Environment",
        "spec": {
          "name": "staging",
          "googleProject": "gc-prd-make-it-stag-833e"
          "rbac": { ... },
        }
      },
      ...
    ]
  }
}
```

This field means our staging environment is *linked* against the Google project
with project ID `gc-prd-make-it-stag-833e`. This means GCP resources for this
environment exist in that Google project- it also means our cluster service will
provision a [Config Connector](TODO) instance for the `make-it-rain` namespaces,
allowing developers to provision Google Cloud Resources like a CloudSQL by
creating Kubernetes resources, something we're finding very useful.

Returning to permissions, this means we know what Google project we need to
create them in. And from our RBAC, we know who has which viewer, operator, or
admin role.

The missing piece is what Google IAM roles to grant. For this, you may have
noticed a mention of Google services in the original make-it-rain service entry:

```jsonnet
service.mixin.withGoogleServices([
  'pubsub.googleapis.com',
]) +
```

This tells us that make-it-rain makes use of Google Pub/Sub. Using this, we can
use some additional config that maps Google services to appropriate IAM
permissions for each role:

```jsonnet
// Configure the Google IAM roles we want to bind people of different role
// (viewer/operator/admin) type to, depending on what Google service they are
// configured to have access to.
googleServiceIAMRoles: {
  'pubsub.googleapis.com': {
    viewers: ['roles/pubsub.viewer'],
    operators: ['roles/pubsub.editor'],
    admins: ['roles/pubsub.admin'],
  },
  ...
},
```

To compute the final list of Google IAM bindings we need to produce for
make-it-rain:

```json
[
  {
    "member": "banking-integrations-team@gocardless.com",
    "project": "gc-prd-make-it-stag-833e",
    "role": "roles/pubsub.admin"
  },
  {
    "member": "core-banking-team@gocardless.com",
    "project": "gc-prd-make-it-stag-833e",
    "role": "roles/pubsub.editor"
  }
]
```

We implement the registry queries that aggregate these permissions in a separate
Jsonnet file, `registry-permissions.jsonnet`, inside of the registry terraform
project. Terraform is far less suited to manipulating data than Jsonnet, so we
aim to produce whatever structure is easiest for the terraform to understand,
leading to extremely simple terraform code:

```terraform
provider "jsonnet" {}

# [{member, project, role}]
data "jsonnet_file" "registry_permissions" {
  source = "registry-permissions.jsonnet"
}

# An IAM member per permission binding, sourced from our Jsonnet
resource "google_project_iam_member" "permissions" {
  for_each = {
    for permission in data.registry_permissions : join(".", [
      permission.project, permission.member, permission.role
    ]) => permission
  }

  project = each.value.project
  member  = "group:${each.value.member}"
  role    = each.value.role
}
```

And just like that, we express our GCP permissions using the same data-source
that powers our Kubernetes RBAC, traced back to the service definition in our
cannonical registry.

While this permission model may not fit your team, it should be clear you can
encode whatever model you want into your registry. Once you establish a sound
data model, you'll be surprised by how easily you can use this to power your
various tools.

If you do it right, it should help a small group of SREs manage an ever
increasing number of services, using the automation to ensure consistency.
That's what we hope, at any rate!

# Tooling

So far we've covered provisioning of infrastructure, possibly the most useful
way to leverage a service registry. But once you use it to create
infrastructure, the registry becomes a trusted map of everything that exists,
which can be an awesome help when creating user friendly developer tools.

## Discovery

Before anyone can use the registry, they need to access it. If we're aiming to
make the registry truly ubiquitous, we need to provide tools that can fetch a
registry from anywhere, without requiring additional setup or authentication
material.

For this, taking inspiration from Google Application Default Credentials, we
implemented a discovery flow that should work from anywhere. We do this by
deploying the registry in several places:

- For developers, we upload a registry JSON blob to a GCS bucket. Every
  GoCardless developer is authenticated against Google Cloud Platform from their
  local machine, which we can use to grant them access
- For infrastructure, we place the registry in a globally accessible ConfigMap
  in all of our Kubernetes clusters, and permit access from cluster service
  accounts

This flow is implemented in a Go `pkg/registry`, that can be vendored into any
Golang app. Using it is as simple as calling:

```go
package registry

// Discover loads the service registry, falling back to a number of locations.
func Discover(context.Context, kitlog.Logger, DiscoverOptions) (*Registry, error) {
  ...
}
```

For those who don't use Go or are writing simple scripts, we rely on a binary
called `utopia`, a tool we vendor into developer and production runtimes along
with several other GoCardless specific tools. The binary supports a `utopia
registry` command, which calls the standard discovery flow and prints the JSON
registry.

```console
$ utopia registry | jq keys
[
  "clusters",
  "logIndices",
  "projects",
  "services",
  "teams"
]
```

So now it's accessible everywhere, what can we do with it?

## Improving UX

Like many teams, our maturing Kubernetes expertise encouraged us to break our
large cluster into many smaller clusters. Where most services used to exist in a
single cluster, they were now spread across many, and might move depending on
maintenance or business requirements.

Where our developer tools used to default to a specific cluster, the number of
teams who could happily rely on the default value was falling day-by-day. In
addition to cluster, developers needed to understand what namespace their
service existed in, and often a `release` label.

Together, these parameters were beginning to complicate our developer tools:

```console
$ anu consoles create \
  --context <cluster-name> \
  --namespace <namespace> \
  --release <release> \
  ...
```

Application engineers shouldn't need to know our cluster topology from heart-
that's quite an ask for someone who infrequently has to make changes to these
configurations. I suspect new joiners were encouraged to type magic values,
instead of understanding what they were writing, and any maintenance that
changed them could potentially break many a runbook.

Developers think in terms of service and environment, not physical location. Our
registry can help us here- if it's easy to map service and environment to the
cluster and namespace in which it's deployed, then we can start offering
interfaces that align with how developer think:

```console
# --service can be provided, or automatically inferred from the current repo
$ utopia consoles create --environment staging -- bash
```

And it's not just finding services. The average infrastructure has a load of
tools that are interconnected in ways that aren't easy to mentally model, but
are easy to write into a registry like ours.

As an example, we run Kibana to provide centralised logging. Service logs are
routed into various index patterns, which means you need to hit the right index
pattern for any search to be successful.

By adding a `loggingIndex` type to our registry, we can easily map a service
environment to a Kibana index, allowing us to implement a shortcut for jumping
into a services logs:

```console
# Open the browser with Kibana at the right index, with filters
# for this service environment
$ utopia logs --service=make-it-rain --environment=staging --since=1h
```

These improvements may seem small, but can reduce cognitive load in situations
where it really pays, such as during incident response. The efforts to make
developers lives easier are, I think, appreciated.

## Monitoring and alerting

- The data structure is well understood, which means you can translate it into
  other formats
- Template Prometheus recording rules that create a `gocardless_service` time
  series with team and alert channel labels, by mapping over services in the
  registry
- Now we can automatically join common alerts (Kubernetes pod crash-looping)
  onto team specific channels, allowing automatic routing of alerts

# Closing

At GoCardless, we're about to release a total reimagining of our infrastructure
tooling, and the service registry has been an essential piece of that puzzle.

Once you have a registry, you start thinking about solutions to problems you
didn't even realise existed. When you start orienting teams around that data
model, you can encourage consistency and benefit from a shared mental model of
your infrastructure.

This post describes some of the benefits we've seen, and solutions to problems I
think most engineering orgs of our size experience. I encourage people to give
this a go- you might just like it, too.
