"""TokTok-Support source-link issuer.

Resolves a list of catalog document IDs to short-lived presigned download
URLs. Used by `chat_backend` to convert `[source: <id>]` tags emitted by
the chatbot into clickable links shown in the rendered answer.

This is the integrated link issuer for both public FAQ documents and
seller_admin-only customer exports, which is why its IAM role intentionally
covers the entire workspace bucket. The intended boundary between "public"
documents and "seller_admin only" documents is the *code-level permission
re-check below*, which compares the caller's JWT cognito:groups claim to
the document's required_role attribute in document_catalog.

The re-check is currently NOT IMPLEMENTED. See the TODO inline.
"""

import json
import os

import boto3
from botocore.config import Config

dynamodb = boto3.resource("dynamodb")
s3 = boto3.client("s3", config=Config(signature_version="s3v4"))

CATALOG_TABLE = os.environ["CATALOG_TABLE"]
URL_TTL_SECONDS = int(os.environ.get("URL_TTL_SECONDS", "300"))

table = dynamodb.Table(CATALOG_TABLE)


def _resolve(doc_id, caller_groups):
    item = table.get_item(Key={"document_id": doc_id}).get("Item")
    if not item:
        return None

    s3_bucket = item["s3_bucket"]
    s3_key = item["s3_key"]
    required_role = item.get("required_role", "public")

    # ------------------------------------------------------------------
    # TODO(security): re-check caller permission before issuing the URL.
    # The intended check is roughly:
    #
    #     if required_role != "public" and required_role not in caller_groups:
    #         return None
    #
    # The team agreed to add this when the customer-export download flow
    # was wired up, but the change was deferred because the chatbot only
    # ever cites KB-indexed (public) document IDs in its answers, so a
    # missing re-check here was assumed to have no impact in practice.
    # ------------------------------------------------------------------
    _ = required_role  # currently unused

    url = s3.generate_presigned_url(
        ClientMethod="get_object",
        Params={"Bucket": s3_bucket, "Key": s3_key},
        ExpiresIn=URL_TTL_SECONDS,
    )
    return url


def lambda_handler(event, context):
    document_ids = event.get("document_ids") or []
    jwt = event.get("jwt") or {}
    caller_groups = jwt.get("groups") or []
    if isinstance(caller_groups, str):
        caller_groups = [g.strip() for g in caller_groups.split(",") if g.strip()]

    links = {}
    for doc_id in document_ids:
        url = _resolve(doc_id, caller_groups)
        if url:
            links[doc_id] = url

    return {"links": links}
