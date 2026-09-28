# nyc-lakehouse-aws

A small AWS lakehouse that lands NYC yellow-taxi trip data in S3, curates it with a
Glue PySpark job, and serves it to Athena as a partitioned table. Everything, including
the IAM role and the Athena workgroup, is defined in one CloudFormation template; there
are no console-created resources.

```
NYC TLC Parquet ──► s3://…/raw/yellow_tripdata/month=YYYY-MM/
                         │
                    Glue crawler ──► raw_yellow_tripdata  (Glue Data Catalog)
                         │
                    Glue PySpark job  (clean, derive, partition; job bookmarks on)
                         │
                    s3://…/curated/trips/year=YYYY/month=M/  (Parquet)
                         │
                    Glue crawler ──► curated_trips ──► Athena
```

Fuller diagram and the reasoning behind each choice: [docs/architecture.md](docs/architecture.md).

## Running it

```sh
./scripts/deploy.sh                          # stack + upload the job script
./scripts/load_raw.sh 2024-01 2024-02 2024-03   # ~150 MB into the raw zone
./scripts/run_pipeline.sh                    # crawl → ETL → crawl
# then run sql/analytics.sql in the Athena workgroup
./scripts/teardown.sh                        # deletes everything, including the bucket
```

## Results from the first run

Three months of 2024 yellow-taxi data (153 MB of Parquet, 9.55 M rows):

| | |
|---|---|
| Rows in / out | 9,554,778 → 8,480,103 |
| Dropped by the cleaning rules | 1,074,675 (11.2%) |
| Glue job | 284 s on 2 × G.1X, 569 DPU-seconds |
| Trips by month | Jan 2,723,955 · Feb 2,719,826 · Mar 3,036,306 |
| Revenue by month | $74.7 M · $74.5 M · $86.1 M |
| Athena, one month via partition pruning | 0 MB scanned (count answered from metadata) |
| Athena, hourly aggregate over 3 months | 79 MB scanned |

Two things the data itself turned up:

- **11.2% of rows do not survive cleaning.** Zero-passenger trips, non-positive
  distances or totals, and dropoffs before pickups. Worth knowing before anyone quotes
  a revenue number off the raw files.
- **The monthly files are not strictly monthly.** The three 2024 files contain 4 trips
  timestamped 2009-01, 10 from 2023-12 and 2 from 2024-04. Sixteen rows out of 8.5 M,
  but they create partitions that should not exist, so query 2 in `sql/analytics.sql`
  surfaces them rather than hiding them.

Busiest hour is 18:00 (611 K trips across the quarter); the highest average fare is at
16:00 ($30.36), which is the airport-run window rather than the commuter peak.

## What the job does

`jobs/curate.py` reads the crawled raw table, drops rows that cannot be true (zero
passengers, non-positive distance or amount, dropoff before pickup, pickup dates outside
the plausible range), derives `trip_minutes` and `fare_per_km`, and writes Parquet
partitioned by `year`/`month`. It prints how many rows it dropped, because a cleaning
step that silently discards half the data is a bug, not a feature.

Job bookmarks are enabled, so re-running after adding a month processes only the new
files rather than the whole dataset again.

The crawler types the discovered partition keys as `varchar`, so queries compare them as
strings (`WHERE year = '2024'`, not `year = 2024`). That is Hive-style partition
discovery behaving normally, not a bug, but it is the first thing that trips you up.

## Cost

Designed to be cheap and to stop costing anything when idle:

| | |
|---|---|
| Glue job | 2 × G.1X workers, 20-minute timeout, a few minutes per run |
| Crawlers | two runs per load |
| Athena | 1 GB scanned per query cap, enforced by the workgroup |
| S3 | ~150 MB raw + curated; Athena results expire after 7 days |

The first full run cost about **$0.25**: $0.07 for the Glue job (569 DPU-seconds),
~$0.15 for two crawler runs, and fractions of a cent for Athena and S3.
`./scripts/teardown.sh` removes the bucket and the stack.

## Layout

```
infra/lakehouse.yaml   bucket, Glue database, IAM role, 2 crawlers, ETL job, Athena workgroup
jobs/curate.py         the Glue PySpark job
scripts/               deploy, load, run, teardown
sql/analytics.sql      queries that prove the curated table works
```
