# Recipe #1 — Install Crossplane on EKS + Create Your First S3 Bucket

**Foundation required:** `eks-base`

```bash
./foundations/eks-base/scripts/create-cluster.sh
```

## What this recipe does

1. Installs `upbound/provider-aws-s3` on the running Crossplane cluster
2. Creates a `Bucket` Managed Resource — one YAML file, one S3 bucket in AWS
3. Verifies the bucket exists in AWS via CLI and Console URL
4. Demonstrates delete propagation: `kubectl delete bucket` → S3 bucket gone from AWS

## Run it

```bash
./recipe-01/run.sh
```

Override the bucket name:

```bash
BUCKET_NAME=my-custom-bucket ./recipe-01/run.sh
```

## Files

| File | Purpose |
|------|---------|
| `provider-s3.yaml` | Install `upbound/provider-aws-s3` |
| `bucket.yaml` | S3 Bucket Managed Resource (template — envsubst fills `BUCKET_NAME` and `AWS_REGION`) |
| `run.sh` | Full recipe: install provider → create bucket → verify → delete demo |

## The aha moment

```bash
kubectl delete bucket xp-cookbook-12345678-r01
```

The S3 bucket disappears from AWS. No `terraform destroy`. No `aws s3 rm`. Kubernetes
reconciliation drives the cloud API — that's the Crossplane model.
