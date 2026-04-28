#!/usr/bin/env python3
import os
import aws_cdk as cdk
from eks_base.eks_base_stack import EksBaseStack

app = cdk.App()

EksBaseStack(app, "EksBaseStack",
    env=cdk.Environment(
        account=os.getenv("CDK_DEFAULT_ACCOUNT"),
        region=os.getenv("CDK_DEFAULT_REGION"),
    ),
)

app.synth()
