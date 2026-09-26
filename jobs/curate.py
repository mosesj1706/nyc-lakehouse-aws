"""Raw NYC yellow-taxi trips -> a curated, partitioned, queryable table.

Reads the raw table the crawler registered, drops rows that cannot be true,
derives the partition columns, and writes Parquet partitioned by year/month.
Job bookmarks are on, so a second run only processes files added since the last one.

Run by the Glue job defined in infra/lakehouse.yaml; arguments come from that template.
"""
import sys

from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from pyspark.sql import functions as F

args = getResolvedOptions(sys.argv, ["JOB_NAME", "database", "source_table", "target_path"])

sc = SparkContext.getOrCreate()
glue = GlueContext(sc)
spark = glue.spark_session
job = Job(glue)
job.init(args["JOB_NAME"], args)

# from_catalog rather than a raw S3 path: the crawler owns the schema, and bookmarks
# need the catalog to know which files have already been read.
raw = glue.create_dynamic_frame.from_catalog(
    database=args["database"],
    table_name=args["source_table"],
    transformation_ctx="raw_trips",
).toDF()

before = raw.count()

# The public dataset has rows with zero passengers, negative fares, and pickup dates
# from outside the file's own month. None of those survive into the curated zone.
trips = (
    raw.withColumn("pickup_ts", F.col("tpep_pickup_datetime").cast("timestamp"))
       .withColumn("dropoff_ts", F.col("tpep_dropoff_datetime").cast("timestamp"))
       .filter(F.col("pickup_ts").isNotNull() & F.col("dropoff_ts").isNotNull())
       .filter(F.col("dropoff_ts") > F.col("pickup_ts"))
       .filter(F.col("passenger_count") > 0)
       .filter(F.col("trip_distance") > 0)
       .filter(F.col("total_amount") > 0)
       .withColumn("year", F.year("pickup_ts"))
       .withColumn("month", F.month("pickup_ts"))
       .filter(F.col("year").between(2009, 2030))
       .withColumn("trip_minutes",
                   F.round((F.col("dropoff_ts").cast("long") - F.col("pickup_ts").cast("long")) / 60, 2))
       .withColumn("fare_per_km", F.round(F.col("total_amount") / (F.col("trip_distance") * 1.60934), 2))
       .select(
           "pickup_ts", "dropoff_ts", "trip_minutes",
           F.col("passenger_count").cast("int").alias("passengers"),
           F.col("trip_distance").cast("double").alias("trip_miles"),
           F.col("fare_amount").cast("double").alias("fare_amount"),
           F.col("tip_amount").cast("double").alias("tip_amount"),
           F.col("total_amount").cast("double").alias("total_amount"),
           "fare_per_km",
           F.col("payment_type").cast("int").alias("payment_type"),
           F.col("PULocationID").cast("int").alias("pickup_zone_id"),
           F.col("DOLocationID").cast("int").alias("dropoff_zone_id"),
           "year", "month",
       )
)

after = trips.count()
print(f"[curate] rows in={before} out={after} dropped={before - after} ({100 * (before - after) / max(before, 1):.1f}%)")

if after:
    (trips.repartition("year", "month")       # one file per partition instead of 200 tiny ones
          .write.mode("append")
          .partitionBy("year", "month")
          .parquet(args["target_path"]))
    print(f"[curate] wrote {after} rows to {args['target_path']}")
else:
    print("[curate] nothing new to write (bookmark found no unprocessed files)")

job.commit()
