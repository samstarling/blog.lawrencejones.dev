---
layout: post
title:  "An incident response starter-pack: how do you handle production outages?"
date:   "2020-10-27 09:00:00 +0000"
image:  /assets/images/incident-response-email.png
tags:
  - incident-response
  - sre
excerpt: |
  <p>
    Tips-and-tricks to better handle incidents, learned over years of dealing
    with production issues. Included are opinions on strategy, process, tools
    and how to handle the all-important human element.
  </p>
  <p>
    Read this if you're new to incident response and want a starter-pack of
    advice, or to contrast your own perspective with another.
  </p>

---

Throughout my career, I’ve always gravitated toward incidents. Maybe it’s the
drama, or I like to see how things go wrong. Perhaps… maybe I even cause them?

Whatever the reason, this experience has helped me develop a sense of how I like
handling incidents, something I’ve tried passing onto my team. So when a
colleague asked what our methods were, I was more than happy to respond with
some unstructured ramblings.

<figure>
  <img src="{{ "/assets/images/incident-response-email.png" | prepend:site.baseurl }}" alt="email asking for incident response advice"/>
</figure>

Since then, Matthieu has regularly nudged me to share these thoughts more
widely. This article is what happened when I took those words, dressed them up
all fancy, and sent them into the world.

I hope you find it useful!

---

[atlassian]: https://www.atlassian.com/incident-management
[atlassian/roles]: https://www.atlassian.com/incident-management/incident-response/roles-responsibilities

If you’ve ever Googled incident response, you’ll have found a load of results
about **incident roles**. Atlassian has some [incredible docs][atlassian] that
explain the concepts well.

In brief:

- Incident roles help scale incidents as your response team grows. Roles help
  separate responsibilities, ensuring someone is properly focused on each aspect
  of an incident. Defining these roles can help make everyone clear about what
  they’re expected to do, and what to expect of one another.
- Two [roles][atlassian/roles] you must be aware of:
    - Incident commander, the single point of contact for actions taken related
      to this incident. They don’t need to be the person taking the action, but
      before you reboot that server, you check with them. This avoids the
      classic ‘shit, I didn’t realise you were restoring the database onto
      _that_ node’ when you clash with a well-intentioned colleague
    - Communications. Essential, and typically the first thing forgotten when
      lacking a structured incident response process. Don’t be that team-
      nominate someone to manage comms as early as possible, and make sure all
      responders actively offload communication to them. Don’t ever split
      people’s focus by requiring them to debug and communicate, or you’ll
      half-ass both!
- There are many other roles defined in the literature, but roles only help when
  your team has a strong understanding of what each role entails. Commander and
  communications are, in my opinion, essential- adding more granularity without
  sufficient training can confuse incidents and impair your response

If you become comfortable with the roles you want to use, and your team are well
practiced in all of them, you’ll have taken the first step towards an effective
response. But now you have the roles, how does your team go about fixing the
issue?

Firstly, identify **what is bleeding**. If you can establish the scope of an
incident early, it means your next steps will be much more likely to address the
problem.

Try to:

- Identify which systems are failing, then work through the dependencies to
  understand whether the issue is due to an upstream or downstream component
- Be extremely wary of assumptions. For everything you receive from a
  third-party, trust but verify. Record whatever you did to verify, such as the
  commands you ran and the time you ran them. An incorrect assumption can derail
  your response, so do your best to avoid them!
- Once you’ve found the technical source, consider running some impact analysis.
  Don’t delay your response with this work, but if someone is spare, get them to
  estimate the scope of the impact- who and how many are affected. An inaccurate
  understanding of impact can lead to poor decisions, and clarity on who is
  affected can help other parts of your organisation (Customer Success, Support,
  etc) respond appropriately

Once the team understands the nature of the incident, you can begin to **stop
the bleeding**. Put differently, your goal should be to stop the immediate pain
and defer clean-up to a less pressured time.

For this, we need to prioritise actions to achieve the best chance of a positive
outcome. Note the phrase **“best chance”**: routine remediations that are quick
to apply should be taken first, even if you suspect it may only partially fix
the problem.

This means:

- Rollback to a known good revision, even if you think you can write a fix
  really quickly- you can always do that after you’ve rolled back, when there is
  less urgency
- Take action to preserve critical systems, even at the expense of other less
  critical flows. If a single endpoint is causing the whole system to fail,
  don’t hesitate to no-op that endpoint if it restores service to the parts that
  matter
- Make full use of your team and proactively apply whatever fixes you think are
  low-risk, even if you suspect it might not fix the whole problem: scale down
  non-essential queues, put a freeze on deploys, restart that server. Effective
  delegation means it costs little to try, provided other responders continue to
  work on root cause analysis assuming the easy fixes will fail

This should give you an idea of what your team should work on. The question is
now how should they work together to execute them?

Given incident response is so much about communication, you’ll be wanting an
effective tool for **instant messaging**, and to record a log of your actions.

Turn to Slack (or whatever your equivalent is):

[monzo/response]: https://github.com/monzo/response
[netflix/dispatch]: https://netflixtechblog.com/introducing-dispatch-da4b8a2a8072

- The first action in any incident should be creating a message channel. Several
  tools ([monzo/response][monzo/response], [Netflix’s
  Dispatch][netflix/dispatch]) can automatically create that (and more) for you,
  but even if you have to painstakingly click those buttons yourself, do it.
  It’s way worth the additional minute of downtime to get that space
  ready-to-go.
- I strongly advocate against private incident response channels. Company
  culture providing, a public channel can level-up your response by increasing
  ease of access to information. This can prevent coordination issues that you’d
  head-desk to encounter (I’ve seen two separate incident teams tackling the
  same incident, with no knowledge of each others existence…)
- Whenever you’re about to do something destructive, such as run a command or
  restart some resource, message the channel. Not only can this improve
  awareness across the team, but it provides an invaluable resource when
  building an incident log for your post-mortem

Instant messaging is great for information that is timestamped and should not be
changed. For content you expect to modify as the incident progresses, create an
**incident document** in your favourite collaborative editor (Google Docs,
Dropbox Paper, Notion, etc):

- Your organisation can draft incident doc templates that contain the structure
  you need: perhaps you have reporting responsibilities, or have a specific
  communications flow? Put it all in here, and make it easy to create documents
  from these templates with a single click
- Especially for large-scale incidents where people rotate through the incident
  team, this doc can act as the entry-point for onboarding people into the
  incident. Have whoever runs comms manage this document, maintaining a timeline
  of important events, and even draft an executive summary if the incident is
  particularly complex
- Have your technical team post code snippets or relevant logs lines into the
  document appendix, so everyone can lean on a central view of the incident

Paired together, chat log and incident doc can be powerful tools to help
coordinate the response team, while providing transparency to any invested
onlookers. Even better, this content can be easily reshaped into a post-mortem
once the dust has settled.

Finally, and most importantly, the **human element**. People make bad decisions
when stressed, and the excitement of an incident can make you forget entirely
about caring for yourself. Lead by example and be forceful when encouraging your
responders to care for themselves.

Some things to consider:

- One highly effective method to reduce stress is to take breaks, going away
  from your screen, and breathing. Actively encourage your team to take these
  pauses with you, reducing the chance you’ll screw things up by rushing
- As a general rule, take pauses whenever:
    - You get paged. It doesn’t have to be long; just 10s of breathing can
      remind your body that you’re in control, and lower your adrenaline.
    - Whenever the production impact has ceased. As soon as the alarms go quiet
      and things seem stable, call a break for the entire team. It’s rare that
      incidents don’t have extended follow-up work: rest yourself for at least
      15m before you start that process
    - During follow-up, before commencing any sort of procedure, such as
      ‘recovery of X cluster’. Get everyone to grab some air before running the
      checklist, allowing each individual to recharge in case the process goes
      wrong, or takes much longer than expected
- Ensure your incident commanders are trained to detach responders before they
  burn themselves. One important job is to order (and expense!) food before
  people get hungry. You’ll be surprised at how an incident response team will
  eat, after noisily protesting that they don’t need any food!

That’s all folks! A whistle-stop tour through my essential shopping list of
incident response practices. This list is far from complete, but can be used as
a great starter pack, or a prompt for the more experienced to consider what they
care about in their incident response process.

Just remember: take a deep breath, look out for your colleagues, blame systems
not people, and don’t rush. Good luck!

[@lawrjones]: https://twitter.com/lawrjones

_Missing from this post is any discussion of post-mortems, preparations you can
make before an incident occurs, or any trade-offs like security vs
data-integrity, vs availability. If you’re interested in hearing my opinions on
these, please do tweet me ([@lawrjones][@lawrjones]) and I’ll be delighted to
share!_
