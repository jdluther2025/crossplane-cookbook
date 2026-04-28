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
CROSSPLANE_VERSION="${CROSSPLANE_VERSION:-2.2.0}"
PROVIDER_FAMILY_VERSION="${PROVIDER_FAMILY_VERSION:-v2.0.0}"
PROVIDER_IAM_ROLE="crossplane-provider-aws"

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
echo "║            Crossplane Cookbook — Foundation Summary                  ║"
echo "╠══════════════════════════════════════════════════════════════════════╣"
printf "║  Cluster name   : %-50s║\n" "${EKS_CLUSTER_NAME}"
printf "║  AWS account    : %-50s║\n" "${AWS_ACCOUNT_ID}"
printf "║  Region         : %-50s║\n" "${AWS_REGION}"
printf "║  Kubernetes     : %-50s║\n" "${K8S_VERSION}"
printf "║  Crossplane     : %-50s║\n" "${CROSSPLANE_VERSION}"
echo "╠══════════════════════════════════════════════════════════════════════╣"
printf "║  VPC            : %-50s║\n" "${VPC_ID}"
printf "║  Private subnet : %-50s║\n" "${PRIVATE_SUBNET_1} (${AZ_1})"
printf "║  Private subnet : %-50s║\n" "${PRIVATE_SUBNET_2} (${AZ_2})"
printf "║  Public subnet  : %-50s║\n" "${PUBLIC_SUBNET_1} (${AZ_1})"
printf "║  Public subnet  : %-50s║\n" "${PUBLIC_SUBNET_2} (${AZ_2})"
echo "╠══════════════════════════════════════════════════════════════════════╣"
printf "║  Node group     : %-50s║\n" "t3.medium x2 (managed)"
printf "║  OIDC           : %-50s║\n" "enabled (required for IRSA)"
printf "║  Provider auth  : %-50s║\n" "IRSA — no static credentials"
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
# provider-family-aws creates the shared ServiceAccount that all sub-providers use.
# DeploymentRuntimeConfig annotates that SA with the IRSA role ARN.

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
apiVersion: aws.upbound.io/v1beta1
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
echo "  → Run a recipe: cd recipe-01 && ./run.sh"
echo "  → Tear down:    ./foundations/eks-base/scripts/destroy-cluster.sh"
