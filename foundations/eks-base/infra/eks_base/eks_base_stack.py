from aws_cdk import (
    Stack,
    CfnOutput,
    Tags,
    aws_ec2 as ec2,
)
from constructs import Construct

CLUSTER_NAME = "crossplane-cookbook"


class EksBaseStack(Stack):

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # ── VPC ────────────────────────────────────────────────────────────────
        # 2 AZs, 1 NAT gateway (cost optimization for tutorial use).
        # Private subnets: EKS nodes.
        # Public subnets: load balancers.

        vpc = ec2.Vpc(self, "EksBaseVpc",
            max_azs=2,
            nat_gateways=1,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="Public",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24,
                ),
                ec2.SubnetConfiguration(
                    name="Private",
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    cidr_mask=24,
                ),
            ],
        )

        for subnet in vpc.public_subnets:
            Tags.of(subnet).add(f"kubernetes.io/cluster/{CLUSTER_NAME}", "shared")
            Tags.of(subnet).add("kubernetes.io/role/elb", "1")

        for subnet in vpc.private_subnets:
            Tags.of(subnet).add(f"kubernetes.io/cluster/{CLUSTER_NAME}", "shared")
            Tags.of(subnet).add("kubernetes.io/role/internal-elb", "1")

        # ── Outputs (read by scripts/create-cluster.sh) ────────────────────────

        CfnOutput(self, "ClusterName",
            value=CLUSTER_NAME,
            export_name="EksBaseClusterName",
        )

        CfnOutput(self, "VpcId",
            value=vpc.vpc_id,
            export_name="EksBaseVpcId",
        )

        CfnOutput(self, "PrivateSubnetIds",
            value=",".join([s.subnet_id for s in vpc.private_subnets]),
            export_name="EksBasePrivateSubnetIds",
        )

        CfnOutput(self, "PublicSubnetIds",
            value=",".join([s.subnet_id for s in vpc.public_subnets]),
            export_name="EksBasePublicSubnetIds",
        )
