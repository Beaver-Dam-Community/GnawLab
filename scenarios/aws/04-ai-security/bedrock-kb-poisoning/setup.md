# Bedrock Knowledge Base Poisoning - Setup Guide

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.5.0
- [AWS CLI](https://aws.amazon.com/cli/) v2
- `jq`, `curl`, `bash` (any modern Unix shell — tested on Ubuntu 24.04 LTS / WSL2)
- AWS Account with admin access (for resource creation)
- AWS CLI profile `GnawLab` configured with admin credentials
- **us-east-1** region (Bedrock Agent + Bedrock Knowledge Base availability)
- **Bedrock model access** approved for:
  - `anthropic.claude-3-haiku-20240307-v1:0`
  - `amazon.titan-embed-text-v2:0`

## Step 1: Configure AWS CLI Profile

```bash
aws configure --profile GnawLab
```

Enter your admin credentials:
- AWS Access Key ID: `<your-admin-access-key>`
- AWS Secret Access Key: `<your-admin-secret-key>`
- Default region name: `us-east-1`
- Default output format: `json`

Verify:

```bash
aws sts get-caller-identity --profile GnawLab
```

## Step 2: Enable Bedrock Foundation Models

Bedrock requires per-account, per-region opt-in for each foundation model. Open
the [Bedrock console → Model access](https://us-east-1.console.aws.amazon.com/bedrock/home?region=us-east-1#/modelaccess)
and request access to:

- **Anthropic — Claude 3 Haiku**
- **Amazon — Titan Text Embeddings V2**

Approval is usually instant for non-Anthropic models and within minutes for
Claude. You can verify from the CLI:

```bash
aws bedrock list-foundation-models \
  --region us-east-1 --profile GnawLab \
  --query 'modelSummaries[?contains(modelId, `claude-3-haiku`) || contains(modelId, `titan-embed-text-v2`)].[modelId,modelLifecycle.status]' \
  --output table
```

If either model is missing or not in `ACTIVE` state, the apply will fail at the
Bedrock Agent / Knowledge Base step.

## Step 3: Navigate to Terraform Directory

```bash
cd terraform
```

## Step 4: (Optional) Check Your Public IP

The scenario auto-detects your IP for the WAFv2 + API Gateway whitelist. To
verify what will be used:

```bash
curl -s https://ifconfig.co/ip
```

If you want to pin the IP explicitly (recommended in CI), create
`terraform.tfvars`:

```hcl
whitelist_ip = "1.2.3.4/32"
profile      = "GnawLab"
```

## Step 5: Initialize Terraform

```bash
terraform init
```

## Step 6: Review the Plan

```bash
terraform plan
```

You should see ~110 resources being created, including:

- 1 Bedrock Agent + 1 Bedrock Knowledge Base + 1 OpenSearch Serverless collection
- 1 Cognito User Pool with 2 groups, 2 users, 4 trigger Lambdas
- 5 Lambda functions (`chat_backend`, `source_link_issuer`,
  `kb_ingestion_trigger`, `cognito_pre_signup`, `cognito_post_confirmation`)
- 1 S3 workspace bucket + 1 DynamoDB `document_catalog` table
- 1 KMS CMK
- 1 API Gateway REST API (`/api/chat`)
- 1 CloudFront distribution + WAFv2 web ACL
- 1 S3 web hosting bucket (BPO console SPA + FitMall storefront)

## Step 7: Deploy the Scenario

```bash
terraform apply
```

Type `yes` when prompted. **Expect ~22–28 minutes** for the first apply — the
Bedrock Knowledge Base + OpenSearch Serverless collection alone take ~10 min,
and the CloudFront distribution another ~5–8 min.

If the apply is interrupted (network, MFA timeout, etc.), simply re-run
`terraform apply`. State is reconciled idempotently.

## Step 8: Seed the Knowledge Base (one-time, after the first apply)

> **Why:** Terraform creates the S3 bucket notification *after* the seed FAQ
> files are PUT to the bucket, so the first round of `ObjectCreated:*` events
> never fires. The KB stays empty until something else modifies `public/`. We
> run a single ingestion job by hand to seed it.

Drop into the `terraform` directory and run:

```bash
export AWS_PROFILE=GnawLab
export AWS_REGION=us-east-1

KB_ID=$(aws bedrock-agent list-knowledge-bases \
  --query 'knowledgeBaseSummaries[0].knowledgeBaseId' --output text)
DS_ID=$(aws bedrock-agent list-data-sources \
  --knowledge-base-id "$KB_ID" \
  --query 'dataSourceSummaries[0].dataSourceId' --output text)

echo "KB=$KB_ID  DS=$DS_ID"

aws bedrock-agent start-ingestion-job \
  --knowledge-base-id "$KB_ID" \
  --data-source-id   "$DS_ID" \
  --description "initial seed ingestion (manual)"

# Poll until COMPLETE (usually 30–90 s)
while :; do
  STATUS=$(aws bedrock-agent list-ingestion-jobs \
    --knowledge-base-id "$KB_ID" \
    --data-source-id   "$DS_ID" \
    --max-results 1 \
    --sort-by '{"attribute":"STARTED_AT","order":"DESCENDING"}' \
    --query 'ingestionJobSummaries[0].status' --output text)
  echo "ingestion: $STATUS"
  case "$STATUS" in COMPLETE) break ;; FAILED) exit 1 ;; *) sleep 6 ;; esac
done

echo "Knowledge Base seeded."
```

## Step 9: Get the Starting Credentials

```bash
terraform output -json leaked_credentials
terraform output console_url
```

Example:

```json
{
  "email":    "kay@digitalcs.example.com",
  "password": "Zxq8…",
  "groups":   ["bpo_editor"]
}
```

## Step 10: Start the Challenge

Open the `console_url` in a browser **from the same public IP** that you used
for `terraform apply` (otherwise CloudFront / WAF returns 403). Sign in as
Kay with the credentials from Step 9, then follow [walkthrough.md](./walkthrough.md).

## Configuration Options

Create `terraform.tfvars` for custom settings:

```hcl
# Optional: pin IP manually instead of auto-detect (must be CIDR with /32 mask)
whitelist_ip = "1.2.3.4/32"

# Optional: deploy with a different AWS CLI profile
profile = "my-admin-profile"

# Optional: switch Bedrock models (must already be approved on the account)
agent_model_id     = "anthropic.claude-3-haiku-20240307-v1:0"
embedding_model_id = "amazon.titan-embed-text-v2:0"

# Optional: override the seeded BPO / seller email domains and accounts
bpo_email_domain    = "digitalcs.example.com"
seller_email_domain = "fitmall.example.com"
kay_email           = "kay@digitalcs.example.com"
owner_email         = "owner@fitmall.example.com"
```

## Re-running, parallel runs, and destroy semantics

The Terraform module is built to be **idempotent** — you can re-apply on top
of a partial state, run multiple copies of the scenario in the same AWS
account, and destroy from any state without scripts:

- `random_string.scenario_id` (8 lowercase alphanumeric chars) is generated on
  first apply and pinned in `terraform.tfstate`. Every globally / regionally
  unique name (`aws_s3_bucket`, `aws_iam_role`, `aws_cognito_user_pool`,
  `aws_bedrockagent_*`, `aws_opensearchserverless_collection`, KMS alias, …)
  is suffixed with this id. **Re-applying never recreates these resources.**
- Two parallel deployments? `cp -r terraform terraform-second && cd
  terraform-second && terraform init && terraform apply`. The second copy
  generates its own `scenario_id` and lives alongside the first without name
  collisions.
- `terraform destroy` is self-contained: `bedrock.tf` ships
  `null_resource.predestroy_kb_jobs` and `null_resource.predestroy_workspace_bucket`,
  which run on destroy *before* their parent resources and respectively
  cancel any `IN_PROGRESS` Bedrock KB ingestion job and purge versioned
  objects + delete markers from the workspace bucket. You should not need
  the manual checklist in [cleanup.md](./cleanup.md) under normal conditions.

## Troubleshooting

### "AccessDeniedException: You don't have access to the model" during apply

Bedrock model access has not been approved on this account/region for one of
the models. See **Step 2**.

### Cognito sign-in returns "User does not exist"

Two pre-seeded users (Kay + FitMall owner) are created via `AdminCreateUser`,
which fires the PreSignUp / PostConfirmation hooks. If you re-applied during a
hook deploy, the user records can race with the `lambda:InvokeFunction`
permissions. Re-run `terraform apply` once and the user will be created
cleanly (the `aws_cognito_user` resources have explicit `depends_on` on the
permission resources).

### CloudFront / API Gateway returns 403

Your public IP no longer matches the WAFv2 IP set. Re-run
`terraform apply` to refresh `whitelist_ip` (auto-detect picks up the new IP).

### Chatbot answers "I cannot help with that request."

The Bedrock Guardrail tripped. The seeded prompt-injection in the walkthrough
is mild enough to bypass it, but if you experimented with stronger payloads
the guardrail may have started flagging the query itself. Tone the payload
down — see [walkthrough.md](./walkthrough.md) Step 4 for a known-good shape.

### KB returns the original FAQ even after editing it

The bucket notification fired but the ingestion job is queued. List recent
jobs and wait for `COMPLETE`:

```bash
aws bedrock-agent list-ingestion-jobs \
  --knowledge-base-id "$KB_ID" --data-source-id "$DS_ID" \
  --max-results 5 \
  --sort-by '{"attribute":"STARTED_AT","order":"DESCENDING"}' \
  --output table
```

### Terraform state issues

```bash
terraform refresh
```

If you see drift on `aws_s3_object.faq_*` after manual edits, that is
expected — the seed files are under Terraform's content control. The
walkthrough does its poisoning via the BPO console (which writes through
`chat_backend` Lambda using a different etag) so it does not collide with
state.

## Cost Estimate

This scenario uses (us-east-1):

| Service                          | Idle (per hour) | During walkthrough |
|----------------------------------|-----------------|--------------------|
| OpenSearch Serverless (1 OCU)    | ~$0.24          | ~$0.24             |
| Bedrock Knowledge Base (storage) | ~$0.01          | ~$0.01             |
| Bedrock Agent invocations        | $0              | ~$0.10             |
| Lambda                           | $0              | <$0.01             |
| API Gateway                      | $0              | <$0.01             |
| CloudFront                       | $0              | <$0.01             |
| S3 + DynamoDB                    | <$0.01          | <$0.01             |
| KMS                              | ~$0.04          | ~$0.04             |
| **Total**                        | **~$0.30 / h**  | **~$0.45 / h**     |

> **Estimated total cost: < $2** for a 90-minute walk-through, *if you destroy
> immediately afterwards*. OpenSearch Serverless billing is per-OCU-hour, so
> leaving the stack idle is the dominant cost. Always run `terraform destroy`
> when finished. See [cleanup.md](./cleanup.md).
