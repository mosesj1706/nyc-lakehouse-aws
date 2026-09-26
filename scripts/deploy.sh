#!/usr/bin/env bash
# Create or update the stack, then upload the job script the stack points at.
set -euo pipefail
cd "$(dirname "$0")/.."
STACK="${STACK:-nyc-lakehouse}"
REGION="${AWS_REGION:-$(aws configure get region)}"

aws cloudformation deploy \
  --template-file infra/lakehouse.yaml \
  --stack-name "$STACK" \
  --capabilities CAPABILITY_NAMED_IAM \
  --region "$REGION"

BUCKET=$(aws cloudformation describe-stacks --stack-name "$STACK" --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='BucketName'].OutputValue" --output text)

aws s3 cp jobs/curate.py "s3://$BUCKET/scripts/curate.py" --region "$REGION"

echo
echo "stack:  $STACK ($REGION)"
echo "bucket: $BUCKET"
aws cloudformation describe-stacks --stack-name "$STACK" --region "$REGION" \
  --query "Stacks[0].Outputs[].[OutputKey,OutputValue]" --output table
