-- Run in the nyc-lakehouse-wg workgroup, database nyc-lakehouse_db.
-- Partition keys (year, month) are discovered by the crawler and typed as varchar,
-- so they are compared as strings: WHERE year = '2024', not year = 2024.
-- The workgroup caps any single query at 1 GB scanned.

-- 1. Did the pipeline work? Trips and revenue per month.
SELECT year, month, count(*) AS trips, round(sum(total_amount), 0) AS revenue_usd
FROM curated_trips
GROUP BY year, month
ORDER BY year, month;

-- 2. Data quality: rows whose pickup date falls outside the file they arrived in.
--    The TLC monthly files contain a handful of these (a 2009 timestamp in the
--    January 2024 file, and so on). Small enough to ignore, large enough to know about.
SELECT year, month, count(*) AS trips
FROM curated_trips
WHERE year <> '2024' OR month NOT IN ('1', '2', '3')
GROUP BY year, month
ORDER BY year, month;

-- 3. Demand by hour of day: the shape every taxi analysis starts from.
SELECT hour(pickup_ts) AS hr,
       count(*) AS trips,
       round(avg(trip_minutes), 1) AS avg_minutes,
       round(avg(total_amount), 2) AS avg_fare
FROM curated_trips
WHERE year = '2024'
GROUP BY hour(pickup_ts)
ORDER BY hr;

-- 4. Busiest pickup zones, with distance and tipping behaviour.
SELECT pickup_zone_id,
       count(*) AS trips,
       round(avg(trip_miles), 2) AS avg_miles,
       round(avg(tip_amount / nullif(fare_amount, 0)) * 100, 1) AS avg_tip_pct
FROM curated_trips
WHERE year = '2024'
GROUP BY pickup_zone_id
ORDER BY trips DESC
LIMIT 15;

-- 5. Partition pruning, demonstrated: one month, ~5 MB scanned instead of ~14 MB.
SELECT count(*) AS january_trips
FROM curated_trips
WHERE year = '2024' AND month = '1';
