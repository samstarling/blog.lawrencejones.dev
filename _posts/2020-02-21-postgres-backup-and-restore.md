---
layout: post
title:  "GoCardless: Postgres Backup & Restore"
date:   "2020-02-21 11:00:00 +0000"
toc:    true
tags:
  - postgres
audience: Students looking to understand SRE
goals: Explain an example project, emphasising SRE focuses
excerpt:

---

- Intro
  - GC, team of SRE
  - Walkthrough of a project from an SRE mindset
- Set scene
  - Monolithic payments-service, powers all the API
  - Database, Postgres, it's 3TB and doubling each year
  - Payment data is important, should probably back it up...

- Good backup systems must:
  - RTO
  - RPO
  - Regularly tested
- Postgres
  - Heap `/data/postgres`
  - WAL `/data/postgres/pg_{wal,xlog}`
- Legacy (barman)
  - Barman, pulls backup every 6hrs
  - WAL is shipped whenever a segment is closed
  - Offsite backup into AWS S3, bundling the WAL
  - Shell script that pulls the backup into a container and boots Postgres,
    checking if it can see a payment
- Problems
  - Did I mention we're growing?
  - Speed limit: no more than 440MB/s (used to be)
  - 3TB is 2hrs, in a year 4hrs. Restoring from a backup? Same difference
  - Can we afford to take 4hrs restoring a backup?
  - $60 per copy taken, network cost
- Set contraints (SRE)
  - RTO = 43m (99.95%), RPO = 1m
  - Working backwards, what can possibly get us this speed?
  - 3TB moved within 43m means at least 1.16GB/s. This isn't possible without
    RAID'ing GCP persistent disks, or using emphemeral SSDs
- Disk snapshots
  - Incremental backups taken from GCP persistent disks
  - Creating snapshots scales sub-linearly with the amount of data
  - <3m to take a snapshot, <10m to restore, non-lazy

- Plan
  - Step 1: Nominate backup node
    - Take three node cluster, make it four
    - Use single disk for data and WAL, consistent snapshots
    - Non-promoteable:
      - Stolon manages our cluster, all nodes promotable
      - Snapshots impact disk performance & machine should be small
      - Add feature to mark a node as replica only, never promoted
      - Show output of stolonctl status
  - Step 2: Schedule backups
    - Generic to GCE VMs
    - Invoked locally, on the machine that is the backup target, it inspects the
      machine metadata to resolve the persistent disk and hits GCP for the
      snapshot
      ```ruby
      disk_snapshot_schedule("/data") do
        snapshot_frequency("*:0/15")
        retention_windows(
          "3d": "15m",
          "1w": "1h",
          "4w": "1d",
          "1y": "1w",
          "*":  "4w",
        )
      end
      ```
  - Step 3: Prune backups
    - Periodically prune backups, causing each snapshot to merge into the next
    - Creates cyclical storage requirements, but ensures we minimise our costs
  - Step 4: Ship WAL
    - Have Postgres push WAL segments from primary into GCS

- Good backup systems must:
  - RTO maybe?
  - RPO maybe?
  - Regularly tested: let's confirm
- ABR (automated backup recovery)
  - In the event of disaster, we'd spin-up a secondary cluster that restores
    from backup
  - Provision cluster with no nodes, recovery process scales it each day
  - Record results, alert us whenever it fails to meet RTO or RPO

- Outcomes
  - Meets current business needs, scales to support future growth
  - 5x reduction in costs
  - So fast it opens new use cases: people can spin-up test clusters with real
    data within 15m, making possible experiments that were previously too costly
  - Matures a key element of our supported tooling, accellerating GoCardless
    engineers
