---
layout: post
title:  "Moving on from GoCardless"
date:   "2021-08-01 12:00:00 +0000"
image:  /assets/images/moving-on-from-gocardless.jpg
tags:   []
excerpt: |
  <p>
    Starting next week, I'll be joining the <a
    href="https://incident.io/">incident.io</a> team after logging off for the
    last time at GoCardless. Mostly for myself, here's some reflections on the
    last five years.
  </p>

---

Yesterday, I left the GoCardless office for the last time.

After five and a bit years, and a six month internship before that, it feels
weird to be saying this- but it’s time for me to move on.

Trying to reflect on this experience is difficult. I started GC as an intern and
left as a Principal Engineer, which is just one aspect of an incredible journey
with many amazing stops along the way.

# What even happened?

Here’s some thoughts that make my head spin:

- GC has 20x as many staff now as they did when I first started
- Our payment volume has increased similarly- I remember a mad panic about 180k
  daily payments in 2016, but we submitted ~2.5M last Thursday without a sweat!
- I’ve had about six different job titles at GC, given I’ve switched from SDE to
  SRE and back again, been promoted three times and had tours in more than six
  teams
- In that time, I’ve made 16,000 commits and ~2k PRs to GoCardless repos, in
  more than ten programming languages

You work on a huge variety of projects in a tenure like this, and my list
contains things like managing the integration of an acquisition, rebuilding our
[Postgres clustering](https://github.com/gocardless/stolon-pgbouncer)
([twice](https://github.com/gocardless/pgsql-cluster-manager) 🤦), creating a
framework for [GC Kubernetes operators](https://github.com/gocardless/theatre)
and a [learning from lots and lots of
incidents](https://blog.lawrencejones.dev/incident-response/).

The best thing about spending a while at the same place, though, is that you get
to work on really large-scale initiatives that might take years and see them
from start to finish. That’s the type of work that has long-term impact on a
company, and is what I’m most proud of.

For me, these were:

### Migrating from IBM SoftLayer to Google Cloud Platform (Aug 2017-Sept 2018)

Starting properly in August 2017, the Platform team worked to rebuild the
entirety of GoCardless’ infrastructure from physical machines in SoftLayer to
the fully virtualised world of GCP.

The entire team had to learn Kubernetes from scratch, discover all the
idiosyncrasies of the legacy infrastructure, then plot a course into a modern
Cloud environment while continuing to support the rest of Product Development
for their infrastructure needs.

On the 16th of September 2018, we switched everything over to GCP with just 7m
of downtime. Since then, GoCardless has only increased its investment in GCP,
and almost every team works with Google technologies on a day-to-day for
critical parts of their job.

### Building Utopia, our internal PAAS toolchain (June 2020, on-going)

Moving to GCP was great, but it left a lot to be desired.

The self-serve aspect of our infrastructure was something that always bothered
me. It was clear we couldn’t expect people in engineering to pick-up and use our
new infrastructure without substantial help from us, and I didn’t even know how
we’d make that a reality.

In a constant search for something that worked, we:

- Ditched helm-charts-per-app in favour of a generic ‘gc-app’ chart
- Trying for a move git-ops approach, rewrote our core Kubernetes resources in
  kustomize
- Sick of the Kustomize straight-jacket, rewrote again in Jsonnet with Ksonnet
  mixins

This experience along with similar trial-by-fire in GCP best-practices suddenly
clicked, and in a week we built a prototype of something called Utopia, our new
infrastructure toolchain.

More than just Kubernetes templating, Utopia:

- Was designed to be entirely self-service, with zero-tolerance for an SRE-only
  audience
- Provided an integrated experience between Kubernetes resources and GCP
  infrastructure
- Aligned Kubernetes topology with Google Projects and IAM roles
- Established a framework for marrying Kubernetes RBAC with GCP IAM, and a
  philosophy for understanding permissions and when/who to grant them to

In personal terms, Utopia fulfilled a dream I’d had since I first joined the
Platform team- that a new joiner could boot themselves a service into GoCardless
infrastructure by following a tutorial in their first week: see [Deploying
Software at GoCardless: Open-Sourcing our “Getting Started”
Tutorial](https://medium.com/gocardless-tech/deploying-software-at-gocardless-open-sourcing-our-getting-started-tutorial-ab857aa91c9e).

I think we arrived here just in time- our growth plans mean the number of GC
services is at the start of hockey-stick growth, and Utopia is going to make
that possible.

### GoCardless and Open Banking (Dec 2020-July 2021)

Forming the last arch of my GoCardless journey, I moved out of infrastructure
and took on the tech lead of our Open Banking initiatives for the last nine
months.

Open Banking had two clear goals, which (as of July 2021!) are products that
real people are using:

- [Instant Bank Pay](https://gocardless.com/solutions/instant-bank-pay/),
  collect payments instantly from your UK customers using the Faster Payments
  network
- [Verified Mandates](https://gocardless.com/en-us/g/verified-mandates/),
  protect against fraud by ensuring your payer owns the bank account before
  setting up a Direct Debit mandate

Getting here was hard, though.

Instant Bank Pay meant integrating an entirely new payment method into our
product, where it soon became obvious our old APIs were not fit-for-purpose. In
fact, any Open Banking product will require a high-touch payer interaction that
none of our existing product had expected.

So while Instant Bank Pay and Verified Mandates are awesome, what I’m truly
proud of is the behind-the-scenes work that has made them possible.

This includes:

- An entirely new API concept of a [Billing
  Request](https://developer.gocardless.com/getting-started/billing-requests/overview/),
  designed to abstract scheme requirements including support for Open
  Banking-esque payer flows
- Introduced our new [Billing Request
  Flow](https://developer.gocardless.com/getting-started/billing-requests/anatomy-of-a-billing-request-flow/)
  checkout experience
- Created [Billing Request
  Templates](https://developer.gocardless.com/api-reference/#billing-requests-billing-request-templates)
  to power reuse-able authorisation links, paving the way for no-code
  abstractions like [Stripe Payment
  Links](https://stripe.com/en-gb/payments/payment-links)
- Released a [Javascript
  Drop-in](https://developer.gocardless.com/getting-started/billing-requests/using-dropin/)
  library that makes integrating the checkout flow a breeze

Together, these changes are a massive step-change for GoCardless, and was only
achievable by leveraging experience across the entire company. Whatever we built
had to intuitively support our existing product use cases, while catering for a
load of future ambitions we know we’ll want to explore.

In many ways, designing evolving into Billing Requests was similar to how Stripe
describe their [payment API
evolution](https://stripe.com/blog/payment-api-design), and was no mean feat.

Releasing such impactful products at pace is a testament to the GoCardless
culture I love, and the amazing people that work there. While the Payer
Experience and Payment Rails 2 teams were the workhorses for a lot of this,
there was a huge number of people who pulled together to get this done.

We didn’t cut corners, but we took the right, pragmatic shortcuts. And the work
left everyone feeling even more excited about GoCardless’ future than they were
before.

# What’s next?

I’m leaving GoCardless feeling extraordinarily grateful. The people I’ve worked
with and the experiences we shared have really changed my life, and I can’t
imagine where I’d be without it.

But if it sucks to leave a company you love so much, the one upside is you only
do it for an opportunity you can’t resist.

So with that in mind… I’m excited to say that starting Monday, I’ll be joining
Pete, Stephen, Chis and Lisa at [incident.io](https://incident.io/), where we’ll
be pooling our considerable fire-fighting expertise into what we hope will be
the world’s best tool for incident response.

I couldn’t be more excited for the challenge, and look forward to the really
early stages I missed at GC!
