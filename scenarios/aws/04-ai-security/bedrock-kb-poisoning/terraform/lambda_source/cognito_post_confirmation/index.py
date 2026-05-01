"""Cognito Post-Confirmation hook.

Auto-attaches new users to a Cognito group based on their email domain.
This implements the seller's "BPO partner self-onboarding" feature — once
an account is confirmed (which the pre-signup hook already auto-does for
trusted domains), this hook puts BPO emails into bpo_editor and seller
staff into seller_admin so they can immediately use the workspace.
"""

import os
import boto3

idp = boto3.client("cognito-idp")

BPO_DOMAIN = os.environ["BPO_DOMAIN"].lower()
SELLER_DOMAIN = os.environ["SELLER_DOMAIN"].lower()


def lambda_handler(event, context):
    email = (event.get("request", {}).get("userAttributes", {}).get("email") or "").lower()
    domain = email.split("@")[-1] if "@" in email else ""

    if domain == BPO_DOMAIN:
        group = "bpo_editor"
    elif domain == SELLER_DOMAIN:
        group = "seller_admin"
    else:
        return event

    idp.admin_add_user_to_group(
        UserPoolId=event["userPoolId"],
        Username=event["userName"],
        GroupName=group,
    )

    return event
