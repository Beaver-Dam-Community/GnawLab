"""Local contract tests for the Bedrock KB Poisoning scenario.

These tests use small in-memory AWS doubles. They verify the authorization
contrast without creating or modifying AWS resources.
"""

import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import types
import unittest


SCENARIO_ROOT = Path(__file__).resolve().parents[1]
CHAT_PATH = SCENARIO_ROOT / "terraform/lambda_source/chat_backend/index.py"
ISSUER_PATH = SCENARIO_ROOT / "terraform/lambda_source/source_link_issuer/index.py"


CATALOG_ITEMS = {
    "cat_4b17e2": {
        "document_id": "cat_4b17e2",
        "s3_bucket": "workspace-bucket",
        "s3_key": "public/faq/refund-policy-v3.md",
        "title": "Refund Policy v3.0",
        "content_type": "text/markdown",
        "required_role": "public",
    },
    "cat_9c2a41": {
        "document_id": "cat_9c2a41",
        "s3_bucket": "workspace-bucket",
        "s3_key": "admin-only/customers/customer-export-2026-04.csv",
        "title": "VIP customer export - 2026-04",
        "content_type": "text/csv",
        "required_role": "seller_admin",
        "created_at": "2026-04-30",
        "row_count": "50",
        "display_size": "12.4 KB",
    },
}


class FakeTable:
    def __init__(self, items):
        self.items = items

    def get_item(self, Key):
        item = self.items.get(Key["document_id"])
        return {"Item": dict(item)} if item else {}

    def scan(self, **kwargs):
        return {"Items": [dict(item) for item in self.items.values()]}


class FakeDynamoResource:
    def __init__(self, table):
        self.table = table

    def Table(self, name):
        return self.table


class FakeS3:
    def generate_presigned_url(self, ClientMethod, Params, ExpiresIn):
        return (
            "https://signed.example/"
            + Params["Key"]
            + f"?method={ClientMethod}&ttl={ExpiresIn}"
        )

    def put_object(self, **kwargs):
        return {"ETag": "fake"}


class FakeLambdaClient:
    def invoke(self, **kwargs):
        return {"Payload": io.BytesIO(b'{"links": {}}')}


class FakeBedrockAgent:
    def start_ingestion_job(self, **kwargs):
        return {"ingestionJob": {"ingestionJobId": "job-1"}}


class FakeBedrockRuntime:
    def invoke_agent(self, **kwargs):
        return {"completion": []}


class FakeClientError(Exception):
    def __init__(self, response=None, operation_name=None):
        super().__init__(str(response or {}))
        self.response = response or {}
        self.operation_name = operation_name


def install_aws_doubles():
    table = FakeTable(CATALOG_ITEMS)
    clients = {
        "s3": FakeS3(),
        "lambda": FakeLambdaClient(),
        "bedrock-agent": FakeBedrockAgent(),
        "bedrock-agent-runtime": FakeBedrockRuntime(),
    }

    boto3 = types.ModuleType("boto3")
    boto3.client = lambda name, **kwargs: clients[name]
    boto3.resource = lambda name, **kwargs: FakeDynamoResource(table)

    botocore = types.ModuleType("botocore")
    botocore_config = types.ModuleType("botocore.config")
    botocore_config.Config = lambda **kwargs: kwargs
    botocore_exceptions = types.ModuleType("botocore.exceptions")
    botocore_exceptions.ClientError = FakeClientError

    sys.modules["boto3"] = boto3
    sys.modules["botocore"] = botocore
    sys.modules["botocore.config"] = botocore_config
    sys.modules["botocore.exceptions"] = botocore_exceptions
    return table


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


class ScenarioContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        install_aws_doubles()
        os.environ.update(
            {
                "AGENT_ID": "agent",
                "AGENT_ALIAS_ID": "alias",
                "SOURCE_LINK_ISSUER_ARN": "issuer",
                "CATALOG_TABLE": "catalog",
                "WORKSPACE_BUCKET": "workspace-bucket",
                "KB_ID": "kb",
                "DATA_SOURCE_ID": "ds",
                "S3_KEY_TO_CATALOG_ID": json.dumps(
                    {
                        "public/faq/refund-policy-v3.md": "cat_4b17e2",
                    }
                ),
            }
        )
        cls.issuer = load_module("scenario_source_link_issuer", ISSUER_PATH)
        cls.chat = load_module("scenario_chat_backend", CHAT_PATH)

    def test_catalog_listing_hides_s3_location(self):
        files = self.issuer.lambda_handler({"operation": "list"}, None)["files"]
        protected = next(item for item in files if item["document_id"] == "cat_9c2a41")
        self.assertEqual(protected["required_role"], "seller_admin")
        self.assertEqual(protected["created_at"], "2026-04-30")
        self.assertNotIn("s3_key", protected)
        self.assertNotIn("s3_bucket", protected)

    def test_direct_download_denies_bpo_but_allows_seller_admin(self):
        denied = self.issuer.lambda_handler(
            {
                "document_ids": ["cat_9c2a41"],
                "jwt": {"groups": ["bpo_editor"]},
                "enforce_acl": True,
            },
            None,
        )
        allowed = self.issuer.lambda_handler(
            {
                "document_ids": ["cat_9c2a41"],
                "jwt": {"groups": ["seller_admin"]},
                "enforce_acl": True,
            },
            None,
        )
        self.assertEqual(denied["links"], {})
        self.assertIn("cat_9c2a41", allowed["links"])

    def test_citation_path_can_sign_same_admin_object_without_final_acl(self):
        result = self.issuer.lambda_handler(
            {
                "document_ids": ["cat_9c2a41"],
                "jwt": {"groups": ["bpo_editor"]},
                "enforce_acl": False,
            },
            None,
        )
        self.assertIn("cat_9c2a41", result["links"])

    def test_inline_id_must_exist_in_retrieved_faq_text(self):
        accepted = self.chat._cross_check_inline_ids(
            ["cat_9c2a41", "cat_deadbe"],
            ["Related customer tier material: cat_9c2a41"],
        )
        self.assertEqual(accepted, ["cat_9c2a41"])

    def test_chat_path_uses_cross_checked_id_without_acl_enforcement(self):
        calls = []
        original_invoke_agent = self.chat._invoke_agent
        original_resolve_links = self.chat._resolve_links
        try:
            self.chat._invoke_agent = lambda message, session: (
                "See the related file [source: cat_9c2a41]",
                ["cat_4b17e2"],
                ["VIP tier source catalog ID: cat_9c2a41"],
            )

            def fake_resolve(ids, jwt, enforce_acl=False):
                calls.append((list(ids), dict(jwt), enforce_acl))
                return {catalog_id: f"https://signed/{catalog_id}" for catalog_id in ids}

            self.chat._resolve_links = fake_resolve
            response = self.chat._handle_chat(
                {"body": json.dumps({"message": "VIP refund?", "sessionId": "s1"})},
                {"groups": ["bpo_editor"]},
            )
        finally:
            self.chat._invoke_agent = original_invoke_agent
            self.chat._resolve_links = original_resolve_links

        payload = json.loads(response["body"])
        self.assertEqual(response["statusCode"], 200)
        self.assertIn("cat_9c2a41", payload["validation"]["accepted_inline_ids"])
        self.assertEqual(calls[0][2], False)
        self.assertEqual(calls[0][0], ["cat_4b17e2", "cat_9c2a41"])

    def test_download_api_requests_final_acl_enforcement(self):
        calls = []
        original_resolve_links = self.chat._resolve_links
        try:
            def fake_resolve(ids, jwt, enforce_acl=False):
                calls.append((list(ids), dict(jwt), enforce_acl))
                return {}

            self.chat._resolve_links = fake_resolve
            response = self.chat._handle_download(
                {"body": json.dumps({"document_id": "cat_9c2a41"})},
                {"groups": ["bpo_editor"]},
            )
        finally:
            self.chat._resolve_links = original_resolve_links

        self.assertEqual(response["statusCode"], 403)
        self.assertEqual(calls[0][2], True)

    def test_unretrieved_model_id_is_not_resolved(self):
        accepted = self.chat._cross_check_inline_ids(
            ["cat_9c2a41"],
            ["Refund policy without any protected catalog reference"],
        )
        self.assertEqual(accepted, [])

    def test_catalog_id_cross_check_uses_token_boundaries(self):
        accepted = self.chat._cross_check_inline_ids(
            ["cat_9c2a41"],
            ["A different identifier cat_9c2a410 must not match."],
        )
        self.assertEqual(accepted, [])

    def test_s3_attribution_is_mapped_to_opaque_catalog_id(self):
        uri = "s3://workspace-bucket/public/faq/refund-policy-v3.md"
        self.assertEqual(self.chat._catalog_id_from_s3_uri(uri), "cat_4b17e2")


if __name__ == "__main__":
    unittest.main(verbosity=2)
