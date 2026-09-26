#!/usr/bin/env bash
# Download NYC TLC yellow-taxi Parquet months and put them in the raw zone.
#   ./scripts/load_raw.sh 2024-01 2024-02 2024-03
set -euo pipefail
cd "$(dirname "$0")/.."
STACK="${STACK:-nyc-lakehouse}"
REGION="${AWS_REGION:-$(aws configure get region)}"
MONTHS=("${@:-2024-01 2024-02 2024-03}")

BUCKET=$(aws cloudformation describe-stacks --stack-name "$STACK" --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='BucketName'].OutputValue" --output text)

mkdir -p .data
for M in "${MONTHS[@]}"; do
  F="yellow_tripdata_${M}.parquet"
  [ -f ".data/$F" ] || curl -sSfL -o ".data/$F" "https://d37ci6vzurychx.cloudfront.net/trip-data/$F"
  echo "$F  $(du -h ".data/$F" | cut -f1)"
  # One prefix per month keeps the crawler's job obvious and lets bookmarks work per file.
  aws s3 cp ".data/$F" "s3://$BUCKET/raw/yellow_tripdata/month=$M/$F" --region "$REGION"
done
echo "raw zone:"
aws s3 ls "s3://$BUCKET/raw/yellow_tripdata/" --recursive --human-readable --region "$REGION" | tail -5
