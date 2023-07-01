---
layout: post
title:  "Copy-and-paste is the goal"
date:   "2023-07-03 12:00:00 +0000"
image:  /assets/images/copy-paste-code.png
tags:
  - engineering
excerpt: |
  <p>
    From the moment you learn programming people tell you "don't repeat
    yourself!"
  </p>
  <p>
    So what I'm about to suggest might sound odd. But I'm here to say that if
    you want to ship high-quality software at pace, you should be investing in
    abstractions that are designed to enable copy-and-paste.
  </p>
---

From the moment you learn programming people tell you "don't repeat yourself!"

So what I'm about to suggest might sound odd. But I'm here to say that if you
want to ship high-quality software at pace, you should be investing in
abstractions that are designed to enable copy-and-paste.

When you look at most software teams, they work within an existing application
and extend it with new features. Most tickets are "build another X" where X is a
backend API, frontend form, database model, whatever.

For your team's velocity to scale with the size of your codebase, you want every
version of X to look as similar as is possible. Developers should be able to
jump between each form/endpoint/etc and be immediately familiar, just as people
can move between vehicles and know how to drive because the steering wheel is in
the same place.

That doesn't just help people understanding the code: it drives down the time to
create new features because you can bootstrap code by copy-and-pasting from an
existing module, then switch out the relevant pieces until it does what you need
it to do.

Let's see what that looks like in practice.

## An example

At [incident.io](https://incident.io/), our engineering team is committed to
moving fast, and we've made deliberate investments to enable copy-and-paste as a
strategy to quickly build
new features.

Our product is a Slack app, and most product features include building Slack
forms. When we noticed time-to-build for Slack modals was high (2-5 days,
depending on the modal) and it was hard to share code between them due to lack
of consistency, we invested in a `slackv2` framework that was entirely geared
toward copy-and-paste.

Let's take a look at two different modals as they appear in our Slack app.

![Escalation and action create modal side-by-side](/assets/images/copy-paste-modals.png)

On the left is the "escalate to PagerDuty" form, responsible for creating an
escalation in our database and communicating with the PagerDuty API to trigger
an incident. The service and "Who do you need?" inputs are powered by a
typeahead API that fetches options from PagerDuty.

The right modal is much simpler, allowing creation of an action (e.g. Reboot the
database) against the current incident.

Quite different behaviours, especially considering communication with
third-parties and even just the complexity of each modal. And yet, here's the
code...

![Escalation and action modal code side-by-side](/assets/images/copy-paste-code.png)

These files, structurally, are _exactly the same_. Sure, they implement the same
interfaces so they'd naturally look similar but care has been taken to ensure
even the method implementations appear in the right order.

Both go:

- `modal.Register` adds this modal to our router and provides several 'snapshot'
  fixtures that we use to build a Storybook-esque development library of app
  modals.
- `EscalatePagerDuty` is the modal itself.
- `EscalatePagerDutyProps` are static props the app instantiates, much like
  React-props.
- `EscalatePagerDutyState` is temporary state stored in the modal, such as
  values from input fields.

And so on. Notice none of what I listed is part of the modal interface, it's
just about how you layout the code inside of the file.

This is a massive win. Anyone can move between modals and know exactly where
they are, but – no surprises guessing what comes next – if you want to create a
new modal then just...

```
cp slack/views/escalate_pagerduty.go slack/views/my_new_modal.go
```

...and do a `s/EscalatePagerDuty/MyNewModal/g`. We've even paid attention to
things like the callback ID (Slack uses these to identify modals and can be seen
as a magic string that ties an existing modal to an implementation) so they use
CamelCase and will be included in the search-and-replace.

Within 60s you have a new modal that you can tear apart until it does what you
need it to.

This is obviously great, but you can get even more bang-for-buck by applying
similar ideas to tests. The 'blank page' problem where building a test file with
all the right stubs from scratch is a massive deterent to writing tests, and if
you want a comprehensive test suite that isn't multiplying your time-to-build,
you need to be ruthless with consistency.

So we did that, too.

![Escalation and action modal test code side-by-side](/assets/images/copy-paste-test-code.png)

Along with your original modal, you copy the test file and tweak/replace until
it does what you need. Most of the factories are already initialised and it's
easy to find more complex test code because each test file is structurally so
similar, so you can dive into other files looking for examples when needed.

It's so easy to bootstrap great tests that this is the only part of our codebase
where we mandate that you have them.

## Just try it.

If you've never worked in a codebase that prioritises this before, it might feel
weird to view copy-and-pasting code as a good thing.

It's definitely not always good: you shouldn't be copy-and-pasting complex
logic, and I have another rule-of-thumb I apply just as frequently about "only
one part of the codebase should do X" that counterbalances this. This is clearly
not about blindly copying whatever you feel and is much more about bootstrapping
structure than breaking DRY-principles.

I promise though, if you can understand that nuance and invest in abstractions
that have copy-and-paste in mind, you're at risk of becoming an extremely
productive development team.
