#!/usr/bin/env bash
# run.sh — Recipe #1: Install provider-aws-s3 and create your first S3 Bucket.
# Run from the repo root: ./recipe-01/run.sh
#
# Prerequisites: foundations/eks-base/scripts/create-cluster.sh must have completed.
# Override bucket name: BUCKET_NAME=my-bucket ./recipe-01/run.sh

set -euo pipefail

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_ACCOUNT_ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --output text --query 'Account')

# Bucket name: globally unique by default (last 8 digits of account ID)
export BUCKET_NAME="${BUCKET_NAME:-xp-cookbook-${AWS_ACCOUNT_ID: -8}-r01}"

echo ""
echo "── STEP 1: Install provider-aws-s3 ─────────────────────────────────────"
kubectl apply -f "${RECIPE_DIR}/provider-s3.yaml"
echo "Waiting for provider-aws-s3 to become healthy (may take ~60s)..."
kubectl wait provider/upbound-provider-aws-s3 \
    --for=condition=Healthy \
    --timeout=300s
echo "provider-aws-s3 is healthy."

echo ""
echo "── STEP 2: Create S3 Bucket Managed Resource ────────────────────────────"
echo "Bucket name : ${BUCKET_NAME}"
echo "Region      : ${AWS_REGION}"
envsubst < "${RECIPE_DIR}/bucket.yaml" | kubectl apply -f -

echo ""
echo "── STEP 3: Watch Crossplane reconcile ───────────────────────────────────"
echo "Waiting for bucket to become Ready (Crossplane is calling the S3 API)..."
kubectl wait bucket/"${BUCKET_NAME}" \
    --for=condition=Ready \
    --timeout=120s
echo "Bucket is Ready."

echo ""
echo "── STEP 4: Verify ───────────────────────────────────────────────────────"
echo ""
kubectl get bucket "${BUCKET_NAME}" -o wide
echo ""
aws s3api head-bucket --bucket "${BUCKET_NAME}" --region "${AWS_REGION}" 2>/dev/null \
    && echo "AWS confirms: s3://${BUCKET_NAME} exists." \
    || echo "Bucket not found in AWS — check region and permissions."
echo ""
echo "Console: https://s3.console.aws.amazon.com/s3/buckets/${BUCKET_NAME}"

echo ""
echo "── STEP 5: Delete demonstration ─────────────────────────────────────────"
echo "This is the aha moment: deleting the K8s resource deletes the S3 bucket."
read -r -p "Delete the bucket now? (y/n): " confirm
if [[ "${confirm}" == "y" ]]; then
    envsubst < "${RECIPE_DIR}/bucket.yaml" | kubectl delete -f -
    echo "Waiting for deletion propagation to AWS..."
    kubectl wait bucket/"${BUCKET_NAME}" \
        --for=delete \
        --timeout=120s 2>/dev/null || true
    echo "Done. Bucket is gone from both Kubernetes and AWS."
else
    echo "Bucket left running. To delete manually:"
    echo "  kubectl delete bucket ${BUCKET_NAME}"
fi
