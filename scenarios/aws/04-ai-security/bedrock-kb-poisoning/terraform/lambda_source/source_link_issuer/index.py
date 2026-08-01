"""Internal catalog and source-link service.

The same Lambda resolves FAQ and seller_admin-only files. Direct downloads set
enforce_acl=True and re-check the caller group. Citation links from the chat
path intentionally omit that final check, preserving the scenario flaw.
"""

import os

import boto3
from botocore.config import Config


dynamodb = boto3.resource("dynamodb")
s3 = boto3.client("s3", config=Config(signature_version="s3v4"))

CATALOG_TABLE = os.environ["CATALOG_TABLE"]
URL_TTL_SECONDS = int(os.environ.get("URL_TTL_SECONDS", "300"))
table = dynamodb.Table(CATALOG_TABLE)


def _caller_can_access(required_role, caller_groups):
    return required_role == "public" or required_role in set(caller_groups or [])


def _resolve(document_id, caller_groups, enforce_acl):
    item = table.get_item(Key={"document_id": document_id}).get("Item")
    if not item:
        return None

    required_role = item.get("required_role", "public")
    if enforce_acl and not _caller_can_access(required_role, caller_groups):
        return None

    return s3.generate_presigned_url(
        ClientMethod="get_object",
        Params={"Bucket": item["s3_bucket"], "Key": item["s3_key"]},
        ExpiresIn=URL_TTL_SECONDS,
    )


def _scan_all():
    items = []
    response = table.scan()
    items.extend(response.get("Items") or [])
    while response.get("LastEvaluatedKey"):
        response = table.scan(ExclusiveStartKey=response["LastEvaluatedKey"])
        items.extend(response.get("Items") or [])
    return items


def _list_files():
    safe_fields = (
        "document_id",
        "title",
        "content_type",
        "required_role",
        "created_at",
        "row_count",
        "display_size",
    )
    files = [
        {
            field: item[field]
            for field in safe_fields
            if field in item
        }
        for item in _scan_all()
    ]
    return sorted(
        files,
        key=lambda item: (
            item.get("required_role", "public") == "public",
            item.get("title") or "",
        ),
    )


def lambda_handler(event, context):
    operation = event.get("operation") or "resolve"
    if operation == "list":
        return {"files": _list_files()}

    document_ids = event.get("document_ids") or []
    jwt = event.get("jwt") or {}
    caller_groups = jwt.get("groups") or []
    if isinstance(caller_groups, str):
        caller_groups = [
            group.strip() for group in caller_groups.split(",") if group.strip()
        ]
    enforce_acl = bool(event.get("enforce_acl"))

    links = {}
    for document_id in document_ids:
        url = _resolve(document_id, caller_groups, enforce_acl)
        if url:
            links[document_id] = url
    return {"links": links}
