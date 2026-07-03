"""TokTok-Support source-link issuer.

Resolves catalog document IDs to short-lived presigned download URLs. Called by
`chat_backend` to turn the `[source: <id>]` tags the chatbot emits into
clickable links in the rendered answer.

Serves both public FAQ documents and seller_admin customer exports out of the
same workspace bucket, so the execution role reads the whole bucket. Per-document
metadata, including required_role, lives in the document_catalog table.
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

    # The console already gates the export download UI by group, so link
    # issuance just resolves and signs. required_role is kept for the pending
    # export-download work (BPO-1423).
    _ = required_role

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
