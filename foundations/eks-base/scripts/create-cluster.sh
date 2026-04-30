#!/usr/bin/env bash
# create-cluster.sh — Deploy VPC with CDK, create EKS cluster with eksctl,
#                     install Crossplane, and wire up IRSA for the AWS provider.
# Run from the repo root: ./foundations/eks-base/scripts/create-cluster.sh
#
# What this does:
#   Step 1: CDK deploys VPC
#   Step 2: Read CDK outputs (subnet IDs)
#   Step 3: envsubst fills cluster.yaml.template → cluster/cluster.yaml
#   Step 4: eksctl creates EKS cluster with OIDC enabled
#   Step 5: Install Crossplane via Helm
#   Step 6: Create IAM role for Crossplane provider IRSA
#   Step 7: Install provider-family-aws + apply DeploymentRuntimeConfig (IRSA)
#   Step 8: Apply ClusterProviderConfig (source: IRSA)
#   Step 9: Verify
#
# Override defaults with environment variables before running:
#   INSTANCE_TYPE=t3.medium ./foundations/eks-base/scripts/create-cluster.sh

set -euo pipefail

_SCRIPT="${BASH_SOURCE[0]}"
case "${_SCRIPT}" in
    /*)  ;;
    */*) _SCRIPT="${PWD}/${_SCRIPT}" ;;
    *)   _SCRIPT="$(command -v "${_SCRIPT}")" ;;
esac
FOUNDATION_ROOT="$(cd "$(dirname "${_SCRIPT}")/.." && pwd)"
STACK_NAME="EksBaseStack"

# ── Parameters (override via env vars) ─────────────────────────────────────

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --output text --query 'Account')
export AWS_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
export EKS_CLUSTER_NAME="crossplane-cookbook"
export K8S_VERSION="${K8S_VERSION:-1.32}"
export EKS_DEFAULT_MNG_NAME="${EKS_DEFAULT_MNG_NAME:-system}"
export EKS_DEFAULT_MNG_MIN="${EKS_DEFAULT_MNG_MIN:-1}"
export EKS_DEFAULT_MNG_MAX="${EKS_DEFAULT_MNG_MAX:-3}"
export EKS_DEFAULT_MNG_DESIRED="${EKS_DEFAULT_MNG_DESIRED:-2}"
CROSSPLANE_VERSION="${CROSSPLANE_VERSION:-2.2.0}"
PROVIDER_FAMILY_VERSION="${PROVIDER_FAMILY_VERSION:-v2.0.0}"
PROVIDER_IAM_ROLE="crossplane-provider-aws"

# ── Instance type selection ─────────────────────────────────────────────────
# Override with: INSTANCE_TYPE=t3.medium ./foundations/eks-base/scripts/create-cluster.sh

if [[ -z "${INSTANCE_TYPE:-}" ]]; then
    echo "── Select node instance type ───────────────────────────────────────────"
    echo "  1) t3.medium   — 2 vCPU,  4GB   (general testing, lowest cost)"
    echo "  2) t3.xlarge   — 4 vCPU, 16GB   (moderate workloads)"
    echo "  3) m5.xlarge   — 4 vCPU, 16GB   (production-like, AI/ML default)"
    echo "  4) m5.2xlarge  — 8 vCPU, 32GB   (heavier AI/ML workloads)"
    echo ""
    read -r -p "Choice (1-4) [default: 1]: " type_choice
    case "${type_choice:-1}" in
        1) INSTANCE_TYPE="t3.medium" ;;
        2) INSTANCE_TYPE="t3.xlarge" ;;
        3) INSTANCE_TYPE="m5.xlarge" ;;
        4) INSTANCE_TYPE="m5.2xlarge" ;;
        *) echo "Invalid choice. Using t3.medium."; INSTANCE_TYPE="t3.medium" ;;
    esac
fi
export INSTANCE_TYPE

echo ""
echo "── STEP 1: Deploy VPC with CDK ─────────────────────────────────────────"
cd "${FOUNDATION_ROOT}/infra"
python3 -m venv .venv 2>/dev/null || true
source .venv/bin/activate
pip install -q -r requirements.txt
cdk deploy --require-approval never
deactivate

echo ""
echo "── STEP 2: Read CDK outputs ─────────────────────────────────────────────"

get_output() {
    aws cloudformation describe-stacks \
        --stack-name "${STACK_NAME}" \
        --region "${AWS_REGION}" \
        --query "Stacks[0].Outputs[?OutputKey=='${1}'].OutputValue" \
        --output text
}

export VPC_ID=$(get_output "VpcId")
PRIVATE_SUBNETS=$(get_output "PrivateSubnetIds")
PUBLIC_SUBNETS=$(get_output "PublicSubnetIds")

export PRIVATE_SUBNET_1=$(echo "${PRIVATE_SUBNETS}" | cut -d',' -f1)
export PRIVATE_SUBNET_2=$(echo "${PRIVATE_SUBNETS}" | cut -d',' -f2)
export PUBLIC_SUBNET_1=$(echo "${PUBLIC_SUBNETS}" | cut -d',' -f1)
export PUBLIC_SUBNET_2=$(echo "${PUBLIC_SUBNETS}" | cut -d',' -f2)

export AZ_1=$(aws ec2 describe-subnets --subnet-ids "${PRIVATE_SUBNET_1}" --region "${AWS_REGION}" \
    --query "Subnets[0].AvailabilityZone" --output text)
export AZ_2=$(aws ec2 describe-subnets --subnet-ids "${PRIVATE_SUBNET_2}" --region "${AWS_REGION}" \
    --query "Subnets[0].AvailabilityZone" --output text)

echo ""
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║          Crossplane Cookbook — Foundation Summary                   ║"
echo "╠══════════════════════════════════════════════════════════════════════╣"
echo "║  Cluster name   : ${EKS_CLUSTER_NAME}"
echo "║  AWS account    : ${AWS_ACCOUNT_ID}"
echo "║  Region         : ${AWS_REGION}"
echo "║  Kubernetes     : ${K8S_VERSION}"
echo "║  Crossplane     : ${CROSSPLANE_VERSION}"
echo "╠══════════════════════════════════════════════════════════════════════╣"
echo "║  VPC            : ${VPC_ID}"
echo "║  Private subnet : ${PRIVATE_SUBNET_1} (${AZ_1})"
echo "║  Private subnet : ${PRIVATE_SUBNET_2} (${AZ_2})"
echo "║  Public subnet  : ${PUBLIC_SUBNET_1} (${AZ_1})"
echo "║  Public subnet  : ${PUBLIC_SUBNET_2} (${AZ_2})"
echo "╠══════════════════════════════════════════════════════════════════════╣"
echo "║  Node group     : ${EKS_DEFAULT_MNG_NAME}"
echo "║  Instance type  : ${INSTANCE_TYPE}"
echo "║  Min / Max      : ${EKS_DEFAULT_MNG_MIN} / ${EKS_DEFAULT_MNG_MAX}"
echo "║  Desired nodes  : ${EKS_DEFAULT_MNG_DESIRED}"
echo "╠══════════════════════════════════════════════════════════════════════╣"
echo "║  OIDC / IRSA    : Enabled"
echo "║  Provider auth  : IRSA — no static credentials                      ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

read -r -p "Proceed with cluster creation? (y/n): " confirm
if [[ "${confirm}" != "y" ]]; then
    echo "Aborted. VPC remains deployed."
    echo "Run 'cdk destroy' in infra/ to remove it."
    exit 0
fi

echo ""
echo "── STEP 3: Generate eksctl cluster config ───────────────────────────────"
envsubst < "${FOUNDATION_ROOT}/cluster/cluster.yaml.template" > "${FOUNDATION_ROOT}/cluster/cluster.yaml"
echo "Written: cluster/cluster.yaml"

echo ""
echo "── STEP 4: Create EKS cluster with eksctl ───────────────────────────────"
eksctl create cluster -f "${FOUNDATION_ROOT}/cluster/cluster.yaml"

echo ""
echo "── STEP 5: Install Crossplane via Helm ──────────────────────────────────"
helm repo add crossplane-stable https://charts.crossplane.io/stable 2>/dev/null || \
    helm repo update crossplane-stable
helm install crossplane crossplane-stable/crossplane \
    --namespace crossplane-system \
    --create-namespace \
    --version "${CROSSPLANE_VERSION}" \
    --wait
echo "Crossplane ${CROSSPLANE_VERSION} installed."

echo ""
echo "── STEP 6: Create IAM role for Crossplane provider IRSA ─────────────────"
OIDC_ISSUER=$(aws eks describe-cluster \
    --name "${EKS_CLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --query "cluster.identity.oidc.issuer" \
    --output text | sed 's|https://||')

TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_ISSUER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringLike": {
          "${OIDC_ISSUER}:sub": "system:serviceaccount:crossplane-system:*"
        }
      }
    }
  ]
}
EOF
)

aws iam create-role \
    --role-name "${PROVIDER_IAM_ROLE}" \
    --assume-role-policy-document "${TRUST_POLICY}" \
    --description "Crossplane provider-aws IRSA role — crossplane-cookbook" \
    --region "${AWS_REGION}" \
    --output text --query 'Role.Arn'

aws iam attach-role-policy \
    --role-name "${PROVIDER_IAM_ROLE}" \
    --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess"

PROVIDER_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROVIDER_IAM_ROLE}"
echo "  IAM role: ${PROVIDER_ROLE_ARN}"

echo ""
echo "── STEP 7: Install provider-family-aws + DeploymentRuntimeConfig ─────────"
kubectl apply -f - <<EOF
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: upbound-provider-family-aws
spec:
  package: xpkg.crossplane.io/upbound/provider-family-aws:${PROVIDER_FAMILY_VERSION}
  runtimeConfigRef:
    name: aws-provider-irsa
EOF

kubectl apply -f - <<EOF
apiVersion: pkg.crossplane.io/v1beta1
kind: DeploymentRuntimeConfig
metadata:
  name: aws-provider-irsa
spec:
  serviceAccountTemplate:
    metadata:
      annotations:
        eks.amazonaws.com/role-arn: "${PROVIDER_ROLE_ARN}"
EOF

echo "Waiting for provider-family-aws to become healthy..."
kubectl wait provider/upbound-provider-family-aws \
    --for=condition=Healthy \
    --timeout=300s

echo ""
echo "── STEP 8: Apply ClusterProviderConfig (IRSA) ────────────────────────────"
kubectl apply -f - <<EOF
apiVersion: aws.m.upbound.io/v1beta1
kind: ClusterProviderConfig
metadata:
  name: default
spec:
  credentials:
    source: IRSA
EOF
echo "ClusterProviderConfig 'default' created with source: IRSA"

echo ""
echo "── STEP 9: Verify ───────────────────────────────────────────────────────"
echo ""
kubectl get nodes
echo ""
kubectl get providers
echo ""
echo "Foundation ready. Next steps:"
echo "  → Run a recipe: ./recipe-01/run.sh"
echo "  → Tear down:    ./foundations/eks-base/scripts/destroy-cluster.sh"
