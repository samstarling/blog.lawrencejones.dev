---
layout: post
title:  "Fixing flaky dbt tests with a sync cutoff"
date:   "2022-02-09 12:00:00 +0000"
hackernews: https://news.ycombinator.com/item?id=30272312
tags:
  - data
  - dbt
excerpt: |
  <p>
    Using a sync cutoff when building our dbt models helped fix our flaky tests,
    making our CI much more reliable and exposing latent bugs.
  </p>

---

[incident]: https://incident.io/
[incident/data-stack]: https://incident.io/blog/data-stack
[fivetran]: https://fivetran.com/
[dbt]: https://getdbt.com/
[metabase]: https://www.metabase.com/

I work at [incident.io][incident], a start-up in London that just built our
[first data stack][incident/data-stack] using [Fivetran][fivetran] for ETL and
[dbt][dbt] for transformations.

While we built the pipeline for internal use only, we soon realised
[Metabase][metabase] could provide much better dashboards for our internal
product than our ~~scrappy~~ _basic_ Javascript graphs.

We wanted to embed Metabase straight in our product, like this:

![Screenshot of incident.io dashboard](/assets/images/flaky-dbt-tests-insights.png)

This would be fine, except we'd accepted some compromises while building for
ourselves that we couldn't if we were to provide this data to our customers.
Namely, our dbt tests were flaky, and there was no way we'd ship a data product
where our tests would regularly fail.

## Flaky tests

The test failures were all relationship tests, which look like this in the dbt
schema:

```yaml
---
version: 2
models:
  - name: actions
    description: Incident actions
    columns:
      - name: organisation_id
        description: "Organisation ID"
        tests:
          - not_null
          - relationships:
              to: ref('organisations')
              field: organisation_id
```

This test gets dbt to confirm all `organisation_id` values in the
`actions` table appear in `organisations`. Put simply,
have we screwed something up in our join, or does the data look good?

According to our test suite, the data _did not_ look good. But only on some
runs, where about once every three runs of the test suite we'd see an error like
this:

```
Failure in test relationships_incident_actions_organisation_id__ref_organisations_ (models/staging/product/stg_product.yml)
Got 1 result, configured to fail if != 0

compiled SQL at target/compiled/analytics/models/staging/product/stg_product.yml/relationships_inc_e2d88f3fd5bd723431990564532e121c.sql
```

This isn't the clearest output, but it can understood as "there were
organisation IDs in the actions table that had no match in the organisations
table".

That's not good, but why is it happening?

## How we sync: hello, Fivetran!

We use Fivetran to pull data from our Postgres database, the source of the
organisation and incident actions, into our BigQuery data warehouse.

In Postgres-land, you can expect to be running with a (mostly) consistent view
of data across all tables. Even with respect to individual queries, data is
inserted and updated atomically, so it would be very strange for you to find a
resource that references something in another table where that reference does
not exist.

That begs the question: if we're sourcing our data from Postgres, which is
consistent, what gives with these broken relations?

Well, while Postgres might be consistent, the resulting BigQuery data warehouse
is not. The syncing process for Fivetran can be reduced to this psuedo-code:

```
every 15 minutes:
    for table in database.all_tables:
        changes_since_last_sync = table.get_changes_since(table.last_synced)
        table.last_synced = now()
        warehouse.insert(table, changed_since_last_sync)
```

BigQuery does not provide consistency across multiple tables, so we end up
producing a 'jagged' dataset, where each table is synced to a different point in
time.

Visually, this might look like:

```
                  t0
organisations     ======> t1
incident_actions  =============> t2
other_table       =====================> t3
```

Where t0 is when the sync begins, after which we:

- Sync `organisations` up until t1
- Sync `incident_actions` up until t2
- etc

If after t0, but before t2, we add an organisation and some incident actions
that relate to it, then our sync will have skipped the organisation but included
the actions.

That's the cause of our failing tests, and why they fail randomly (flake): it
entirely depends on when Fivetran has performed a sync and what data may have
been missed on whether the test fails.

## Fixing with a cutoff

In an ideal world, our BigQuery warehouse would have tables that contain updates
up-to a consistent cutoff, applied equally across all tables. That would avoid
us having patchy relations, and allow us to lean on our tests.

While Fivetran might not work like this, we can patch over it using dbt.

First, we create a dbt model `sync_watermarks` that estimates a timestamp that
is safely before the start of the last Fivetran run.

It looks like this:

```sql
-- models/sync_watermarks.sql
{% raw %}{{
  config(
    materialized = "table",
  )
}}{% endraw %}

-- This table marks the point at which we've run dbt. The
-- cutoff is used to filter any very recent changes from each
-- database table, allowing us to ensure each table in the
-- dataset is consistent, even when syncs happen at different
-- periods.
-- 
-- 20m is chosen as Fivetran attempts to sync every 15m, which
-- should complete in <1m. Going back 20m ensures we cutoff
-- safely after the start of the last complete sync, meaning
-- each table will be consistent.
select
  timestamp_sub(current_timestamp(), interval 20 minute) as cutoff_at
```

As our Fivetran syncs every 15m, and each sync completes in ~1m, we know all
tables will have completed a sync <20m ago, at which point it will contain all
data up-to and beyond that cutoff.

This means we can apply the cutoff to all tables, ignoring any inconsistent sync
progress beyond that point.

Note that we've materialised this table so it gets calculated just once, at the
start of our dbt run. This is as opposed to a view, where any time we query the
table, the value of `current_timestamp()` would change.

Then for each of our table models, we apply the cutoff against the row created
at:

```sql
{% raw %}with

source as (
  select
    *
  from
    {{ source('core_production_public', 'organisations') }},
    {{ ref('sync_watermarks') }} sync_watermarks
  where
    _fivetran_deleted is null
    and created_at < sync_watermarks.cutoff_at
),

renamed as (
  select
    /* ... */
  from
    source
)

select * from renamed{% endraw %}
```

Using `ref('sync_watermarks')` means dbt will know to build the
watermark before our model, as it will track the dependency in dbt's graph.

We apply the same pattern to the rest of our database tables, ensuring each
table has a consistent cutoff.

No more `organisation_id not found in organisations`!

## Other data sources

We don't just sync data from our Postgres database: we pull it from a variety of
sources, such as Segment or social media, all of which might reference core
Postgres resources.

If we see similar flaky test issues, we can reuse the cutoff on these models
too. We do just that for our BigQuery event tables which are written to in
realtime from the product.

This ensures we get a consistent snapshot across all our data models, regardless
of source.

## Wasn't that easy?

There's many ways to solve this problem, but this is simple and quick, and has
the advantage of saving the cutoff into your data warehouse if you ever need to
reference or check it.

Whether you use this or something else, it's important to avoid flaky tests.
When first applying the cutoff, I was unsurprised to discover failures that were
unrelated to the cutoff, and were legitimate bugs.

While it was the right decision to ignore these failures when prototyping, I'm
glad we sorted it before exposing this data to our customers.

Life is just less stress when you have a test suite you can depend on!
