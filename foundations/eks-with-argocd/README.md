# Foundation: eks-with-argocd

**Used by:** Recipe #16 (GitOps with Crossplane + ArgoCD)

**Extends:** `eks-base` — run `eks-base` first, then this foundation adds ArgoCD with Crossplane-specific configuration.

## What this adds on top of eks-base

- ArgoCD installed via Helm
- `argocd-cm` configured for Crossplane compatibility:
  - `application.resourceTrackingMethod: annotation`
  - Custom Lua health checks for `*.crossplane.io/*` and `*.upbound.io/*`
  - `ProviderConfigUsage` excluded from UI
  - `ARGOCD_K8S_CLIENT_QPS: 300`

## Scripts

```bash
# First: bring up eks-base
./foundations/eks-base/scripts/create-cluster.sh

# Then: add ArgoCD
./foundations/eks-with-argocd/scripts/install-argocd.sh

# Teardown ArgoCD (eks-base teardown handles the cluster)
./foundations/eks-with-argocd/scripts/uninstall-argocd.sh
```

*Scripts will be populated when Recipe #16 is written.*
