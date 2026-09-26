#!/usr/bin/env bash
# Empty the bucket and delete the stack. Nothing keeps billing after this.
set -euo pipefail
STACK="${STACK:-nyc-lakehouse}"
REGION="${AWS_REGION:-$(aws configure get region)}"
BUCKET=$(aws cloudformation describe-stacks --stack-name "$STACK" --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='BucketName'].OutputValue" --output text 2>/dev/null || true)
[ -n "${BUCKET:-}" ] && aws s3 rm "s3://$BUCKET" --recursive --region "$REGION" || true
aws cloudformation delete-stack --stack-name "$STACK" --region "$REGION"
aws cloudformation wait stack-delete-complete --stack-name "$STACK" --region "$REGION"
echo "deleted: $STACK"
