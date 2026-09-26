#!/usr/bin/env bash
# Crawl raw -> run the ETL job -> crawl curated. Waits for each step.
set -euo pipefail
cd "$(dirname "$0")/.."
STACK="${STACK:-nyc-lakehouse}"
REGION="${AWS_REGION:-$(aws configure get region)}"
out() { aws cloudformation describe-stacks --stack-name "$STACK" --region "$REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text; }

crawl() {
  echo "crawler: $1"
  aws glue start-crawler --name "$1" --region "$REGION" 2>/dev/null || echo "  (already running)"
  while [ "$(aws glue get-crawler --name "$1" --region "$REGION" --query 'Crawler.State' --output text)" != "READY" ]; do
    sleep 10; printf '.'
  done
  echo " done"
}

crawl "$(out RawCrawlerName)"

JOB=$(out JobName)
RUN=$(aws glue start-job-run --job-name "$JOB" --region "$REGION" --query JobRunId --output text)
echo "job: $JOB run $RUN"
while :; do
  ST=$(aws glue get-job-run --job-name "$JOB" --run-id "$RUN" --region "$REGION" --query 'JobRun.JobRunState' --output text)
  [ "$ST" = "RUNNING" ] || [ "$ST" = "STARTING" ] || break
  sleep 15; printf '.'
done
echo " $ST"
[ "$ST" = "SUCCEEDED" ] || { aws glue get-job-run --job-name "$JOB" --run-id "$RUN" --region "$REGION" \
  --query 'JobRun.ErrorMessage' --output text; exit 1; }

crawl "$(out CuratedCrawlerName)"
echo "curated table is queryable in Athena workgroup $(out WorkGroupName)"
