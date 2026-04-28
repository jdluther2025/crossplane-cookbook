# Foundation: eks-nim-ready

**Used by:** Recipe #20 (GPU Infrastructure with Crossplane: Provision NIM-Ready EKS)

**Based on:** [aiml-on-aws-eks-with-nim-operator](https://github.com/jdluther2025/aiml-on-aws-eks-with-nim-operator) (Blog #5)

## What this provides

The full Blog #5 stack provisioned declaratively by Crossplane Compositions:
- EKS Auto Mode cluster
- EFS file system (ReadWriteMany for NIMCache model weights)
- OpenSearch Serverless collection (RAG vector store)
- IAM roles (Pod Identity for chatbot, IRSA for provider-aws)
- NVIDIA NIM Operator

## Scripts

```bash
./foundations/eks-nim-ready/scripts/create-cluster.sh
./foundations/eks-nim-ready/scripts/destroy-cluster.sh
```

*Scripts will be populated when Recipe #20 is written.*
