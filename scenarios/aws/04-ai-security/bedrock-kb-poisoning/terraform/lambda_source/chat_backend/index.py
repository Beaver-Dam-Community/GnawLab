"""TokTok-Support API backend.

Flow for /api/chat:
  1. Receive a JSON body {message, sessionId} with the caller's Cognito JWT
     already verified by API Gateway's Cognito authorizer.
  2. Call Bedrock Agent InvokeAgent. Aggregate the streaming response into a
     single output_text string and collect retrievedReferences from chunk
     attribution.
  3. Parse `[source: <document_id>]` inline tags from output_text. Union the
     IDs found in tags with the IDs found in retrievedReferences.
  4. Invoke source_link_issuer with (document_ids, jwt). Receive a
     {document_id: temporary_url} mapping back.
  5. Substitute every `[source: <id>]` tag in output_text with a Markdown
     link to the temporary URL. Return {raw, rendered, citations} so the
     console QA / preview screen can show both panes side by side.

The console QA screen relies on the response containing `raw` (with original
source tags) and `rendered` (with substituted URLs).

Flow for /api/docs:
  1. Accept a FAQ document edit from bpo_editor or seller_admin.
  2. Write the Markdown back to S3 under public/faq/.
  3. Start a Bedrock Knowledge Base ingestion job.
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

SOURCE_TAG = re.compile(r"\[source:\s*([A-Za-z0-9_./\-]+)\s*\]")
catalog_table = dynamodb.Table(CATALOG_TABLE)


def _cors():
    return {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "Content-Type,Authorization",
        "Access-Control-Allow-Methods": "OPTIONS,POST",
    }


def _resp(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json", **_cors()},
        "body": json.dumps(body),
    }


def _invoke_agent(message, session_id):
    response = bedrock_agent_runtime.invoke_agent(
        agentId=AGENT_ID,
        agentAliasId=AGENT_ALIAS_ID,
        sessionId=session_id,
        inputText=message,
        enableTrace=False,
    )

    output_text = ""
    retrieved_doc_ids = []

    for event in response.get("completion", []):
        chunk = event.get("chunk")
        if not chunk:
            continue
        output_text += chunk.get("bytes", b"").decode("utf-8", errors="replace")

        attribution = chunk.get("attribution") or {}
        for citation in attribution.get("citations", []) or []:
            for ref in citation.get("retrievedReferences", []) or []:
                location = ref.get("location") or {}
                s3 = location.get("s3Location") or {}
                uri = s3.get("uri") or ""
                # Convert "s3://bucket/public/faq/refund-policy-v3.md" to
                # the catalog ID "faq/refund-policy-v3".
                if uri.startswith("s3://"):
                    key = uri.split("/", 3)[3]
                    if key.startswith("public/"):
                        without_prefix = key[len("public/") :]
                        doc_id = without_prefix.rsplit(".", 1)[0]
                        retrieved_doc_ids.append(doc_id)

    return output_text, retrieved_doc_ids


def _parse_inline_doc_ids(text):
    return SOURCE_TAG.findall(text or "")


def _jwt_from_event(event):
    claims = (
        event.get("requestContext", {})
        .get("authorizer", {})
        .get("claims")
        or {}
    )
    jwt_groups = claims.get("cognito:groups") or ""
    return {
        "sub": claims.get("sub"),
        "email": claims.get("email"),
        "groups": (
            [g.strip() for g in jwt_groups.split(",") if g.strip()]
            if isinstance(jwt_groups, str)
            else jwt_groups
        ),
    }


def _resolve_links(doc_ids, jwt):
    """Invoke source_link_issuer Lambda synchronously."""
    if not doc_ids:
        return {}

    payload = {"document_ids": doc_ids, "jwt": jwt}
    resp = lambda_client.invoke(
        FunctionName=SOURCE_LINK_ISSUER_ARN,
        InvocationType="RequestResponse",
        Payload=json.dumps(payload).encode("utf-8"),
    )
    body = json.loads(resp["Payload"].read())
    return body.get("links", {})


def _render(output_text, links):
    def _sub(match):
        doc_id = match.group(1)
        url = links.get(doc_id)
        if not url:
            return match.group(0)
        return f"[source]({url})"

    return SOURCE_TAG.sub(_sub, output_text)


def _save_doc(event, jwt):
    groups = jwt.get("groups") or []
    if "bpo_editor" not in groups and "seller_admin" not in groups:
        return _resp(403, {"error": "forbidden"})

    body = json.loads(event.get("body") or "{}")
    doc_id = (body.get("document_id") or "").strip()
    content = body.get("content")
    if not doc_id or not isinstance(content, str):
        return _resp(400, {"error": "document_id and content are required"})

    item = catalog_table.get_item(Key={"document_id": doc_id}).get("Item")
    if not item:
        return _resp(404, {"error": "unknown_doc"})

    key = item.get("s3_key") or ""
    if not key.startswith("public/faq/"):
        return _resp(403, {"error": "faq_docs_only"})

    s3_client.put_object(
        Bucket=WORKSPACE_BUCKET,
        Key=key,
        Body=content.encode("utf-8"),
        ContentType="text/markdown; charset=utf-8",
    )
    status = "sync_started"
    ingestion_job_id = None
    try:
        job = bedrock_agent.start_ingestion_job(
            knowledgeBaseId=KB_ID,
            dataSourceId=DATA_SOURCE_ID,
            description=f"FAQ save: {doc_id}",
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
            "document_id": doc_id,
            "ingestion_job_id": ingestion_job_id,
        },
    )


def lambda_handler(event, context):
    if event.get("httpMethod") == "OPTIONS":
        return _resp(200, {})

    jwt = _jwt_from_event(event)
    if (event.get("path") or "").endswith("/docs"):
        return _save_doc(event, jwt)

    body = json.loads(event.get("body") or "{}")
    message = (body.get("message") or "").strip()
    session_id = body.get("sessionId") or str(uuid.uuid4())
    if not message:
        return _resp(400, {"error": "message is required"})

    raw_text, retrieved_ids = _invoke_agent(message, session_id)
    inline_ids = _parse_inline_doc_ids(raw_text)
    union_ids = list(dict.fromkeys(retrieved_ids + inline_ids))

    links = _resolve_links(union_ids, jwt)
    rendered = _render(raw_text, links)

    return _resp(
        200,
        {
            "sessionId": session_id,
            "raw": raw_text,
            "rendered": rendered,
            "citations": [
                {"document_id": doc_id, "url": links.get(doc_id)}
                for doc_id in union_ids
            ],
        },
    )
