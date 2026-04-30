#!/usr/bin/env bash
# destroy-cluster.sh — Tear down the Crossplane Cookbook foundation in reverse order.
# Run from the repo root: ./foundations/eks-base/scripts/destroy-cluster.sh
#
# What this does:
#   Step 1: Delete recipe resources (reminder — must be done before this)
#   Step 2: Delete IAM role for Crossplane provider IRSA
#   Step 3: eksctl delete cluster
#   Step 4: CDK destroy (VPC)
#   Step 5: Verify everything is gone (no idle costs)

set -euo pipefail

_SCRIPT="${BASH_SOURCE[0]}"
case "${_SCRIPT}" in
    /*)  ;;
    */*) _SCRIPT="${PWD}/${_SCRIPT}" ;;
    *)   _SCRIPT="$(command -v "${_SCRIPT}")" ;;
esac
FOUNDATION_ROOT="$(cd "$(dirname "${_SCRIPT}")/.." && pwd)"

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --output text --query 'Account')
export AWS_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
export EKS_CLUSTER_NAME="crossplane-cookbook"
PROVIDER_IAM_ROLE="crossplane-provider-aws"

echo ""
echo "⚠️  This will destroy the Crossplane Cookbook foundation."
echo "    Ensure all recipe resources have been deleted first."
echo "    Any AWS resources created by recipes (S3, RDS, VPC, etc.) will"
echo "    block cluster deletion if still managed by Crossplane."
echo ""
read -r -p "Proceed with teardown? (y/n): " confirm
if [[ "${confirm}" != "y" ]]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "── STEP 1: Check for remaining Crossplane-managed resources ─────────────"
MR_COUNT=$(kubectl get managed --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "${MR_COUNT}" -gt 0 ]]; then
    echo "⚠️  Found ${MR_COUNT} managed resource(s) still active:"
    kubectl get managed --no-headers 2>/dev/null
    echo ""
    echo "Delete these before destroying the cluster, or they will leak in AWS."
    read -r -p "Continue anyway? (y/n): " force
    if [[ "${force}" != "y" ]]; then
        echo "Aborted. Clean up managed resources first."
        exit 1
    fi
fi

echo ""
echo "── STEP 2: Delete IAM role for Crossplane provider IRSA ─────────────────"
aws iam detach-role-policy \
    --role-name "${PROVIDER_IAM_ROLE}" \
    --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess" 2>/dev/null || true
aws iam delete-role \
    --role-name "${PROVIDER_IAM_ROLE}" 2>/dev/null || true
echo "  IAM role ${PROVIDER_IAM_ROLE} deleted."

echo ""
echo "── STEP 3: Delete EKS cluster with eksctl ───────────────────────────────"
eksctl delete cluster \
    --name "${EKS_CLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --wait

echo ""
echo "── STEP 4: Destroy VPC with CDK ─────────────────────────────────────────"
cd "${FOUNDATION_ROOT}/infra"
source .venv/bin/activate
cdk destroy --force
deactivate

echo ""
echo "── STEP 5: Verify everything is gone ────────────────────────────────────"
PASS=0
FAIL=0

check() {
    local label="$1"; local cmd="$2"; local expect_empty="$3"
    local result
    result=$(eval "${cmd}" 2>&1)
    if [[ "${expect_empty}" == "true" && -z "${result}" ]] || \
       [[ "${expect_empty}" == "false" && -n "$(echo "${result}" | grep -i 'does not exist\|not found\|NoSuchEntity\|cannot list\|error')" ]]; then
        echo "  ✓ ${label}"
        PASS=$((PASS + 1))
    else
        echo "  ✗ ${label} — may still exist"
        echo "    ${result}" | head -3
        FAIL=$((FAIL + 1))
    fi
}

check "EKS cluster deleted" \
    "aws eks describe-cluster --name ${EKS_CLUSTER_NAME} --region ${AWS_REGION} 2>&1 | grep -i 'not found\|does not exist'" \
    "false"

check "eksctl CloudFormation stack deleted" \
    "aws cloudformation describe-stacks --stack-name eksctl-${EKS_CLUSTER_NAME}-cluster --region ${AWS_REGION} 2>&1 | grep -i 'does not exist\|not found'" \
    "false"

check "CDK CloudFormation stack deleted" \
    "aws cloudformation describe-stacks --stack-name EksBaseStack --region ${AWS_REGION} 2>&1 | grep -i 'does not exist\|not found'" \
    "false"

check "EC2 nodes terminated" \
    "aws ec2 describe-instances \
        --filters Name=tag:eks:cluster-name,Values=${EKS_CLUSTER_NAME} Name=instance-state-name,Values=running,pending,stopping \
        --query 'Reservations[].Instances[].InstanceId' \
        --output text --region ${AWS_REGION}" \
    "true"

echo ""
if [[ "${FAIL}" -eq 0 ]]; then
    echo "All ${PASS} checks passed. No idle costs."
else
    echo "${FAIL} check(s) failed — review above. Re-run checks with:"
    echo "  aws eks describe-cluster --name ${EKS_CLUSTER_NAME} --region ${AWS_REGION}"
    echo "  aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE --region ${AWS_REGION}"
fi
