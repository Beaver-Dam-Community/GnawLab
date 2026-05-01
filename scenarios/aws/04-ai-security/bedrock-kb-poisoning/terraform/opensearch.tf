# OpenSearch Serverless vector collection used as the Bedrock KB store.
# Bedrock KB needs its data-access policy to include the KB execution role.

resource "aws_opensearchserverless_security_policy" "kb_encryption" {
  name = "${local.scenario_name}-enc-${local.scenario_id}"
  type = "encryption"

  policy = jsonencode({
    Rules = [
      {
        Resource     = ["collection/${local.oss_collection}"]
        ResourceType = "collection"
      }
    ]
    AWSOwnedKey = true
  })
}

resource "aws_opensearchserverless_security_policy" "kb_network" {
  name = "${local.scenario_name}-net-${local.scenario_id}"
  type = "network"

  policy = jsonencode([
    {
      Rules = [
        {
          Resource     = ["collection/${local.oss_collection}"]
          ResourceType = "collection"
        },
        {
          Resource     = ["collection/${local.oss_collection}"]
          ResourceType = "dashboard"
        }
      ]
      AllowFromPublic = true
    }
  ])
}

resource "aws_opensearchserverless_access_policy" "kb_data_access" {
  name = "${local.scenario_name}-dap-${local.scenario_id}"
  type = "data"

  policy = jsonencode([
    {
      Rules = [
        {
          Resource     = ["collection/${local.oss_collection}"]
          ResourceType = "collection"
          Permission = [
            "aoss:CreateCollectionItems",
            "aoss:DeleteCollectionItems",
            "aoss:UpdateCollectionItems",
            "aoss:DescribeCollectionItems",
          ]
        },
        {
          Resource     = ["index/${local.oss_collection}/*"]
          ResourceType = "index"
          Permission = [
            "aoss:CreateIndex",
            "aoss:DeleteIndex",
            "aoss:UpdateIndex",
            "aoss:DescribeIndex",
            "aoss:ReadDocument",
            "aoss:WriteDocument",
          ]
        }
      ]
      Principal = [
        aws_iam_role.bedrock_kb.arn,
        data.aws_caller_identity.current.arn,
      ]
    }
  ])
}

resource "aws_opensearchserverless_collection" "kb" {
  name = local.oss_collection
  type = "VECTORSEARCH"

  depends_on = [
    aws_opensearchserverless_security_policy.kb_encryption,
    aws_opensearchserverless_security_policy.kb_network,
    aws_opensearchserverless_access_policy.kb_data_access,
  ]
}

# Bedrock KB requires a vector index. Create it via opensearch-py from the
# Terraform host (same pattern v11 used).
resource "null_resource" "create_vector_index" {
  depends_on = [aws_opensearchserverless_collection.kb]

  triggers = {
    collection_endpoint = aws_opensearchserverless_collection.kb.collection_endpoint
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOF
      python3 - <<'PYEOF'
import json
import time
import boto3
from opensearchpy import OpenSearch, RequestsHttpConnection, AWSV4SignerAuth

aoss = boto3.client('opensearchserverless', region_name='${var.region}')
collection_name = "${aws_opensearchserverless_collection.kb.name}"

print(f"Waiting for collection {collection_name} to become ACTIVE...")
for attempt in range(30):
    resp = aoss.batch_get_collection(names=[collection_name])
    details = resp.get('collectionDetails', [])
    if details and details[0].get('status') == 'ACTIVE':
        print(f"Collection ACTIVE after {attempt * 10}s")
        break
    print(f"  Status: {details[0].get('status') if details else 'unknown'}, waiting...")
    time.sleep(10)
else:
    raise SystemExit("Collection did not become ACTIVE within 300s")

endpoint = "${aws_opensearchserverless_collection.kb.collection_endpoint}"
host = endpoint.replace("https://", "")
credentials = boto3.Session().get_credentials()
auth = AWSV4SignerAuth(credentials, '${var.region}', 'aoss')

client = OpenSearch(
    hosts=[{'host': host, 'port': 443}],
    http_auth=auth,
    use_ssl=True,
    verify_certs=True,
    connection_class=RequestsHttpConnection,
    timeout=60,
)

index_name = "bedrock-knowledge-base-default-index"
try:
    if client.indices.exists(index=index_name):
        print(f"Index {index_name} already exists, skipping creation")
        raise SystemExit(0)
except Exception as e:
    print(f"Index check error (may not exist yet): {e}")

index_body = {
    "settings": {
        "index.knn": True,
        "number_of_shards": 2,
        "number_of_replicas": 0,
    },
    "mappings": {
        "properties": {
            "bedrock-knowledge-base-default-vector": {
                "type": "knn_vector",
                "dimension": 1024,
                "method": {
                    "engine": "faiss",
                    "name": "hnsw",
                    "parameters": {
                        "m": 16,
                        "ef_construction": 512,
                    }
                }
            },
            "AMAZON_BEDROCK_METADATA": {"type": "text", "index": False},
            "AMAZON_BEDROCK_TEXT_CHUNK": {"type": "text"},
        }
    }
}

print(f"Creating vector index: {index_name}")
response = client.indices.create(index=index_name, body=index_body)
print(f"Index created: {json.dumps(response)}")
PYEOF
    EOF
  }
}
