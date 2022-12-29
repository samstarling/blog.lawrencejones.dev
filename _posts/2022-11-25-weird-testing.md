---
layout: post
title:  "Weird stuff and how to test it"
date:   "2022-12-29 12:00:00 +0000"
image:  /assets/images/weird-testing.jpg
hackernews: https://news.ycombinator.com/item?id=34171348
tags:
  - engineering
excerpt: |
  <p>
    Most software is simple: you have a codebase, and existing patterns for
    testing at a unit and integration level. But sometimes you'll face problems
    that aren't just adding code to an existing project, and don't have an
    existing test suite to jump into.
  </p>
  <p>
    This posts shares some problems that required out-of-box thinking to find
    testing strategies, and gives advice on how you could use those techniques
    in your code.
  </p>
---

Most software is simple: you have a codebase, and existing patterns for testing
at a unit and integration level.

Sometimes though, you'll face problems that aren't just adding code to an
existing project. Maybe your problem involves many codebases, uses tricky
infrastructure, or perhaps you're not trying to test 'code', per-say.

I've faced my share of problems outside the usual mold, and found you can combat
the complexity if you'll willing to get creative about investing in test or dev
tooling. Most of these approaches generalise, and once you get how they work,
you start seeing opportunities to use them everywhere.

So here's some examples of problems that required out-of-box thinking to test,
and how you can tackle them.

## Snapshot tests

[snapshot-testing]: https://jestjs.io/docs/snapshot-testing

The frontend community have popularised ['snapshot testing'][snapshot-testing],
where HTML output is compared to a known-good snapshot as part of the CI
pipeline, often by textually diff'ing the HTML and sometimes by visually
comparing screenshots.

Snapshots are useful because small changes to the frontend code – say, changing
a CSS selector – can have outsized impact on the final result, and it can be
difficult to catch that during code review. It's much easier to realise your
sidebar has become a footer when CI flags a screenshot, or catch a bad condition
in your React component when large chunks of HTML disappear from the snapshot
file.

The concept is applicable outside of frontend though, and can be cheap to
implement depending on what you'd like to test.

One success story around snapshot tests comes from my time at GoCardless, when
we first started using Helm charts to deploy apps into Kubernetes. If you're
unfamiliar, Helm charts allow you to write Kubernetes config files (big YAML
documents) using Go templates, helping DRY-up your infrastructure code.

An example Helm template would be:

```yaml
{% raw %}
# Extract of helm/charts/stable/buildkite:
# https://github.com/helm/charts/blob/master/stable/buildkite/templates/deployment.yaml
{{- if .Values.agent.token }}
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: {{ template "buildkite.fullname" . }}
spec:
  replicas: {{ .Values.replicaCount }}
  template:
    metadata:
      labels:
        app: {{ template "buildkite.name" . }}
        release: {{ .Release.Name }}
        # ...
{{- end }}
{% endraw %}
```

Which when evaluated by Helm - using a given set of values that provide things
like the `replicaCount` field - will become:

```yaml
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: buildkite-production
spec:
  replicas: 3
  template:
    metadata:
      labels:
        app: buildkite
        release: production
        # ...
```

Seems simple enough, but if you've ever written Helm templates you'll know
that's a lie.

While the Go template language might be ok alone, using it to produce large,
whitespace sensitive, heavily nested YAML files is horrible. It's extremely easy
to screw up the whitespace such that the output totally changes, and the subtle
{% raw %}`{{-`{% endraw %} trailers in the Go conditional blocks can drive you
mad.

But when you can say the following statements about your code:

1. Small changes can cause large differences in output
2. You care a lot about catching regressions (god forbid we accidentally delete
   a database statefulset)
3. It's cheap to calculate a 'snapshot' of your output

Your problem might benefit from snapshot tests, to regain some sanity/control.

Applying this to our Helm charts, we started creating a `values` directory in
each chart that contains fixtures of chart values (such as the `replicaCount` in
the buildkite example) each analagous to a test case.

For a generic `app` chart that supports deploying server backends and async
workers, we might have something like:

```
charts/app                                                                                                 
├── Chart.yaml
├── README.md
├── templates                                                                                                           
│   ├── _helpers.tpl
│   ├── ...
│   └── deployment.yaml
├── values
│   ├── backend.yaml
│   ├── backend.snapshot
│   │   └── app
│   │       └── templates
│   │           ├── ...
│   │           └── deployment.yaml
│   ├── async-workers.yaml
│   └── async-workers.snapshot
│       └── app
│           └── templates
│               ├── ...
│               └── deployment.yaml
└── values.yaml
```

Each use case of the chart – in this case deploying a backend, or provisioning
async workers – is represented as a `.yaml` values fixture which compiles into a
`.snapshot` directory, using the `helm template` command. Snapshots are built
using a Makefile target which regenerates snapshots from their fixtures, taking
only a couple of seconds to refresh the entire lot.

The resulting snapshots are checked into the repo alongside the chart, which
means:

1. Whenever changes to the chart alters YAML output, the resultant Kubernetes
   manifests are included in the pull request diff, helping catch unexpected
   errors or clarify complex templating.
2. If you want to see what a chart might produce, you can look at the snapshot
   and see plain YAML instead of trying to mentally evaluate the Go template.
3. Values fixtures are great documentation for how to use the chart, as you know
   you can trust they work because they're checked via the snapshots on every
   change to the repo.

Adding a CI task that regenerates snapshots and checks the git state means you
can't forget to generate them, and is an easy way to fail the build if the
snapshots have got stale.

```yaml
# CircleCI
check-snapshots:
  steps:
    - checkout
    - run: make snapshots
    - run:
        name: Ensure snapshots were updated
        command: |
          if [ ! -z "$(git status --porcelain)" ]; then
            git status
            echo
            echo -e '\033[1;93m!!! "make snapshots" resulted in changes. Please run locally and commit the changes.\e[0m'
            echo
            git diff
            echo
            exit 1
          fi
```

When we deprecated Helm in favour of Jsonnet (which can also be used to build
YAML manifests) we continued to generate YAML snapshots. This allowed us to use
more complex Jsonnet templating – because the snapshots confirm the output – and
even power CODEOWNER rules if a dependent Jsonnet file changes the output of a
snapshot in a different location.

[utopia/snapshots]: https://github.com/gocardless/utopia-getting-started/wiki/Utopia:-Tutorials:-Getting-Started#jsonnet-snapshots

> See the Jsonnet snapshots in action at [Utopia: Getting Started: Jsonnet
> snapshots][utopia/snapshots].

Snapshot tests like this are language independent, and can be applied to all
sorts of problems. They take almost no time to setup, and can improve code
reviews by bringing the generated artifact front-and-centre of the review.

I encourage you to give them a go!

## Real infrastructure

On occassion, you'll want to test something that isn't just code. It might be a
real system like a database cluster, and you may want to use tests not on a
continual basis in CI but as part of an operational event, like a migration.

Either way, the key is realising you can use the same tools and testing
frameworks as in normal software engineering, but applied to the real world
system.

When migrating GoCardless' infrastructure from Softlayer to GCP, we needed to
lift-and-shift everything from compute to DNS. One of the thorniest parts of
this move was the 'routing tier', a collection of proxies held together by
scrappy Chef templating that provided network ingress and layer 7 rule for all
GoCardless traffic.

From memory, the path of a request would be:

```
1.    Cloudflare (DNS + HTTP proxy)
2. -> nginx (edge, public internet)
3. -> HAProxy (internal, private network)
   -> Compute VMs {
4.    -> nginx
5.    -> Containers
   }
```

Cloudflare hosted our DNS and was enabled in proxy mode for DDoS protection,
meaning DNS requests would resolve Cloudflare's edge load balancer (1).

Requests would be proxied to our nginx edge LBs (2) which handled a mix of
static sites proxied onto S3 and internal services, which were forwarded into
the private network.

HAProxy load balancers (3) received internal requests which (in addition to the
edge nginx load balancers) handled some proxying of static sites to S3 buckets,
though its primary purpose was round-robin'ing requests to our compute machines
(4 + 5). If you'd made it this far, the compute machines ran an nginx (4) which
was managed by our homegrown container orchestration system (conductor) such
that incoming service HTTP requests would be round-robin'd to the right
containers.

For reasons that I hope are now clear, we wanted to simplify this when moving to
GCP, with an aim of:

```
1.    Google Cloud Load Balancer (HTTP proxy)
2. -> HAProxy (deployed to GKE)
```

Running a single HAProxy inside GKE that would accept traffic for all existing
domains (about ~30, if memory serves) and preserve legacy routing behaviour,
such as HTTP redirects and static site hosting.

That's more context than you might need, but it helps highlight the signs that
mean it might be worth investing in some real world tests to manage the
craziness:

1. Behaviour is the sum of many production systems, some of which (e.g.
   Cloudflare) not able to be easily simulated.
2. Many parts and complex interactions mean there are likely to be awkward edge
   cases you can't easily predict.
2. Serving everything from marketing site to GoCardless API requests, mistakes
   will be visible and customer impacting, justifying additional care and time
   to reduce the risk.

[inspec]: https://docs.chef.io/inspec/

So taking inspiration from tools like [Chef InSpec][inspec] which runs tests
against external systems, we built a test suite that covered legacy routing
behaviour that could be applied to an arbitrary server, which would allow us to
verify both legacy and new systems.

This isn't as difficult as it sounds, especially when the external system can be
verified with something as standard as black-box HTTP requests. I no longer have
access to the test suite we used, but writing something similar for
incident.io's site might look like:

```ruby
require "excon"
require "rspec"

# Make a GET request with HOST_OVERRIDE applied.
def request(url)
  Excon.get(build_url(url), headers: {
    "Host" => URI.parse(url).hostname,
  })
end

# Alter the given URL to override the hostname, port and
# scheme according to the HOST_OVERRIDE envar.
def build_url(url)
  uri = URI.parse(url)
  if override = ENV["HOST_OVERRIDE"]
    override_uri = URI.parse(override)

    uri.hostname = override_uri.hostname
    uri.port = override_uri.port
    uri.scheme = override_uri.scheme
  end

  uri.to_s
end

RSpec.describe "incident.io" do
  describe "redirects" do
    {
      "https://guide.incident.io/" => "https://incident.io/guide/",
      "https://incident.io/jobs" => "/careers",
    }.each do |from_url, to_url|
      specify "#{from_url} -> #{to_url}" do
        resp = request(from_url)

        expect(resp.status).to match(301..302)
        expect(resp.headers["location"]).to eql(to_url)
      end
    end
  end
end
```

The `request` method makes an HTTP request that can be overriden to target a
specific host via the `HOST_OVERRIDE` environment variable. This means you can
invoke the test suite with no parameters to test the existing production setup
(for incident.io, Cloudflare and Netlify):

```console
$ bundle exec rspec --format=doc routing.rb

incident.io
  redirects
    https://guide.incident.io/ -> https://incident.io/guide/ ✔️
    https://incident.io/jobs -> /careers ✔️

Finished in 0.48689 seconds (files took 0.06897 seconds to load)
2 examples, 0 failures
```

Or, if you're running a local server like I do to preview this blog, you can
direct it at that instead:

```console
$ HOST_OVERRIDE=http://localhost:4000/ \
  bundle exec rspec --format=doc routing.rb

incident.io
  redirects
    https://guide.incident.io/ -> https://incident.io/guide/ (FAILED - 1) ❌
    https://incident.io/jobs -> /careers (FAILED - 2) ❌

Finished in 0.01104 seconds (files took 0.06916 seconds to load)
2 examples, 2 failures
```

Obviously my local blog server doesn't provide these redirects, but the requests
have been directed there: that's why the tests failed.

Returning to the example of migrating the routing tier, the new setup with a
single HAProxy was much more testable than the legacy system: we could boot the
HAProxy locally and point this test suite at it, allowing us to catch
regressions or bad HAProxy config before it was deployed.

There's nothing too outlandish about this setup other than realising you can
use the same testing tools as in normal software to help work with real systems.
And perhaps a bit of "oh, software engineering can help with my operations!"
instead of keeping the two areas – SWE & SRE – separate.

It'll depend on the situation at hand, but I've written test suites for big
migrations or critical operational processes many times now. Even the more
complex tests become possible with a helper that executes commands against the
machines that are involved: we once broke a 10+ step Postgres cluster migration
into a series of Ruby script/RSpec test files that executed commands via ssh,
making the migration as simple as:

```console
$ ruby scripts/01_enable_maintenance.rb
timestamp="2022-12-28T15:59:41Z" msg="enabling maintenance mode"
$ rspec scripts/01_enable_maintenance_spec.rb

01_enable_maintenance
  checking maintenance is on
    server01 ✔️
    server02 ✔️
    server03 ✔️

Finished in 0.0234 seconds (files took 0.09123 seconds to load)
3 examples, 3 failures

$ ruby scripts/02_run_checkpoint.rb
...
```

## Don't limit yourself

This might all seem like common sense, but I've rarely seen techniques like
these applied outside whichever small area of engineering they normally occupy.
And that feels a shame, especially when they can be such help elsewhere.

[not-special]: /growing-into-platform-engineering/index.html#1-platform-software-is-just-software-youre-not-special

I think it's a similar problems as SREs being slow to adopt soft-eng best
practices (see [Platform software is just software, you're not
special][not-special]) in that cross-polination requires someone to see the
potential, figure out what needs changing to make it work, then socialise it.

There's little stopping people from trying this, other than an assumption that
if a tool or process you've used successfully isn't used here, it's because it
doesn't work. But you won't know until you try, and I think we could benefit
from more people trying!
