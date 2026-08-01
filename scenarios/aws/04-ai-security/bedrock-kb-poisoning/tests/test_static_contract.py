"""Cross-file assertions that keep the demo, Terraform, and docs aligned."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path):
    return (ROOT / relative_path).read_text(encoding="utf-8")


class StaticContractTests(unittest.TestCase):
    def test_public_api_routes_exist(self):
        api = read("terraform/api_gateway.tf")
        self.assertIn('files = {\n      method = "GET"', api)
        self.assertIn('download = {\n      method = "POST"', api)
        self.assertIn('path_part   = each.key', api)

    def test_ui_calls_real_metadata_and_download_apis(self):
        app = read("assets/web/app.js")
        self.assertIn('apiRequest("/files", "GET"', app)
        self.assertIn('apiRequest("/download", "POST"', app)
        self.assertIn('data-download="${segment.document_id}"', app)
        self.assertIn('Try direct download', app)

    def test_catalog_ids_are_opaque_and_s3_keys_stay_internal(self):
        locals_tf = read("terraform/locals.tf")
        dynamodb_tf = read("terraform/dynamodb.tf")
        app = read("assets/web/app.js")
        self.assertIn('customer_export = "cat_9c2a41"', locals_tf)
        self.assertIn('document_id   = { S = local.catalog_ids.refund }', dynamodb_tf)
        self.assertIn('document_id   = { S = local.customer_export_doc_id }', dynamodb_tf)
        self.assertNotIn('customer-export/fitmall/2026-04', app)
        self.assertNotIn('faq/refund-policy-v3', app)

    def test_kb_excludes_admin_data_but_link_role_spans_workspace(self):
        bedrock = read("terraform/bedrock.tf")
        iam = read("terraform/iam.tf")
        self.assertIn('inclusion_prefixes = [\n        "public/"', bedrock)
        self.assertIn('Sid      = "WorkspaceGetObject"', iam)
        self.assertIn('Resource = "${aws_s3_bucket.workspace.arn}/*"', iam)

    def test_docs_name_all_four_public_routes(self):
        readme = read("README.md")
        setup = read("setup.md")
        for route in ("/api/chat", "/api/docs", "/api/files", "/api/download"):
            self.assertIn(route, readme)
            self.assertIn(route, setup)

    def test_walkthrough_explains_direct_and_indirect_paths(self):
        walkthrough = read("walkthrough.md")
        self.assertIn("normal resource-authorization path blocks", walkthrough)
        self.assertIn("literally appears in a FAQ chunk", walkthrough)
        self.assertIn("without asking it to enforce the final user's ACL", walkthrough)


if __name__ == "__main__":
    unittest.main(verbosity=2)
