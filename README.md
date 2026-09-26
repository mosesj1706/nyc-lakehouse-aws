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

## Running it

```sh
./scripts/deploy.sh                          # stack + upload the job script
./scripts/load_raw.sh 2024-01 2024-02 2024-03   # ~150 MB into the raw zone
./scripts/run_pipeline.sh                    # crawl → ETL → crawl
# then run sql/analytics.sql in the Athena workgroup
./scripts/teardown.sh                        # deletes everything, including the bucket
```

## What the job does

`jobs/curate.py` reads the crawled raw table, drops rows that cannot be true (zero
passengers, non-positive distance or amount, dropoff before pickup, pickup dates outside
the plausible range), derives `trip_minutes` and `fare_per_km`, and writes Parquet
partitioned by `year`/`month`. It prints how many rows it dropped, because a cleaning
step that silently discards half the data is a bug, not a feature.

Job bookmarks are enabled, so re-running after adding a month processes only the new
files rather than the whole dataset again.

## Cost

Designed to be cheap and to stop costing anything when idle:

| | |
|---|---|
| Glue job | 2 × G.1X workers, 20-minute timeout, a few minutes per run |
| Crawlers | two runs per load |
| Athena | 1 GB scanned per query cap, enforced by the workgroup |
| S3 | ~150 MB raw + curated; Athena results expire after 7 days |

A full run costs a few cents. `./scripts/teardown.sh` removes the bucket and the stack.

## Layout

```
infra/lakehouse.yaml   bucket, Glue database, IAM role, 2 crawlers, ETL job, Athena workgroup
jobs/curate.py         the Glue PySpark job
scripts/               deploy, load, run, teardown
sql/analytics.sql      queries that prove the curated table works
```
