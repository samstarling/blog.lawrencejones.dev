---
layout: post
title:  "Building workflows: technical deep-dive and evaluation"
date:   "2022-09-14 12:00:00 +0000"
image:  /assets/images/workflows.png
tags:
  - engineering
excerpt: |
  <p>
    Two part series about how we built incident.io workflows.
  </p>
  <p>
    <a href="https://incident.io/blog/building-workflows-part-1">Part one</a>
    explains core concepts used across the feature, and look at how code
    structure makes development easy. Followed by a deep-dive into the Workflow
    Builder (the configuration UI) showing how the concepts are exposed in APIs,
    and used to power the frontend.
  </p>
  <p>
    <a href="https://incident.io/blog/building-workflows-part-2">Part two</a>
    describes the workflow executor, showing how it listens for workflow
    triggers and if the conditions match, executes them. Finally, we reflect on
    whether we succeeded in our efforts to "slow down, to speed up!" in an
    evaluation of the project.
  </p>
---

After one year in operation, I wrote a technical deep-dive into how we built the
workflows feature at incident.io, split into a two-part series.

<figure>
  <a href="https://incident.io/blog/building-workflows-part-1" target="_blank">
    <img
        href="https://incident.io/blog/building-workflows-part-1"
        style="max-width: 100%"
        src="{{ "/assets/images/workflows.png" | prepend:site.baseurl }}"
        alt="Screenshot of the workflow blog post thumbnails"/>
  </a>
  <figcaption>
    Workflow series in two parts: <a href="https://incident.io/blog/building-workflows-part-1">part 1</a> and <a href="https://incident.io/blog/building-workflows-part-2">part 2</a>
  </figcaption>
</figure>

Part one explains core workflow concepts used across the feature, and look at
how code structure makes development easy. Followed by a deep-dive into the
Workflow Builder (the configuration UI) showing how the concepts are exposed in
APIs, and used to power the frontend.

Part two describes the workflow executor, showing how it listens for workflow
triggers and if the conditions match, executes them. Finally, we reflect on
whether we succeeded in our efforts to "slow down, to speed up!" in an
evaluation of the project.
