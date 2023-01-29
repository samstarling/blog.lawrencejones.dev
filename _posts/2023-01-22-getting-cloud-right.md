---
layout: post
title:  "Getting Cloud right, from the start"
date:   "2023-01-30 12:00:00 +0000"
image:  /assets/images/todo.png
hackernews: TODO
tags:
  - engineering
excerpt: |
  <p>
    From my time at GoCardless, I watched as we continually rebuilt our
    infrastructure to adapt to our growth, eventually arriving at a mature setup
    we were proud of. Not all of the patterns we followed make sense at an
    early-stage company, but some are worthwhile making even from the very
    start.
  </p>
  <p>
    In this talk, I’ll share advice on which best-practices or investments are
    worth making up-front, especially for fast-growing start-ups. I’ll use
    incident.io as an example, where I spent my first week investing in
    infrastructure foundations like infra-as-code and separate developer
    environments which have since seen 15+ engineers onboard themselves onto.
  </p>
  <p>
    I’ll conclude by showing how those foundations make it easy to add more
    security or reliability later, when you have more resource or need for it.
    And emphasise the importance of making these decisions with as much
    information as possible, making appropriate trade-offs for your company at
    that moment.
  </p>
---

Hey all! I'm Lawrence, and I work at incident.io as a Product Engineer, making
me one of your hosts for tonight.

By this point you'll have heard about how people are using Cloud in
medium-to-megacorp companies, and Greg will have given a picture of what
migrating to the Cloud when you already have existing infrastructure looks like.

My talk is going to focus on something different, which is how to get yourself
setup effectively when just starting a company, before you have any legacy to
consider.

Arriving at incident as the first hire, that was the situation I found myself
in. While the app when I arrived was simple and worked well, I was keen to lay
foundations in anticipation of onboarding the 15 engineers we've now hired. The
process of deciding where and what to invest in is what I'd like to walk
through, explaining why some of those investments felt non-negotiable.

My experience and examples will use GCP, but most of these principles
can be applied to other providers.

## What is 'right'?

This talk is called getting cloud 'right', so it's only fair we begin by
explaining what that means, and agree on the principles we'll use to help us
decide how to engineer things.

**1. Simple**

As an early stage company, simplicity is key. Not only are simple systems easier
to build, they're easier to maintain and your future hires will thank you for it
when onboarding.

We want to use cloud technologies because it'll help our business achieve its
goals, not because we like shiny technology.

**2. Consistent**

When possible, we want fewer tools that we can use consistently across our
infrastructure.

You can argue this is part of simple, but they can be in tension: we might
prefer a more complex abstraction if it enables us to be more consistent.

**3. Secure by default**

Whatever we build, we want the constructs to be secure. In cloud environments,
that often means we've found an architecture that works well with the platform
we're using (in our case, GCP).

Thankfully, if we build simple infrastructure with consistent patterns and
tools, it becomes easy to add security best practices into the common patterns.
Often the hardest part about adopting cloud practices when you already have
existing systems, this is where you can benefit from starting from scratch.

## Where to begin!

I arrived at incident having left GoCardless, where I'd spent years with my team
building infrastructure in GCP. As a team, we'd made a lot of decisions we later
regret, reworking our tools and approaches as learned more.

These burned fingers meant I knew what I'd like to invest in early, even if not
exactly how:

1. Model an 'application', and make it easy to create 'environments'.
2. Infrastructure as code for anything production.
3. Each developer gets their own environment for local dev.

It's hard to explain everything that goes into why these are my table stakes, as
there's a huge number of gotchas behind each of them. But if I had to find a
common theme, it's that each of these things become extremely hard to achieve
the longer you go without them.

It's inevitable that a growing company will need to build more applications than
they start with. If you don't have a concept of 'applications' and
'environments' already socialised, the next application will break convention:
this brings inconsistency, which comes with security implications, and reduces
your leverage by creating two separate paths to deploying applications.

Young start-ups rush to do everything, and the chance you'll go back to hand
provisioned infra and move it to terraform is near zero. So if you don't have a
good IAC story from the start, it's likely you'll create tech debt with a
shelf-life that would surprise you.

Finally, if you have (1) and (2), you can easily create a local environment for
each of your developers. Doing this ties everything together by giving devs a
space to learn the infrastructure and tooling, which encourages more ownership
over the production infrastructure. Again, hard to hack on as an after-thought.

Let's see what hitting these goals looked like for incident.

### Model an 'application' and 'environments'

You can't define what an 'application' means for your company before
understanding the current architecture, so that's where we'll start.

The incident app is a Go monolith, deployed to Heroku using a container
buildpack. Its primary datastore is a Heroku Postgres, with a Heroku memcache
as a key-value cache. It runs in three roles: web for serving incoming HTTP
traffic like Slack webhooks and API requests, workers for async jobs, and a cron
to run scheduled tasks.

Google Pub/Sub powers the publishing and subscribing to async jobs, and Google
Cloud Storage is used for blob storage.

It looks like this:

![Architecture of incident app](/assets/images/getting-cloud-right-arch-partial.png)

Together, these components comprise the 'application'. But it's a bit of a messy
collection, with Go app roles alongside infrastructure in GCP and Heroku, and
it's unclear what an 'environment' might look like.

If we want to add more structure, there are some questions we might ask ourselves:

**What environments do we need?**

An environment is an instance of the app. We'll want:

- Production, the real app that customers use.
- Staging, a mirror of production that can be used to test changes.
- Development, actually many environments, one per developer that run on local
  machines.

**Will environments share resources?**

Never. Each environment should be isolated from one another, both in terms of
using separate infrastructure and no sharing of credentials.

**What would an ideal dev environment look like?**

We'd have real, per-developer instances of GCP infrastructure (Pub/Sub & GCS) so
developers can be building against the real thing. We don't want a Heroku
application for each developer, so we'd have developers run their own version of
Postgres and memcache locally.

Developers can run the Go app so it provides web/workers/cron all in one
process, pointed at their local Postgres + memcache and their own copy of GCP
infrastructure.

#### All that said...

Let's add some structure to the original diagram.

![Architecture of incident app with added structure](/assets/images/getting-cloud-right-arch-full.png)

Now we understand the app, we can map the structure to real-world infrastructure
concepts:

- An application environment will have its own Google Project, in which we'll
  provision all GCP infra.
- Each environment gets a separate GCP service account which it uses to access
  GCP services.
- We'll create a staging and production Heroku app, deploying to staging and
  then production in sequence, and each app will have a separate Heroku Postgres
  and memcache.
- Each developer will receive their own environment for working locally, with
  their own Google resources. Non-Google infrastructure can be run locally, via
  docker-compose.

### Infrastructure as code

Having decided what an environment will look like, we need to find a way to
model it in infrastructure-as-code.

This breaks into several problems:

1. Running terraform.
2. Creating an application environment.
3. Provisioning environment resources.

These concerns are interlinked, and have subtle implications. I think the most
effective way of contextualising them is to describe the solution we adopted and
how it solves for each, then we can discuss the qualities of the solution.

#### 0. Creating a repo

We can't do anything without a place to put our code, so that's step 'zero'.

From experience, managing infrastructure code in a single monorepo separate from
your app code is ideal. So we began with an empty repo called `infrastructure`,
with a README that planted the flag.

```bash
mkdir infrastructure && cd infrastructure
cat <<EOF > README.md
# Infrastructure

This repo holds all incident config management code. We use terraform to
declaratively manage Cloud based infrastructure, and aim to have no
configuration exist outside of config management tooling.
EOF

git init
git add README.md
git commit -m "initial commit"
git push git@github.com:incident-io/infrastructure.git
```

As a preview, we'll be working toward a repo structure of:
```
projects/spacelift-stacks
├── README.md
├── main.tf
├── modules
│   └── stack
│       ├── main.tf
│       └── variables.tf
└── variables.tf
projects/incident-io
├── README.md
├── _production.tfvars
├── _staging.tfvars
├── _dev-aaron.tfvars
├── ...
├── main.tf
└── variables.tf
```

Where there is a single directory for each terraform project, and our
business-level 'applications' have their own terraform project, with each
environment being a separate deployment of that project.

#### 1. Running terraform

Terraform needs to create, manage and destroy infrastructure, which means it's
often the only thing in your infrastructure running with 'god' permissions.

That means the security of how you run terraform is critical. Additionally,
there's a chicken-and-egg problem of how you create the thing that runs
terraform if you don't have terraform available to provision it.

We shortcut a lot of this by using Spacelift.

<div style="display: flex; justify-content: center">
  <img
    alt="Spacelift's logo"
    src="/assets/images/getting-cloud-right-spacelift.png"
    style="max-width:65%"
  />
</div>

Spacelift offers a managed terraform runner, quite like a CI/CD system but
designed entirely for terraform.

One of the cool things about Spacelift is you can manage Spacelift _with_
Spacelift, which while meta is really useful: we can write terraform that
manages Spacelift stacks, and ensure our critical 'god' tier stack is managed in
code.

Our setup is quite simple:

1. Create a 'god' permission Spacelift Stack (`spacelift-stacks`) that we'll use
   to manage other Spacelift stacks and infrastructure.
2. Grant permissions to the Google service account attached to
   `spacelift-stacks` so it can administrate Spacelift and our GCP account.
3. Import the stack into itself, and make any subsequent changes through
   Spacelift.

A Spacelift 'stack' combines a terraform project with a fresh terraform state,
and some stack-specific configuration such as which tfvars to use. We'll soon
extend it to create applications and their environments, but for now all it has
is:

```terraform
# projects/spacelift-stacks/main.tf
resource "spacelift_stack" "spacelift_stacks" {
  name         = "spacelift-stacks"
  description  = "Configuration of Spacelift stacks"
  repository   = "infrastructure"
  branch       = "master"
  project_root = "projects/spacelift-stacks"

  # This stack controls other stacks:
  administrative = true
}
```

Which is planned and applied by `spacelift-stacks` itself, inside of Spacelift.

![Spacelift dashboard showing spacelift-stacks](/assets/images/getting-cloud-right-dashboard-stack.png)

#### 2. Creating an application environment

We now have a Spacelift stack that can run terraform which creates other
Spacelift stacks and Google Cloud Platform resources. That's all we need to
build an abstraction that models a generic application environment.

For this, we built a `stack` terraform module that we can use to create an
instance of an application environment.

Using the module to create a staging and production environment for the primary
incident app looks like this:

```terraform
module "incident_io" {
  for_each = {
    "staging" = {
      project = "incident-io-staging"
    }
    "production" = {
      project = "incident-io-production"
    }
  }

  source = "./modules/stack"

  application       = "incident-io"
  instance          = each.key
  google_project_id = each.value.project
}
```

The module creates:

- Spacelift stack executing the terraform project at `projects/incident-io` with
  the correct `.tfvar` file for the instance.
- Google project under which all GCP resources for this environment will be
  provisioned.
- IAM bindings from the Google service account attached to the Spacelift stack
  to manage aforementioned GCP project.

This looks simple and obvious, but it's a key part of this setup: by creating
all application environments through the same terraform module, you ensure a
consistent security model, allowing even a small team to manage many apps by
properly reviewing the shared code instead of each variation that gets invented
without it.

#### 3. Provisioning environment resources

Having created the root `spacelift-stacks` that creates application environments
(1), then created staging/production/development environments for the
`incident-io` application (2), all that remains is provisioning the resources
for the environments (3).

![Diagram of stacks and how they interact](/assets/images/getting-cloud-right-stacks.png)

Each application has a separate terraform project, which is deployed several
times for each environment, parameterised by `.tfvar` files.

We can start by writing a `projects/incident-io/main.tf` that defines each
resource we need:

![Snippets from main.tf of the application](/assets/images/getting-cloud-right-stack-code.png)

Then finish by adding `_staging.tfvar` and `_production.tfvar` files:

```terraform
# projects/incident-io/_staging.tfvars
project            = "incident-io-staging"
environment        = "staging"
images_bucket_name = "incident-io-images-staging"
```

We can deploy each of the environment stacks to provision totally separate
environments, using the projects created for them by `spacelift-stacks`.

## Developers get their own environment

Having settled on a consistent model for an 'application' and implemented that
in infrastructure-as-code, the last goal is for each developer to get their own
environment.

Lots of companies dream of per-developer or ephemeral environments, mostly
because years of development without this in mind makes achieving it really
difficult. Having made our focused investments in structure and tooling, we get
this almost for free by adding the developer environment we want to terraform
that defines the application:

```diff
 module "incident_io" {
   for_each = {
     "staging" = {
       project = "incident-io-staging"
     }
     "production" = {
       project = "incident-io-production"
     }
+    "dev-lawrence" = {
+      project    = "incident-io-dev-lawrence"
+    }
   }
 
   source = "./modules/stack"
 
   application       = "incident-io"
   instance          = each.key
   google_project_id = each.value.project
 }
```

## That's enough to get you started

We've got to a place that is simple, achieves consistency through golden paths,
and is secure by default. And we've achieved it while providing a really great
developer experience, which makes everyone happy.

From a security perspective, we've managed to limit 'god' tier access to a
single CI pipeline that we can lockdown, restrict with approval flows and audit.
Then each of our application environments are provisioned by separate CI
pipelines, with service accounts that can only make changes in their own
project, and make a point of sharing nothing.

Because environments are so easy to create, we can provide one to each developer
so they can experiment and test without getting in each others way. And because
each environment is isolated and their interactions well understood, we can
afford to give developers more powerful IAM roles in those projects, so they can
build and test things by hand: but restrict changes to staging and production to
ensure they go through code review.

[open-source]: https://github.com/incident-io/infrastructure-example

Putting this together takes just a few days, and means when you inevitably need
that new service or Google project, you know exactly how to deploy it and can do
so quickly and securely. It's a great foundation for a team expecting to grow,
and you can fork or take inspiration from our [open-source example][open-source]
to make it even easier.

If you stop here and make no other investment in your infrastructure tooling,
you'll still be in a great place years after.
