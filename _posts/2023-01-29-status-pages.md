---
layout: post
title:  "Uptime, status pages, and transparency calculus"
date:   "2023-01-30 12:00:00 +0000"
image:  /assets/images/status-pages.png
hackernews: TODO
tags:
  - engineering
excerpt: |
  <p>
    From the evergreen AWS status page to hardcoded 100% uptime, no one fully
    trusts a status page anymore.
  </p>
  <p>
    But why is this? Companies often start with good intentions, aiming for full
    transparency. So why do so many change along the way: what pressures people
    into an evergreen status page with poorly-reflective uptime numbers?
  </p>
---

When you first create a status page, it's probably because you want to
communicate outages to your customers. The faster you can share details about an
outage, the sooner your customers know what's going on, and the more effectively
they can handle the outage.

Communicating promptly – in clear language – builds trust. And as a young
company with a customer centric focus, that's your top priority.

So why is it that as an industry, we no longer fully trust the status page of
large service providers?

[stop-lying]: https://stop.lying.cloud/

Take AWS, for example: an industry joke is that their status page is evergreen.
It got so bad that Corey Quinn created [stop.lying.cloud][stop-lying] as a
simplified, more 'truthful' version of the AWS status page. While discontinued
now, Corey's site used to filter the 'sea of green' for the services that were
broken, helping AWS customers to quickly navigate components during stressful
outages.

[gergely/op]: https://twitter.com/GergelyOrosz/status/1617965847338975232
[gergely/response]: https://twitter.com/cooperb/status/1617978304698646528

In a similar theme, just this week Gergely Orosz observed ["Slack's status page
reports 100% uptime since Feb 2022"][gergely/op] despite widespread DNS issues
and many customers seeing Slack blackouts. It seems clearly wrong to read 100%
if you're one of the customers who were impacted, after you (presumably) fell
back to smoke signals and handwritten notes for communication earlier that week.

But if you follow that thread, you'll find a Slack engineer hinting at a very
different perspective...

<div style="min-height: 660px">
<blockquote class="twitter-tweet tw-align-center">
  <p lang="en" dir="ltr">Still, that&#39;s the rules we&#39;re playing with. Does 100% uptime seem weird to me as an engineer? Sure. But the primary purpose of this number is to convey to customers whether they&#39;ll be receiving refunds or not.</p>&mdash; cooper b (@cooperb) <a href="https://twitter.com/cooperb/status/1617978304698646528?ref_src=twsrc%5Etfw">January 24, 2023</a></blockquote>
<script async src="https://platform.twitter.com/widgets.js" charset="utf-8"></script>
</div>

What's going on here, then? What does Cooper mean by "primary purpose ... is to
convey to customers whether they'll be receiving funds"?

## B2B and ELAs

Slack is a B2B company, meaning their customers are businesses rather than
individuals. When B2B companies sell software, they sign enterprise license
agreements with their customers which include provisions around uptime.

Often termed service level agreements (SLAs), they are a commitment to a level
of service – usually expressed as '99.9% uptime' or similar – that if breached,
entitles the customer to compensation.

This might seem unrelated until you realise that as a company grows, you need a
standardised way to communicate uptime to your customers that everyone –
business and customer – can agree is accurate, and relevant to SLA measurement
and compensation. Now perhaps because it's already there, or because having a
'status page' that reports more downtime than an alternative legal measure isn't
tenable, the status page often _becomes_ the official measure.

From that moment on, it becomes difficult to use the page in the same way. As
publishing an incident or uptime statistics can expose the company to financial
penalties, you need an ever-increasing amount of buy-in from senior (and
sometimes non-technical) leadership before you can give an update. Even if the
end result is the same – and you end up publishing the update – adding
executives to the incident loop delays comms, often meaning customers have
already had to fend for themselves before you notify them.

Not as simple as it may have seemed. And it's not just B2B customers who find
themselves in this situation.

## It sucks for B2C too

While B2C companies rarely bake SLAs into contracts with individual customers,
they have a different set of challenges when it comes to publicly updating
status pages.

Firstly, and this concern is shared with any company that has large customer
base, publishing an incident is not free. If you have 1M customers and you
notify them all of an incident via your status page, just 0.1% of those
customers need open a support ticket for it to bury your ops team for days.

You might say "so what, who cares? that's the price of doing business". But the
truth is most incidents only impact a handful of customers, and if you notify
for every incident, you're creating a huge amount of unnecessary stress and
worry for those who aren't impacted. On a human level, if all those customers
spend just 1 minute reading your email, that sums to about 2 years of human life
spent on an issue that may not impact them.

As if that wasn't enough of an incentive to carefully consider updates, being
'too' open can hurt your business beyond SLAs and wasted time.

## Sales

When in an RFP process with prospective customers, you're in a negotiation where
the buyer will look for reasons to lower the price. It's not unusual for the
buyer to look through a company's status page and find incidents to strengthen
their argument: "you've had several incidents over the last few months, just
look at your status page!".

For product people involved in these processes, this can be an uncomfortable
discussion. No doubt you published those updates to do right by your customers,
aiming to be transparent and help resolve the issue as quickly as possible, but
now a prospect – who would benefit from this behaviour if they become a customer
– is using it against you.

You might respond by being even more open about how you measure uptime, how your
SLA works, why the customer shouldn't worry about this. I've been there before,
in one case reviewing our process for calculating uptime and building a data
model that calculated – from request logs – the exact uptime for each customer,
helping identify who qualified for credits and how much.

Sadly, this didn't go as I'd hoped. The truth is that service quality is
extremely hard to quantify in a single number, and if you've got anything even
remotely accurate on a per-customer basis then it's likely pretty complicated.
Sharing the details of this mechanism with the prospect, who was a non-technical
but legally savvy buyer, did not help. In fact they got so tangled in the
details that it made negotiation even more sticky, in a nasty situation where
being fully transparent had made the prospect trust us even less.

Finally, being open about your incidents can feel a bit like a mugs game. No
matter your industry, you'll have competitors who are less open than you about
their issues, keeping a spotless status page despite you knowing they have
frequent, severe outages. That can work against you in sales processes, or if
you're unlucky enough to be in a regulated industry, can even have your
regulators question why you are so 'bad' in comparison.

## Where do we go from here?

Clearly it is in everyone's interest to have transparent, prompt communication
and useful/accurate uptime reporting for software. But I hope you see that by
applying penalties and building uptime into contracts, we've created a number of
incentives that work against this.

It is a real-world example of Goodhart's Law, in that as soon as we began using
uptime as a target, it stopped being a useful measure.

So what is an ideal alternative? For me, as a naive engineer, I'd love to see
the industry start viewing clear and transparent communication in past incidents
as positive signal about a working relationship. After all, we know incidents
are a fact of life, and it's much better to be honest about them than hide.

If we could couple that philosophy with break clauses in software contracts in
case of poor service, I think we're be a good step away from the nickle-and-dime
culture of service credits that can compromise transparency. After all, if the
service is really that bad, surely you'd prefer to find another provider than
fight for a 10% refund?

Sadly, with large companies placing millions on the line, that's a difficult
change. Lawyers write and sign-off on these contracts and are hired to minimise
company exposure, which makes it hard to view a software service contract as
more of a partnership than a transaction. Additionally, while this might work
well for services like Slack where downtime means you lose an hour of
productivity but soon bounce back, it's less suited to critical infrastructure
that can seriously harm a business if down for more than a couple of hours.

Perhaps we can't change the system, but I have hope we might change the game.
Two options that come to mind are increasing the perceived value of great
incident comms, or improving the tooling companies use to communicate to ease
the difficulties this post has outlined.

It's something we spend a lot of time thinking about at incident.io, and already
have a few ideas in the pipeline. So watch this space!
