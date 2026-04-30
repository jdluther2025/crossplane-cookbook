#!/usr/bin/env bash
# cleanup.sh — Delete Recipe #1 resources (S3 Bucket MR and provider-aws-s3).
# Run before destroy-cluster.sh: ./recipe-01/cleanup.sh

set -euo pipefail

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export AWS_REGION="${AWS_REGION:-us-east-1}"
export NAMESPACE="${NAMESPACE:-default}"
export AWS_ACCOUNT_ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --output text --query 'Account')
export BUCKET_NAME="${BUCKET_NAME:-xp-cookbook-${AWS_ACCOUNT_ID: -8}-r01}"

BUCKET_RESOURCE="buckets.s3.aws.m.upbound.io"

echo ""
echo "── Recipe #1 Cleanup ────────────────────────────────────────────────────"
echo "Bucket : ${BUCKET_NAME}"
echo "Region : ${AWS_REGION}"
echo ""
read -r -p "Delete bucket MR and provider-aws-s3? (y/n): " confirm
if [[ "${confirm}" != "y" ]]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "── STEP 1: Delete S3 Bucket Managed Resource ────────────────────────────"
envsubst < "${RECIPE_DIR}/bucket.yaml" | kubectl delete -f - 2>/dev/null || true
echo "Waiting for deletion to propagate to AWS..."
kubectl wait "${BUCKET_RESOURCE}/${BUCKET_NAME}" \
    --namespace "${NAMESPACE}" \
    --for=delete \
    --timeout=120s 2>/dev/null || true

aws s3api head-bucket --bucket "${BUCKET_NAME}" --region "${AWS_REGION}" 2>/dev/null \
    && echo "  ⚠️  Bucket still exists in AWS — wait a moment and re-run." \
    || echo "  ✓ AWS confirms: s3://${BUCKET_NAME} is gone."

echo ""
echo "── STEP 2: Delete provider-aws-s3 ──────────────────────────────────────"
kubectl delete provider crossplane-contrib-provider-aws-s3 2>/dev/null || true
echo "  ✓ provider-aws-s3 removed."

echo ""
echo "Recipe #1 cleanup complete. Safe to run destroy-cluster.sh."
