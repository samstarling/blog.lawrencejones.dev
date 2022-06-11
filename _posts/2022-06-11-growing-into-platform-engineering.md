---
layout: post
title:  "Growing into Platform Engineering"
date:   "2022-06-11 12:00:00 +0000"
image:  /assets/images/growing-platform-engineering.jpg
hackernews: https://news.ycombinator.com/item?id=31704121
tags:
  - engineering
excerpt: |
  <p>
    This talk shares my experience leading an SRE team, scaling from three people
    running all of the company’s infrastructure to a product-centric Platform
    Engineering team building tools for 200 other engineers.
  </p>
  <p>
      I’ll explain the challenges we faced at each stage – problems that are
      common across engineering orgs – and the pragmatic steps we took to solve
      them, helping us get value before going all-in on an Internal Developer
      Platform.
  </p>

---

> This post is a written form of my talk at PlatformCon, with the addition of
> the service catalog story.
>
> Here's a link if watching the talk is more your thing:
> [https://platformcon.com/talk/growing-into-platform-engineering](https://platformcon.com/talk/growing-into-platform-engineering)

I work at [incident.io](https://incident.io/), a start-up in London that offers
incident response tooling to help organisations respond with ease, at scale.

Our company is growing fast and the next year will see us scale our engineering
team well beyond the current, ten-person headcount.

A question I’ve been working hard to answer is: how do we handle infrastructure
in this context?

Specifically:

- Do we hire a Platform team? If so, when?
- Assuming we do, what is their remit? Infrastructure or more?
- What can we do technically, and culturally, to ensure that team is successful?

We could jump in the deep end, and hire a large team that jumps straight to a
full Internal Developer Platform, but that seems premature for our stage.

In fact, there are many pragmatic steps between start-up and well-funded
Platform organisation that can help ease the journey, without up-front cost.
Having travelled this path before, I’m going to share three anecdotes that
describe such solutions, in an attempt to help those taking a similar path.

They’ll be taken from my time at GoCardless, a fintech scale-up, where we grew
into Platform Engineering alongside a maturing engineering org.

## 1. Platform software is just software, you’re not special.

- Q1, 2018
- Platform: 4 engineers
- Engineering: 35+

It’s 2018 and we’re midway through a migration from IBM Softlayer to GCP, a
process that involves gradually porting our Chef’d VMs into Helm charts and
deploying them into our shiny new GKE cluster.

While we moved each service, we needed to preserve the existing deployment
workflow, which at the time involved developers issuing a Capistrano command in
their apps repo to trigger the deployment.

We’d written a hacky script which could do the GKE deployment from Cap, but had
no SDLC around it, including any way of distributing the code to developer
laptops so Cap could invoke it.

***This is just another software problem***

Infrastructure engineers like to think they’re exceptional, that their code is
somehow too complex for standard software engineering practices to apply.

In my experience, it’s often the reverse: complex and critical, their code can
benefit greatly from applying best practices. It’s just harder than
cookie-cutter API CRUD code, and easy to ignore once you get your stuff working.

Here’s the thing, though: if you’re in a burgeoning Platform Engineering team,
this is the moment you can lay foundations to make that burden far lighter.

**Make a home**

Firstly, we created a home for the deployment script that was intended to grow
far beyond that initial use case. As we already had a monorepo containing our
config-as-code, we reused that (anu) and created a new Go project.

In that project we created a CLI tool, anu, which had a single command:

`$ anu deploy`

As we knew this would be the first of many commands, we could justify
establishing some testing patterns, and configuring CI to lint and test the
project on each change.

This meant anyone adding a command wouldn’t need to decide “where do I put this
code?” or “cba with configuring CI just for this…”. They just add their code,
and benefit from the existing codebase.

**Continuous deployment (yes, for *our* stuff)**

The faster you can ship, the more you will. Improving that feedback loop is an
addictive cycle, and you want that for a Platform Engineering team where new
features directly benefit your engineering org.

We setup our repo to cut a new release whenever we merged to master, just as we
would a normal software project. CI would build a binary, push it to GCS, then
update a homebrew tap so developers could pull the new version.

We even semantically versioned the app, so we could refuse to run commands if
the binary knew it was incompatible with other services.

**Deploy it everywhere**

[goreleaser]: https://goreleaser.com/

This one is a bit different than normal software: instead of shipping to one
place, we packaged anu into the homebrew tap, a GCS bucket, and our Debian
package registry (using a great tool called [goreleaser][goreleaser], do check
it out!).

Through either of these means, we ensured whatever environment you were in,
you’d have access to the tool. Be it a container, Chef VM or local dev, you’d
have the latest CLI ready to use.

Building a CLI is way faster than a web UI, especially when you consider that
most Platform Engineering teams may lack frontend expertise. This was an
extremely low effort investment that created a flywheel for developing
infrastructure tools, and helped maintain a shipping rhythm that a customer
facing product team would be jealous of.

## 2. If you can’t explain it, you don’t understand it.

- Q2, 2020
- Platform: 6 engineers
- Engineering: 140

Our platform team is bigger now with 6 engineers, but the broader engineering
org has grown to a chunky 140. You’ll be happy to hear the GCP migration is
complete – yes, we shutdown the last Softlayer machines and burned the invoice –
but life isn’t perfect.

In fact, life in Cloud isn’t as fluffy as we’d been lead to believe. Everyone
had been so excited about GCP tooling that they’d created a load of it, and
perhaps worse, they’d built on the shaky foundations we’d established while
finding our feet during the lengthly migration.

We had a load of services, each with four environments (don’t ask) across a
number of GCP projects, and living in a single, creaking GKE cluster.

It was a bit of a mess, and we didn’t know how to start cleaning it up.

***Start small, describe what you see, then change it.***

We had too much stuff to fit in anyone’s head, so we began to build what we
termed a ‘service registry’ to track it all.

Our aim was to develop an inventory of all entities in our infrastructure, and
felt the perfect catalog would be:

- Universally consumable, so any tool could load it
- Widely distributed, so any environment may access it
- Comprehensive, including all the units that comprised our infrastructure
- Trustworthy, with all entries known to be correct

To these ends, we started building a registry in Jsonnet, a language that is a
superset of and compiles to JSON. The registry began by listing Kubernetes
clusters, with metadata like which GCP project they existed in, then grew to
include services, teams and GCP projects.

The registry lived in our existing monorepo (anu), and was compiled into a JSON
blob and shipped to GCS on master. We extended the anu CLI to pull the registry
from a number of locations, completing the vision of every execution environment
having both the anu tool and a complete registry.

**But why?**

It might sound basic, but this was a big moment for us. Now we had a way to
describe the infrastructure, we could begin feeding that description to the code
that provisions it, having the terraform consume the registry and use that to
decide what to create.

This answered the question about trust: if the registry is used to provision
infrastructure, you no longer need to worry about it drifting from reality.

And once you could rely on the registry being truthworthy, you could start using
it to glue our platform together. We started by ensuring you could only deploy
services that were present in the registry, but eventually adding the service to
the registry would provision it: Kubernetes namespace, GCP project, permissions
and associated infrastructure.

That linking is at the heart of any internal developer platform, and if you
can’t model what you have, you won’t be able to leverage a lot of the tools
growing in popularity today. Building an accurate service registry/catalog is
the hard part of investing in an IDP, but is easier the earlier you start, and
you can get a huge amount of value from a bargain basement JSON setup.

[service-registry]: https://blog.lawrencejones.dev/service-registry/

I wrote a [detailed article][service-registry] about this service registry back
when we'd first built it, which I'd advise reading if you want more info.

## 3. You can’t sell a product no one wants.

- Q2, 2021
- Platform: 7 engineers
- Engineering: 200+

When I first joined Platform, the hiring manager sold me on the dream that new
joiner engineers could self-service their own playground production service,
without any need of SRE help or formal approval.

Three and a half years later (thanks Norberto) we’d finally made that true,
shipping a new joiner tutorial that achieved just that.

Not only was it possible to self-service, it was much faster, much more
ergonomic than our previous process…

***And people weren’t really using it.***

Ok, no, that’s not fair. People were using it, in fact there were some teams who
were rapidly becoming power users and revelling in their new-found freedom.

But adoption across teams was inconsistent, despite all teams having suggested
SRE dependencies being a major productivity pain-point. Reaching out to those
teams and asking some hard questions, we began to realise we weren’t as aligned
as we'd thought.

As it turned out, there were teams who didn’t want to do this stuff themselves.
When they’d said the SRE team was being slow to respond to their infra requests,
their ideal outcome was that we’d work faster – certainly not to give them the
tools, however good, to do it themselves!

This is a failure mode I’ve now seen several times, and I believe is
particularly common to Platform Engineering.

Two reasons for this: firstly, good Platform Engineers tend to hate
technological limitations, are tenacious, love to learn new technologies, and
hate being held up on others. Working in a team full of these people, it’s easy
to forget those qualities aren’t consistent across all of engineering, and that
this might be a demographic crucial to the success of our work.

Compounding this, and ironically, attempts to stay close to the customer can
backfire. When picking teams as design partners, you look for those who are
enthusiastic about your work: you should expect those teams to be much more
invested in your platform tooling than the average, and this bias toward more
passionate customers can lead to overfitting.

**What can we learn from this?**

Stepping back from the detail a bit, this is not a problem specific to Platform
Engineering. I’d argue it’s a general,
product-team-losing-sight-of-their-customer problem.

The reason it appears so frequently in our discipline is because Platform
Engineering teams are often born from divisions historically seen as ‘furthest’
from the Product. This creates teams who see their work as an evolution on that
service-desk approach, rather than the intense, complex and confounding Product
challenge it actually is.

The truth is that for a Platform team to be successful, they need to be taking a
customer-centric approach to their work. When speaking with Product Managers
about this, I advise they see Platform engineering as B2B in close quarters: you
have fewer customers, but (almost) unfettered access to them, and can leverage
your existing relationships to gather feedback a typical product owner could
only wish to get.

And as a bonus, most of your customers are highly technical, and product minded,
too.

We ended up tackling this problem on several fronts, from reaffirming our
expectations across the organisation, to addressing our expectations of
build-it-run-it during the hiring process.

But if you are a Platform team building for your org, it’s easiest to
communicate early, openly, and often with your customers. And make sure they
want what is it you’re delivering, before you build it.

## Round up

Those experiences are three I think are generally useful for anyone in Platform
engineering, and can be summarised as:

- Embrace software engineering practices when doing infrastructure work: you
  probably need it more than they do!
- Building a model of your infrastructure is cheap, easier the earlier you
  start, and can glue it together
- Platform engineering is internal product engineering, and it’s not easy

The next couple of years is going to incident.io make a similar journey, and I’m
excited to see how that plays with such a different landscape than just a decade
ago.

[careers]: https://incident.io/careers/

And if that journey sounds interesting… we’re looking for that [first Platform
hire][careers] right now.
