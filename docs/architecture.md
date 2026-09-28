# Architecture

```
                     NYC TLC yellow-taxi Parquet (public, monthly files)
                                      │
                                      │  scripts/load_raw.sh
                                      ▼
   ┌──────────────────────────────────────────────────────────────────────┐
   │  S3   nyc-lakehouse-<account>-<region>                               │
   │                                                                      │
   │   raw/yellow_tripdata/month=YYYY-MM/*.parquet      153 MB, 9.55 M rows
   │   curated/trips/year=YYYY/month=M/*.parquet        8.48 M rows       │
   │   scripts/curate.py                                                  │
   │   athena-results/                    (lifecycle rule: expire at 7d)  │
   └──────────────────────────────────────────────────────────────────────┘
        │                        ▲                         │
        │ crawl                  │ write                   │ crawl
        ▼                        │                         ▼
   raw_yellow_tripdata ──────────┼──────────────────► curated_trips
        │                        │                         │
        │   Glue Data Catalog (nyc-lakehouse_db)            │
        ▼                        │                         ▼
   ┌─────────────────────────────┴───────┐        ┌──────────────────────┐
   │  Glue job  nyc-lakehouse-curate     │        │  Athena workgroup    │
   │  PySpark, 2 × G.1X, bookmarks on    │        │  nyc-lakehouse-wg    │
   │                                     │        │  1 GB scan cap/query │
   │  · drop impossible rows (11.2%)     │        │  results → S3, 7d    │
   │  · derive trip_minutes, fare_per_km │        └──────────────────────┘
   │  · partition by year / month        │
   │  284 s, 569 DPU-seconds             │
   └─────────────────────────────────────┘

   IAM: one role, scoped to this bucket and the catalog. Nothing else in the
   account is reachable from the job or the crawlers.

   Everything above is created by infra/lakehouse.yaml. Nothing is clicked
   into existence in the console, so the stack is reproducible from empty.
```

## Why it is shaped this way

**Two zones, not one.** Raw keeps the vendor's files byte-for-byte so a bad
transform is always recoverable by re-running the job. Curated holds only rows
that passed the quality rules, in the layout queries actually want.

**Partitioned by year and month** because every question anyone asks of taxi
data is time-bounded. A count for one month reads zero bytes; the same query
over an unpartitioned table would scan all 9.5 million rows.

**Parquet, not CSV**, in both zones: columnar, compressed, and Athena bills by
bytes scanned, so the storage format is a cost decision as much as a speed one.

**Job bookmarks on.** Adding a month and re-running processes that month only.
Without them, every run reprocesses the whole history and the bill grows with
the dataset rather than with the new data.

**Guardrails in the template, not in a runbook.** The 20-minute job timeout, the
two-worker cap, the 1 GB per-query scan ceiling and the 7-day expiry on query
results are all in `infra/lakehouse.yaml`. A mistake costs cents because the
limits are declared, not remembered.
