"""TokTok-Support /chat backend.

Flow per request:
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
"""

import json
import os
import re
import uuid

import boto3

bedrock_agent_runtime = boto3.client("bedrock-agent-runtime")
lambda_client = boto3.client("lambda")

AGENT_ID = os.environ["AGENT_ID"]
AGENT_ALIAS_ID = os.environ["AGENT_ALIAS_ID"]
SOURCE_LINK_ISSUER_ARN = os.environ["SOURCE_LINK_ISSUER_ARN"]

SOURCE_TAG = re.compile(r"\[source:\s*([A-Za-z0-9_./\-]+)\s*\]")


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


def lambda_handler(event, context):
    if event.get("httpMethod") == "OPTIONS":
        return _resp(200, {})

    body = json.loads(event.get("body") or "{}")
    message = (body.get("message") or "").strip()
    session_id = body.get("sessionId") or str(uuid.uuid4())
    if not message:
        return _resp(400, {"error": "message is required"})

    # Extract the JWT that API Gateway already validated via the Cognito
    # authorizer. The `claims` object is forwarded by the authorizer.
    claims = (
        event.get("requestContext", {})
        .get("authorizer", {})
        .get("claims")
        or {}
    )
    jwt_groups = claims.get("cognito:groups") or ""
    jwt = {
        "sub": claims.get("sub"),
        "email": claims.get("email"),
        "groups": (
            [g.strip() for g in jwt_groups.split(",") if g.strip()]
            if isinstance(jwt_groups, str)
            else jwt_groups
        ),
    }

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
