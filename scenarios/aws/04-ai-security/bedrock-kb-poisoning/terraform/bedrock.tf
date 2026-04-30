# Bedrock Knowledge Base + Agent + Guardrail.
# - KB has `public/` prefix as its only S3 data source (admin-only/* is NOT
#   ingested, so the LLM never sees admin-only customer rows directly).
# - Agent is configured with KB association ONLY. No action group.
# - Guardrail blocks PROMPT_ATTACK on user inputs (does not cover KB chunks
#   per AWS documented limitation -> the LLM-side hinge of the chain).

resource "aws_bedrockagent_knowledge_base" "main" {
  name     = "${local.scenario_name}-kb-${local.scenario_id}"
  role_arn = aws_iam_role.bedrock_kb.arn

  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:${data.aws_partition.current.partition}:bedrock:${var.region}::foundation-model/${var.embedding_model_id}"
    }
  }

  storage_configuration {
    type = "OPENSEARCH_SERVERLESS"
    opensearch_serverless_configuration {
      collection_arn    = aws_opensearchserverless_collection.kb.arn
      vector_index_name = "bedrock-knowledge-base-default-index"
      field_mapping {
        vector_field   = "bedrock-knowledge-base-default-vector"
        text_field     = "AMAZON_BEDROCK_TEXT_CHUNK"
        metadata_field = "AMAZON_BEDROCK_METADATA"
      }
    }
  }

  depends_on = [
    null_resource.create_vector_index,
  ]
}

resource "aws_bedrockagent_data_source" "public_prefix" {
  name              = "public-docs"
  knowledge_base_id = aws_bedrockagent_knowledge_base.main.id

  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn = aws_s3_bucket.workspace.arn
      inclusion_prefixes = [
        "public/",
      ]
    }
  }

  data_deletion_policy = "DELETE"
}

# Guardrail. PROMPT_ATTACK on user inputs only (Bedrock-documented behaviour -
# does not inspect KB-retrieved chunks, which is the LLM-side hinge).
resource "aws_bedrock_guardrail" "main" {
  name                      = "${local.scenario_name}-guardrail-${local.scenario_id}"
  description               = "TokTok-Support PROMPT_ATTACK + PII guardrail"
  blocked_input_messaging   = "I cannot help with that request."
  blocked_outputs_messaging = "I cannot share that information."

  content_policy_config {
    filters_config {
      input_strength  = "HIGH"
      output_strength = "NONE"
      type            = "PROMPT_ATTACK"
    }
  }

  sensitive_information_policy_config {
    pii_entities_config {
      action = "ANONYMIZE"
      type   = "EMAIL"
    }
    pii_entities_config {
      action = "ANONYMIZE"
      type   = "PHONE"
    }
  }
}

resource "aws_bedrock_guardrail_version" "main" {
  guardrail_arn = aws_bedrock_guardrail.main.guardrail_arn
  description   = "Initial production version"
  skip_destroy  = false
}

# Agent with KB association ONLY. No action group.
resource "aws_bedrockagent_agent" "main" {
  agent_name                  = "${local.scenario_name}-support-agent-${local.scenario_id}"
  agent_resource_role_arn     = aws_iam_role.bedrock_agent.arn
  foundation_model            = var.agent_model_id
  idle_session_ttl_in_seconds = 1800
  prepare_agent               = true

  guardrail_configuration {
    guardrail_identifier = aws_bedrock_guardrail.main.guardrail_id
    guardrail_version    = aws_bedrock_guardrail_version.main.version
  }

  instruction = <<-EOT
    You are the TokTok-Support customer service assistant for FitMall, a Korean
    activewear brand. Answer questions about refunds, exchanges, shipping and
    sizing using the retrieved Knowledge Base context.

    When you cite a source document in your answer, append an inline citation
    tag in the form `[source: <document_id>]` at the end of the relevant
    sentence. The TokTok-Support frontend will replace the tag with a
    clickable download link automatically.

    Only cite document IDs that appear in the retrieved context for the
    current answer. Never invent document IDs. Never include raw S3 paths,
    customer PII, payment information, or sales data in your responses.
    If a question cannot be answered from the retrieved context, say so and
    direct the customer to a human agent.
  EOT
}

resource "aws_bedrockagent_agent_knowledge_base_association" "main" {
  agent_id             = aws_bedrockagent_agent.main.agent_id
  knowledge_base_id    = aws_bedrockagent_knowledge_base.main.id
  knowledge_base_state = "ENABLED"
  description          = "FitMall public FAQ + manuals"
}

resource "aws_bedrockagent_agent_alias" "prod" {
  agent_id         = aws_bedrockagent_agent.main.agent_id
  agent_alias_name = "prod"

  depends_on = [
    aws_bedrockagent_agent_knowledge_base_association.main,
  ]
}

# ----------------------------------------------------------------------------
# Destroy-time hooks: make `terraform destroy` self-contained.
#
# The two situations that historically blocked a clean teardown are:
#   1. The Knowledge Base has an `IN_PROGRESS` / `STARTING` ingestion job, so
#      `DeleteKnowledgeBase` returns ConflictException.
#   2. The workspace S3 bucket has accumulated noncurrent object versions and
#      delete markers from the walkthrough (FAQ saves trigger versioning).
#      `force_destroy = true` already covers this, but a versioned bucket with
#      hundreds of markers can time out the in-provider sweep.
#
# These two `null_resource`s exist purely to run an AWS CLI cleanup script on
# destroy, before Terraform tries to delete the parent resource. They are
# no-ops on apply and do not consume state outside of `triggers`.
#
# Implicit dependency via `triggers` ensures Terraform schedules them AFTER
# the KB / data source / bucket on apply, and BEFORE them on destroy.
# ----------------------------------------------------------------------------

resource "null_resource" "predestroy_kb_jobs" {
  triggers = {
    kb_id  = aws_bedrockagent_knowledge_base.main.id
    ds_id  = aws_bedrockagent_data_source.public_prefix.id
    region = data.aws_region.current.region
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set +e
      KB="${self.triggers.kb_id}"
      DS="${self.triggers.ds_id}"
      REGION="${self.triggers.region}"

      echo "[predestroy_kb_jobs] cancelling in-flight ingestion jobs for KB=$KB DS=$DS"
      JOBS=$(aws bedrock-agent list-ingestion-jobs \
               --region "$REGION" \
               --knowledge-base-id "$KB" \
               --data-source-id "$DS" \
               --query 'ingestionJobSummaries[?status==`IN_PROGRESS` || status==`STARTING`].ingestionJobId' \
               --output text 2>/dev/null)
      for j in $JOBS; do
        echo "  stop-ingestion-job $j"
        aws bedrock-agent stop-ingestion-job \
          --region "$REGION" \
          --knowledge-base-id "$KB" \
          --data-source-id "$DS" \
          --ingestion-job-id "$j" >/dev/null 2>&1 || true
      done

      # Best-effort: wait up to 60s for jobs to leave RUNNING state.
      for _ in 1 2 3 4 5 6; do
        REM=$(aws bedrock-agent list-ingestion-jobs \
                --region "$REGION" \
                --knowledge-base-id "$KB" \
                --data-source-id "$DS" \
                --query 'length(ingestionJobSummaries[?status==`IN_PROGRESS` || status==`STARTING`])' \
                --output text 2>/dev/null)
        [ "$REM" = "0" ] && break
        sleep 10
      done
      exit 0
    EOT
  }
}

resource "null_resource" "predestroy_workspace_bucket" {
  triggers = {
    bucket = aws_s3_bucket.workspace.id
    region = data.aws_region.current.region
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set +e
      B="${self.triggers.bucket}"
      REGION="${self.triggers.region}"

      echo "[predestroy_workspace_bucket] purging versions+markers from $B"
      while :; do
        OUT=$(aws s3api list-object-versions \
                --region "$REGION" --bucket "$B" --max-keys 1000 \
                --output json 2>/dev/null)
        [ -z "$OUT" ] && break
        N=$(echo "$OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('Versions',[]) or [])+len(d.get('DeleteMarkers',[]) or []))" 2>/dev/null)
        [ -z "$N" ] || [ "$N" = "0" ] && break

        echo "$OUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
items = [{'Key': v['Key'], 'VersionId': v['VersionId']} for v in (d.get('Versions') or [])]
items += [{'Key': v['Key'], 'VersionId': v['VersionId']} for v in (d.get('DeleteMarkers') or [])]
print(json.dumps({'Objects': items, 'Quiet': True}))
" > /tmp/_del_$$.json
        aws s3api delete-objects --region "$REGION" --bucket "$B" \
          --delete file:///tmp/_del_$$.json >/dev/null 2>&1 || true
        rm -f /tmp/_del_$$.json
      done
      exit 0
    EOT
  }
}
