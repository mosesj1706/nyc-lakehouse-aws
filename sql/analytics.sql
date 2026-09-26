-- Run these in the nyc-lakehouse-wg workgroup, database nyc_lakehouse_db.
-- Every query reads only the partitions it needs; the workgroup caps any single
-- query at 1 GB scanned so a mistake costs a fraction of a cent.

-- 1. Did the pipeline work? Rows per month, and what the cleaning removed.
SELECT year, month, count(*) AS trips, round(sum(total_amount), 0) AS revenue_usd
FROM curated_trips
GROUP BY year, month
ORDER BY year, month;

-- 2. Demand by hour of day: the shape every taxi analysis starts from.
SELECT hour(pickup_ts) AS hr,
       count(*) AS trips,
       round(avg(trip_minutes), 1) AS avg_minutes,
       round(avg(total_amount), 2) AS avg_fare
FROM curated_trips
WHERE year = 2024
GROUP BY hour(pickup_ts)
ORDER BY hr;

-- 3. Busiest pickup zones, with how far people go from each.
SELECT pickup_zone_id,
       count(*) AS trips,
       round(avg(trip_miles), 2) AS avg_miles,
       round(avg(tip_amount / nullif(fare_amount, 0)) * 100, 1) AS avg_tip_pct
FROM curated_trips
WHERE year = 2024
GROUP BY pickup_zone_id
ORDER BY trips DESC
LIMIT 15;

-- 4. Partition pruning, demonstrated: this reads one month, not the whole table.
SELECT count(*) AS january_trips
FROM curated_trips
WHERE year = 2024 AND month = 1;
