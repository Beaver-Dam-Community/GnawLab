"""Cognito Pre-Signup hook.

Auto-confirms accounts whose email is on a trusted partner domain (the BPO
partner or the seller's own staff). This is a deliberate convenience the
operations team enables so that BPO onboarding does not require a TokTok
admin to manually approve every new BPO CS hire.
"""

import os

ALLOWED_DOMAINS = {
    os.environ["BPO_DOMAIN"].lower(),
    os.environ["SELLER_DOMAIN"].lower(),
}


def lambda_handler(event, context):
    email = (event.get("request", {}).get("userAttributes", {}).get("email") or "").lower()
    domain = email.split("@")[-1] if "@" in email else ""

    if domain in ALLOWED_DOMAINS:
        event["response"]["autoConfirmUser"] = True
        event["response"]["autoVerifyEmail"] = True

    return event
