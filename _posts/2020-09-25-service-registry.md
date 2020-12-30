---
layout: post
title:  "Why you need a service registry"
date:   "2020-09-28 12:00:00 +0000"
tags:
  - infrastructure
  - terraform
  - chef
  - kubernetes
  - google-cloud-platform
hackernews: https://news.ycombinator.com/item?id=24616442
excerpt: |
  <p>
    As a team's infrastructure estate grows, it becomes increasingly beneficial
    to create a global registry of all people, services, and components. Once
    you do, you can integrate with tools like terraform, Chef, and Kubernetes to
    help provision your infrastructure according to a single authoritative
    source.
  </p>
  <p>
    This post explains how GoCardless built their registry, and some of the uses
    we’ve put it to.
  </p>

---

Building a service registry, a structure that tracks all people, services and
systems that interact with your infrastructure, can be extremely powerful.

If you pick the right format, it can be the glue between totally distinct
toolchains. Placing the registry at the heart of all your other tools means you
no longer need to worry about keeping it up-to-date: the registry defines what
is created, rather than describing it.

By distributing the registry so every developer, infrastructure component or
one-off script can easily read it, you'll find use cases for this data
everywhere. You can even push this data into systems like your monitoring stack,
allowing automated systems to make decisions on the ownership information it
provides.

As part of a revamp of our infrastructure tooling, we've introduced a service
registry into GoCardless. This post explains how we built the registry and some
of the use cases we've found for it.

# What is it?

[jsonnet]: https://jsonnet.org/

The GoCardless service registry is a [Jsonnet][jsonnet] library, stored as a
file inside the same Git repository that contains our infrastructure
configuration. Jsonnet, for those not familiar, is an extension to JSON that
aims to support flexible reuse and customisation of data structures.

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
are many systems that do just that, but I'd suggest the approach of building a
registry out of a single JSON file (compiled from whatever templating language
you choose, be it Jsonnet or otherwise) has several advantages:

- JSON files are so universally compatible that you'll be able to use this
  anywhere
- If you've already adopted Git-ops workflows, tracking changes to the registry
  in Git should feel very natural
- It's just data, and your registry is only as good as the data you put in it.
  Removing the distraction of building an API means you encourage a focus on
  building the right data model, which is what really matters

From the output of the `jsonnet registry.jsonnet` command, you can see we're
tracking our Kubernetes `clusters`, any `services` that we run, organisation
`teams` who interact with the services, and Google Cloud Platform `projects`.

You don't need to start by tracking all these types, but the simplicity of a
Jsonnet library means it costs very little to add a new type. We began with
`services`, then wanted to ensure no service referenced an invalid team. It was
a natural evolution to add `teams`, and this pattern has happened many times
over.

## Service entry (make-it-rain)

[gist/make-it-rain.json]: https://gist.github.com/lawrencejones/b209a1a5da864b987cbedb1dffef6116#file-make-it-rain-json
[gist/make-it-rain.jsonnet]: https://gist.github.com/lawrencejones/b209a1a5da864b987cbedb1dffef6116#file-make-it-rain-jsonnet

Our registry began as a list of services, where each service had a
`metadata.jsonnet` that defined its service entry.

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
service.mixin.withAlertsChannel('make-it-rain-alerts') +
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
        argocd.new(cluster='compute-staging-brava', namespace='make-it-rain'),
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
        argocd.new(cluster='compute-banking', namespace='make-it-rain'),
      ]),
    ],
  ),
])
```

Take a moment to read the Jsonnet- this produces a JSON structure that you can
see [here][gist/make-it-rain.json]. It includes a definition of the service and
all its environments, with a list of deployment targets for each environment
that defines where the deployment lives.

There's some configuration of team permissions and Google Cloud Platform
references- we'll see how we can use them next.

# Provisioning infrastructure

[terraform]: https://www.terraform.io/
[chef]: https://www.chef.io/products/chef-infra
[kubernetes]: https://kubernetes.io/

Once you have a list of service entries like make-it-rain, we can use it
to tightly integrate with all the rest of our infrastructure tools.

Most infrastructure teams deal with many (in my mind, too many) tools.  The
GoCardless team provisions infrastructure with [terraform][terraform], manages
virtual machines with [Chef][chef], and [Kubernetes][kubernetes] resources with
Jsonnet templating. Other teams may use far more.

Thankfully, our service registry is plain ol' JSON, and easily consumed by all
of these tools. Once imported, we can begin provisioning infrastructure in
response to changes in the registry. This is a change from the registry
describing the infrastructure at a point-in-time, to becoming the definition
what really exists.

When you must update registry to create infrastructure, you guarantee the
registry is up-to-date, and know it can no longer become stale. This allows you
to trust the registry in use-cases that weren't possible if it could fall
out-of-date, a benefit we'll see when we integrate it with our
[tools](#tooling).

Let's see how this works in practice.

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
establish a consistent permission model up-front. Consistency means you can
accurately describe your security stance for audits, and helps maintain
productivity for engineers who work across multiple teams.

Your registry, being the authoritative definition of service RBAC, can be used
to power your Kubernetes RBAC and enforce that consistency. Looking at our
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
admin- from our experience, it seems this is flexible enough for almost all use
cases. We thought it would be great if all permissions granted to humans were
derived from these member lists, instead of scattering the membership across our
infrastructure configuration (Kubernetes, terraform, Chef).

Now we have our registry, we can do just that. Using Kubernetes permissions as
an example, it's simple to:

- Identify the list of teams who are viewers, operators, or admins for any
  services that exist within each cluster namespace
- Use these lists to create `RoleBinding`s in the service namespace, granting
  appropriate permissions to each member of the roles

We implement this in a single file, `cluster/app/spaces-rbac.jsonnet`, which
allows us to map over all namespaces in a cluster and provision the
`RoleBinding` Kubernetes resources. Jsonnet is great for this type of data
manipulation, proving–yet again!–how using a static registry does not limit how
flexibly you can query the data.

## Google Cloud Platform

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

[config-connector]: https://cloud.google.com/config-connector/docs/overview

This field means our staging environment is *linked* against the Google project
with project ID `gc-prd-make-it-stag-833e`. This means GCP resources, including
the IAM memberships, must be provisioned in this Google project.

We also detect a linked Google project, and deploy an instance of the [Config
Connector][config-connector] for the `make-it-rain` namespace. This allows
developers to provision Google Cloud Resources (like a CloudSQL instance, of
BigQuery dataset) like any other Kubernetes resource, all automatically deployed
through a registry change.

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

[google-pubsub]: https://cloud.google.com/pubsub/docs/overview

This tells us that make-it-rain makes use of [Google Pub/Sub][google-pubsub].
Using this, we can write some Jsonnet that maps Google services to appropriate
IAM permissions for each role:

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

With this, we can implement the registry queries that aggregate these
permissions into a separate Jsonnet file, `registry-permissions.jsonnet`, inside
of the registry terraform project. Terraform is far less suited to manipulating
data than Jsonnet, so we aim to produce whatever structure is easiest for the
terraform to understand, leading to extremely simple terraform code.

We end up with a simple list of Google groups to Google Cloud Platform IAM
roles:

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

Finally, we import these permissions into our terraform, with almost no
additional data processing required:

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

And just like that, we express our GCP permissions using the same data source
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
which can be a great help when creating user friendly developer tools.

## Discovery

Before anyone can use the registry, they need to access it. If we're aiming to
make the registry truly ubiquitous, we need to provide tools that can fetch a
registry from anywhere, without requiring additional setup or authentication
material.

[google-adc]: https://cloud.google.com/docs/authentication/production#automatically

For this, taking inspiration from [Google Application Default
Credentials][google-adc], we implemented a discovery flow that should work from
anywhere. We enable this by deploying the registry to several locations:

- For developers, we upload a registry JSON blob to a GCS bucket. Every
  GoCardless developer is authenticated against Google Cloud Platform from their
  local machine, which we can use to grant them access. We'll rely on registry
  access for several essential tools: we might have chosen to pull the file from
  our Github repo, but suspect GCS might be a bit more reliable 🙈
- For infrastructure, we place the registry in a globally accessible `ConfigMap`
  in all of our Kubernetes clusters, and permit access from cluster service
  accounts

We want users to consume the registry from either of these locations
transparently. For this, we implement the discovery flow in a Golang
`pkg/registry` that can be vendored into any Golang application.

The interface is as simple as:

```go
package registry

// Discover loads the service registry, falling back to a number of locations.
func Discover(context.Context, kitlog.Logger, DiscoverOptions) (*Registry, error) {
  ...
}
```

For those who don't use Go or are writing shell scripts, we rely on a binary
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
large cluster into many smaller clusters. Where most services used to live in a
single cluster, they are now spread across many, and might move depending on
maintenance or business requirements.

Our developer tools used to default to the primary cluster, but this assumption
was becoming less and less useful as we moved around our workloads. It wasn't
just what cluster you wanted either: developers needed to understand what
Kubernetes namespace their service existed in, and often the value of their
service `release` label.

This was beginning to complicate our developer tools:

```console
$ anu consoles create \
    --context <cluster-name> \
    --namespace <namespace> \
    --release <release> \
    ...
```

Application engineers shouldn't need to know our cluster topology from heart-
that's quite an ask for someone who infrequently touches that configuration.  I
suspect new joiners were encouraged to type magic values they didn't really
understand, a habit you want to discourage when talking about production
applications. And whenever maintenance moved a service, it could potentially
break several runbooks.

Developers at GoCardless think in terms of service and environment, not physical
location. Our registry can help us here- if it's easy to map service and
environment to the cluster and namespace in which it's deployed, then we can
start offering interfaces that better align with how developers think:

```console
# --service can be provided, or automatically inferred from the current repo
$ utopia consoles create --environment staging -- bash
```

And it's not just finding services. Companies our size tend to have many tools
that are interconnected in ways that aren't obvious, and definitely not
supported natively by the tools themselves. But with a registry like ours, it's
easy to encode those connections and provide a much more joined-up experience.

[kibana]: https://www.elastic.co/kibana
[elasticsearch]: https://www.elastic.co/elasticsearch/

As an example, we run [Kibana][kibana] and [Elasticsearch][elasticsearch] to
provide centralised logging. Service logs are routed to specific indices, and
you need to know what index stores your logs to find them via Kibana.

By adding a `loggingIndex` type to our registry, we can easily map a service
environment to a Kibana index pattern. This provides all the information we need
to implement a shortcut for jumping into a service's logs:

```console
# Open the browser with Kibana at the right index, with filters
# for this service environment
$ utopia logs --service=make-it-rain --environment=staging --since=1h
```

These improvements may seem small, but can reduce cognitive load in situations
where it really pays, such as during incident response. The efforts to make
developers lives easier are, I think, appreciated.

## Monitoring and alerting

As the final case study, it's worth demonstrating how easily a static registry
can be translated into a totally different medium.

[prometheus]: https://prometheus.io/

GoCardless has a lot of services, and a growing number of teams. As teams take
more operational responsibility over their services, we're seeing a noticeable
increase in the number of developers writing [Prometheus][prometheus] alerting
rules for their service.

With increased usage came a pressing issue of alert routing. From the start,
we've supported routing alerts to a specific Slack channel by providing a
`channel` label in the alert rule.

For our make-it-rain service, we could direct our alerts to the
`#make-it-rain-alerts` Slack channel like so:

```yaml
# Example Prometheus recording rule for a make-it-rain service
---
groups:
  name: make-it-rain
  rules:
    - alert: ItsStoppedRaining
      expr: rate(make_it_rain_coins_fallen_total[1m]) < 1
      labels:
        channel: make-it-rain-alerts
```

This isn't that great, as you may forget to change the alert rules if your
channel changes. You also need to repeat the channel label across all your
rules, or have your alert wind up in the catch-all `#specialops` alert
graveyard- alerts that are silently dropped are never good news.

So while this was sub-par but we could manage, there were some things we
couldn't support with this system. One specific case were common alerts intended
to cover more than a single service.

As an example, any applications that run in Kubernetes share a number of failure
cases, from `PodCrashLooping` to `PodPending` and even `PodOOMKilled`. We have
common definitions for these alerts in every cluster, but couldn't add a
`channel` label to the common definition as that would direct all these alerts
to a single channel, when many teams run services in the same cluster.

Our solution was to create a new Prometheus recording rule,
`gocardless_service`, for every service deployment target in our registry. This
looks something like this:

```yaml
# service-rules.yaml
---
groups:
  name: gocardless_service
  rules:
    - record: gocardless_service
      expr: "1"
      labels:
        service: make-it-rain
        team: banking-integrations
        channel: make-it-rain-alerts
        environment: staging
        namespace: make-it-rain
        release: make-it-rain
        cluster: compute-staging-brava
        ...
```

This effectively uploads our registry into Prometheus, which means we can use
the rules to dynamically join our alerts onto team routing decisions. Our common
Prometheus alerts now look like this:

```jsonnet
// (kube_pod_status_phase{phase="Pending"} == 1)
// * on(namespace, release) group_left(team, channel) (
//   gocardless_service{location="local"}
// )
{
  alert: 'KubernetesPodPending',
  expr: withServiceLabels('kube_pod_status_phase{phase="Pending"} == 1'),
}
```

Where the `withServiceLabels` templates the PromQL query in the comment, which
joins the alert expression onto our registry team and channel mappings, causing
the alert to be sent directly to the `#make-it-rain-alerts` channel.

We've been happier with this than any of our other alert routing attempts, not
least because it happens automatically. If you change the alerts channel for a
service in the registry, Prometheus will immediately adjust and re-route the
alert elsewhere.

This is just one of the ways we can use this data- we can even alert on any
resources in our clusters that aren't in the registry, and more besides.

# Closing

At GoCardless, we're about to release a total reimagining of our infrastructure
tooling, and the service registry has been an essential piece of that puzzle.

Once you have a registry, you start seeing solutions to problems you didn't even
realise existed. When you start orienting teams around that data model, you can
**encourage consistency** and **benefit from a shared mental model** of your
infrastructure.

This post describes some of the benefits we've seen, and solutions to problems I
think most engineering orgs of our size experience. I encourage people to give
this a go- you might just like it, too.
