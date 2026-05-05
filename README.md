# ☁️ Crossplane Cookbook

A hands-on recipe series for building cloud-native infrastructure with Crossplane on Amazon EKS.

**Publication:** [AI & ML: Human Training & Coaching](https://medium.com/ai-ml-human-training-coaching)

---

## 🍳 Recipes

| Recipe | Title | Blog |
|--------|-------|------|
| Recipe #1 | A Crossplane Ready EKS Cluster to Build Cloud Native Infra | [Read on Medium](https://medium.com/ai-ml-human-training-coaching/crossplane-cookbook-recipe-1-a-crossplane-ready-amazon-eks-cluster-to-build-cloud-native-infra-e331163c1066) |

---

## 🏗️ Foundations

Reusable EKS cluster foundations — spin up once, run any recipe, tear down cleanly.

| Foundation | Description |
|------------|-------------|
| `eks-base` | Crossplane-enabled EKS cluster — Crossplane 2.2, IRSA auth, ClusterProviderConfig |
| `eks-with-argocd` | Coming soon |
| `eks-nim-ready` | Coming soon |

---

## 🚀 Quick Start

```bash
git clone https://github.com/jdluther2025/crossplane-cookbook.git
cd crossplane-cookbook

# Build the foundation
./foundations/eks-base/scripts/create-cluster.sh

# Run a recipe
./recipe-01/run.sh

# Clean up recipe resources
./recipe-01/cleanup.sh

# Tear down the foundation
./foundations/eks-base/scripts/destroy-cluster.sh
```

---

## 🔧 Prerequisites

- AWS CLI — configured with credentials that can create EKS clusters and IAM roles
- AWS CDK — `npm install -g aws-cdk`
- eksctl — `brew install eksctl`
- kubectl — `brew install kubectl`
- Helm — `brew install helm`

---

*JD Luther — 8x AWS Certified, CKAD, Terraform Professional*
