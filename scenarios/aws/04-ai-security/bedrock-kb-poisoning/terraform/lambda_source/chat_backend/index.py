"""TokTok-Support authenticated API backend.

Public API routes:
  POST /api/chat      Ask the Bedrock Agent and render source links.
  POST /api/docs      Save an allowed FAQ document and start KB ingestion.
  GET  /api/files     List safe catalog metadata, including protected files.
  POST /api/download  Enforce the caller group before issuing a URL.

The intentionally vulnerable path is different. /api/chat validates that a
model-emitted catalog ID literally occurs in a retrieved FAQ chunk, then calls
the internal source-link issuer without requesting a final user ACL check. A
poisoned FAQ can therefore make the validation pass while selecting an
admin-only catalog entry.
"""

import json
import os
import re
import uuid

import boto3
from botocore.exceptions import ClientError


bedrock_agent_runtime = boto3.client("bedrock-agent-runtime")
bedrock_agent = boto3.client("bedrock-agent")
lambda_client = boto3.client("lambda")
s3_client = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")

AGENT_ID = os.environ["AGENT_ID"]
AGENT_ALIAS_ID = os.environ["AGENT_ALIAS_ID"]
SOURCE_LINK_ISSUER_ARN = os.environ["SOURCE_LINK_ISSUER_ARN"]
CATALOG_TABLE = os.environ["CATALOG_TABLE"]
WORKSPACE_BUCKET = os.environ["WORKSPACE_BUCKET"]
KB_ID = os.environ["KB_ID"]
DATA_SOURCE_ID = os.environ["DATA_SOURCE_ID"]
S3_KEY_TO_CATALOG_ID = json.loads(os.environ.get("S3_KEY_TO_CATALOG_ID", "{}"))

SOURCE_TAG = re.compile(r"\[source:\s*([A-Za-z0-9_.\-/]+)\s*\]")
catalog_table = dynamodb.Table(CATALOG_TABLE)


def _cors():
    return {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "Content-Type,Authorization",
        "Access-Control-Allow-Methods": "OPTIONS,GET,POST",
    }


def _resp(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json", **_cors()},
        "body": json.dumps(body),
    }


def _request_body(event):
    raw = event.get("body") or "{}"
    return json.loads(raw) if isinstance(raw, str) else raw


def _route_name(event):
    path = event.get("resource") or event.get("path") or ""
    return path.rstrip("/").rsplit("/", 1)[-1]


def _jwt_from_event(event):
    claims = (
        event.get("requestContext", {})
        .get("authorizer", {})
        .get("claims")
        or {}
    )
    raw_groups = claims.get("cognito:groups") or ""
    groups = (
        [group.strip() for group in raw_groups.split(",") if group.strip()]
        if isinstance(raw_groups, str)
        else list(raw_groups)
    )
    return {
        "sub": claims.get("sub"),
        "email": claims.get("email"),
        "groups": groups,
    }


def _catalog_id_from_s3_uri(uri):
    if not uri.startswith("s3://"):
        return None
    bucket_and_key = uri[5:].split("/", 1)
    if len(bucket_and_key) != 2:
        return None
    return S3_KEY_TO_CATALOG_ID.get(bucket_and_key[1])


def _invoke_agent(message, session_id):
    response = bedrock_agent_runtime.invoke_agent(
        agentId=AGENT_ID,
        agentAliasId=AGENT_ALIAS_ID,
        sessionId=session_id,
        inputText=message,
        enableTrace=False,
    )

    output_text = ""
    retrieved_catalog_ids = []
    retrieved_chunks = []

    for event in response.get("completion", []):
        chunk = event.get("chunk")
        if not chunk:
            continue
        output_text += chunk.get("bytes", b"").decode("utf-8", errors="replace")

        attribution = chunk.get("attribution") or {}
        for citation in attribution.get("citations", []) or []:
            for reference in citation.get("retrievedReferences", []) or []:
                content = reference.get("content") or {}
                text = content.get("text") or ""
                if text:
                    retrieved_chunks.append(text)

                location = reference.get("location") or {}
                s3_location = location.get("s3Location") or {}
                catalog_id = _catalog_id_from_s3_uri(s3_location.get("uri") or "")
                if catalog_id:
                    retrieved_catalog_ids.append(catalog_id)

    return (
        output_text,
        list(dict.fromkeys(retrieved_catalog_ids)),
        list(dict.fromkeys(retrieved_chunks)),
    )


def _parse_inline_catalog_ids(text):
    return SOURCE_TAG.findall(text or "")


def _cross_check_inline_ids(inline_ids, retrieved_chunks):
    """Keep only IDs that literally occur in a retrieved FAQ chunk."""
    checked = []
    for catalog_id in inline_ids:
        token = re.compile(
            rf"(?<![A-Za-z0-9_.\-/]){re.escape(catalog_id)}(?![A-Za-z0-9_.\-/])"
        )
        if any(token.search(chunk) for chunk in retrieved_chunks):
            checked.append(catalog_id)
    return list(dict.fromkeys(checked))


def _invoke_source_link_issuer(payload):
    response = lambda_client.invoke(
        FunctionName=SOURCE_LINK_ISSUER_ARN,
        InvocationType="RequestResponse",
        Payload=json.dumps(payload).encode("utf-8"),
    )
    body = json.loads(response["Payload"].read())
    if response.get("FunctionError"):
        raise RuntimeError(body.get("errorMessage") or "source-link issuer failed")
    return body


def _resolve_links(catalog_ids, jwt, enforce_acl=False):
    if not catalog_ids:
        return {}
    body = _invoke_source_link_issuer(
        {
            "operation": "resolve",
            "document_ids": catalog_ids,
            "jwt": jwt,
            "enforce_acl": enforce_acl,
        }
    )
    return body.get("links", {})


def _render(output_text, links):
    def _sub(match):
        catalog_id = match.group(1)
        url = links.get(catalog_id)
        return f"[source: {catalog_id}]({url})" if url else match.group(0)

    rendered = SOURCE_TAG.sub(_sub, output_text)
    tagged_ids = set(_parse_inline_catalog_ids(output_text))
    extra_links = [
        f"- [source: {catalog_id}]({url})"
        for catalog_id, url in links.items()
        if catalog_id not in tagged_ids
    ]
    if extra_links:
        rendered = rendered.rstrip() + "\n\nSources\n" + "\n".join(extra_links)
    return rendered


def _save_doc(event, jwt):
    groups = jwt.get("groups") or []
    if "bpo_editor" not in groups and "seller_admin" not in groups:
        return _resp(403, {"error": "FAQ edit permission required"})

    body = _request_body(event)
    catalog_id = (body.get("document_id") or "").strip()
    content = body.get("content")
    if not catalog_id or not isinstance(content, str):
        return _resp(400, {"error": "document_id and content are required"})

    item = catalog_table.get_item(Key={"document_id": catalog_id}).get("Item")
    if not item:
        return _resp(404, {"error": "document not found"})

    s3_key = item.get("s3_key") or ""
    if item.get("required_role") != "public" or not s3_key.startswith("public/faq/"):
        return _resp(403, {"error": "only public FAQ documents are editable"})

    s3_client.put_object(
        Bucket=WORKSPACE_BUCKET,
        Key=s3_key,
        Body=content.encode("utf-8"),
        ContentType=item.get("content_type") or "text/markdown; charset=utf-8",
    )

    status = "sync_started"
    ingestion_job_id = None
    try:
        job = bedrock_agent.start_ingestion_job(
            knowledgeBaseId=KB_ID,
            dataSourceId=DATA_SOURCE_ID,
            description=f"FAQ save: {catalog_id}",
        )
        ingestion_job_id = job.get("ingestionJob", {}).get("ingestionJobId")
    except ClientError as exc:
        if exc.response.get("Error", {}).get("Code") != "ConflictException":
            raise
        status = "sync_already_running"

    return _resp(
        200,
        {
            "status": status,
            "document_id": catalog_id,
            "ingestion_job_id": ingestion_job_id,
        },
    )


def _handle_chat(event, jwt):
    body = _request_body(event)
    message = (body.get("message") or "").strip()
    session_id = body.get("sessionId") or str(uuid.uuid4())
    if not message:
        return _resp(400, {"error": "message is required"})

    raw_text, retrieved_ids, retrieved_chunks = _invoke_agent(message, session_id)
    inline_ids = _parse_inline_catalog_ids(raw_text)
    checked_inline_ids = _cross_check_inline_ids(inline_ids, retrieved_chunks)
    catalog_ids = list(dict.fromkeys(retrieved_ids + checked_inline_ids))

    # Intentionally vulnerable: the source-link path trusts the checked model
    # selection but does not request a final caller ACL check.
    links = _resolve_links(catalog_ids, jwt, enforce_acl=False)
    rendered = _render(raw_text, links)

    return _resp(
        200,
        {
            "sessionId": session_id,
            "raw": raw_text,
            "rendered": rendered,
            "citations": [
                {"document_id": catalog_id, "url": links.get(catalog_id)}
                for catalog_id in catalog_ids
            ],
            "validation": {
                "inline_ids": inline_ids,
                "accepted_inline_ids": checked_inline_ids,
            },
        },
    )


def _handle_files():
    files = _invoke_source_link_issuer({"operation": "list"}).get("files", [])
    return _resp(200, {"files": files})


def _handle_download(event, jwt):
    body = _request_body(event)
    catalog_id = (body.get("document_id") or "").strip()
    if not catalog_id:
        return _resp(400, {"error": "document_id is required"})

    links = _resolve_links([catalog_id], jwt, enforce_acl=True)
    url = links.get(catalog_id)
    if not url:
        return _resp(
            403,
            {
                "error": "forbidden",
                "reason": "caller group does not satisfy file access policy",
            },
        )
    return _resp(200, {"document_id": catalog_id, "url": url})


def lambda_handler(event, context):
    method = (event.get("httpMethod") or "POST").upper()
    if method == "OPTIONS":
        return _resp(200, {})

    route = _route_name(event)
    jwt = _jwt_from_event(event)
    if route == "chat" and method == "POST":
        return _handle_chat(event, jwt)
    if route == "docs" and method == "POST":
        return _save_doc(event, jwt)
    if route == "files" and method == "GET":
        return _handle_files()
    if route == "download" and method == "POST":
        return _handle_download(event, jwt)
    return _resp(404, {"error": "route not found"})
