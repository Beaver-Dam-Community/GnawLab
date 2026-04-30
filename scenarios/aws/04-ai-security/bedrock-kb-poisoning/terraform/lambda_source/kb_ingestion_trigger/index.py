"""S3 ObjectCreated -> Bedrock Knowledge Base ingestion trigger.

Whenever a document is uploaded under the `public/` prefix, kick off a KB
ingestion job so the chatbot can answer using the new content within ~30s.
"""

import os
import boto3

bedrock_agent = boto3.client("bedrock-agent")

KB_ID = os.environ["KB_ID"]
DATA_SOURCE_ID = os.environ["DATA_SOURCE_ID"]


def lambda_handler(event, context):
    bedrock_agent.start_ingestion_job(
        knowledgeBaseId=KB_ID,
        dataSourceId=DATA_SOURCE_ID,
        description="Triggered by S3 ObjectCreated under public/",
    )
    return {"status": "ingestion_started"}
