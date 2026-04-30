# Bedrock Knowledge Base Poisoning - Cleanup Guide

## Why this is more involved than a single-resource scenario

`terraform destroy` cannot tear down some Bedrock Agent / Knowledge Base
resources cleanly while:

- a Bedrock Agent has an active alias bound to a `DRAFT` version,
- a Knowledge Base still has an `IN_PROGRESS` ingestion job, or
- an S3 bucket with versioning has accumulated object versions and delete
  markers (the workspace bucket gets a lot of these during the walkthrough).

Running the **pre-destroy steps below** before `terraform destroy` makes
teardown deterministic and short (~6–8 min wall clock).

## Automated Cleanup (Recommended)

### Step 1: Pre-destroy Bedrock + S3 cleanup

Run from the scenario root (the directory containing `terraform/`):

```bash
export AWS_PROFILE=GnawLab
export AWS_REGION=us-east-1

cd terraform

# Read what we deployed (skip silently if any output is missing)
agent_id=$(terraform output -raw agent_id 2>/dev/null || true)
agent_alias_id=$(terraform output -raw agent_alias_id 2>/dev/null || true)
ws_bucket=$(terraform output -json verification 2>/dev/null \
              | jq -r '.workspace_bucket // empty')

echo "agent=$agent_id alias=$agent_alias_id bucket=$ws_bucket"

# 1) Cancel any in-flight KB ingestion jobs
for kb in $(aws bedrock-agent list-knowledge-bases \
              --query 'knowledgeBaseSummaries[].knowledgeBaseId' --output text); do
  for ds in $(aws bedrock-agent list-data-sources \
                --knowledge-base-id "$kb" \
                --query 'dataSourceSummaries[].dataSourceId' --output text); do
    for j in $(aws bedrock-agent list-ingestion-jobs \
                 --knowledge-base-id "$kb" --data-source-id "$ds" \
                 --query "ingestionJobSummaries[?status=='IN_PROGRESS' || status=='STARTING'].ingestionJobId" \
                 --output text); do
      echo "Cancelling ingestion job $j"
      aws bedrock-agent stop-ingestion-job \
        --knowledge-base-id "$kb" --data-source-id "$ds" \
        --ingestion-job-id "$j" >/dev/null || true
    done
  done
done

# 2) Delete the Agent prod alias (if present) so destroy can remove the Agent
if [ -n "$agent_id" ] && [ -n "$agent_alias_id" ]; then
  aws bedrock-agent delete-agent-alias \
    --agent-id "$agent_id" --agent-alias-id "$agent_alias_id" || true
fi

# 3) Disassociate the Knowledge Base from the Agent's DRAFT version
if [ -n "$agent_id" ]; then
  for kb in $(aws bedrock-agent list-agent-knowledge-bases \
                --agent-id "$agent_id" --agent-version DRAFT \
                --query 'agentKnowledgeBaseSummaries[].knowledgeBaseId' \
                --output text 2>/dev/null); do
    aws bedrock-agent disassociate-agent-knowledge-base \
      --agent-id "$agent_id" --agent-version DRAFT \
      --knowledge-base-id "$kb" >/dev/null || true
  done
fi

# 4) Empty the workspace bucket (versioned). Repeat for any other versioned
#    buckets terraform created (web hosting bucket, KB data bucket — they
#    appear in `terraform state list | grep aws_s3_bucket`).
empty_bucket() {
  local b="$1"
  [ -z "$b" ] && return 0
  echo "Emptying bucket $b"
  aws s3api delete-objects --bucket "$b" --delete "$(aws s3api list-object-versions \
      --bucket "$b" --output json \
      --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
      2>/dev/null | jq 'select(.Objects != null)')" >/dev/null 2>&1 || true
  aws s3api delete-objects --bucket "$b" --delete "$(aws s3api list-object-versions \
      --bucket "$b" --output json \
      --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
      2>/dev/null | jq 'select(.Objects != null)')" >/dev/null 2>&1 || true
  aws s3 rm "s3://$b" --recursive >/dev/null 2>&1 || true
}

for b in $(terraform state list 2>/dev/null | grep '^aws_s3_bucket\.'); do
  name=$(terraform state show "$b" 2>/dev/null | awk '/^ +bucket +=/ {gsub(/"/,""); print $3; exit}')
  empty_bucket "$name"
done

echo "Pre-destroy cleanup done."
```

### Step 2: Destroy All Resources

```bash
terraform destroy
```

Type `yes` when prompted. **Expect ~5–10 minutes**. CloudFront is the slowest
resource (it has to fully `Disabled` → `Deleted`).

### Step 3: Verify Cleanup

```bash
terraform show
```

Should output `No state.` or empty state.

## Manual Cleanup Checklist

If `terraform destroy` fails, manually delete these resources by tag.

### AWS CLI

```bash
export AWS_PROFILE=GnawLab
export AWS_REGION=us-east-1

# 1. Bedrock Agent (delete alias → agent)
for a in $(aws bedrock-agent list-agents \
            --query "agentSummaries[?contains(agentName, 'gnawlab-bkp')].agentId" \
            --output text); do
  for al in $(aws bedrock-agent list-agent-aliases --agent-id "$a" \
                --query 'agentAliasSummaries[].agentAliasId' --output text); do
    aws bedrock-agent delete-agent-alias --agent-id "$a" --agent-alias-id "$al" || true
  done
  aws bedrock-agent delete-agent --agent-id "$a" --skip-resource-in-use-check || true
done

# 2. Bedrock Knowledge Base (delete data source → KB)
for kb in $(aws bedrock-agent list-knowledge-bases \
             --query "knowledgeBaseSummaries[?contains(name, 'gnawlab-bkp')].knowledgeBaseId" \
             --output text); do
  for ds in $(aws bedrock-agent list-data-sources --knowledge-base-id "$kb" \
                --query 'dataSourceSummaries[].dataSourceId' --output text); do
    aws bedrock-agent delete-data-source --knowledge-base-id "$kb" \
      --data-source-id "$ds" || true
  done
  aws bedrock-agent delete-knowledge-base --knowledge-base-id "$kb" || true
done

# 3. OpenSearch Serverless collection + policies
for c in $(aws opensearchserverless list-collections \
             --query "collectionSummaries[?starts_with(name, 'bkp-kb-')].name" \
             --output text); do
  cid=$(aws opensearchserverless batch-get-collection --names "$c" \
          --query 'collectionDetails[0].id' --output text)
  aws opensearchserverless delete-collection --id "$cid" || true
done

for p in $(aws opensearchserverless list-security-policies --type encryption \
             --query "securityPolicySummaries[?starts_with(name, 'bkp-')].name" \
             --output text); do
  aws opensearchserverless delete-security-policy --type encryption --name "$p" || true
done

for p in $(aws opensearchserverless list-security-policies --type network \
             --query "securityPolicySummaries[?starts_with(name, 'bkp-')].name" \
             --output text); do
  aws opensearchserverless delete-security-policy --type network --name "$p" || true
done

for p in $(aws opensearchserverless list-access-policies --type data \
             --query "accessPolicySummaries[?starts_with(name, 'bkp-')].name" \
             --output text); do
  aws opensearchserverless delete-access-policy --type data --name "$p" || true
done

# 4. Cognito User Pool (must delete domain first)
for up in $(aws cognito-idp list-user-pools --max-results 60 \
              --query "UserPools[?contains(Name, 'gnawlab-bkp')].Id" \
              --output text); do
  domain=$(aws cognito-idp describe-user-pool --user-pool-id "$up" \
            --query 'UserPool.Domain' --output text 2>/dev/null || true)
  if [ -n "$domain" ] && [ "$domain" != "None" ]; then
    aws cognito-idp delete-user-pool-domain --domain "$domain" --user-pool-id "$up" || true
  fi
  aws cognito-idp delete-user-pool --user-pool-id "$up" || true
done

# 5. S3 buckets (versioned)
empty_bucket() { … }   # reuse the function from Step 1 above
for b in $(aws s3api list-buckets \
            --query "Buckets[?starts_with(Name, 'gnawlab-bkp')].Name" \
            --output text); do
  empty_bucket "$b"
  aws s3api delete-bucket --bucket "$b" || true
done

# 6. CloudFront distribution (must disable then wait then delete)
for id in $(aws cloudfront list-distributions \
             --query "DistributionList.Items[?starts_with(Comment, 'TokTok-Support console')].Id" \
             --output text); do
  etag=$(aws cloudfront get-distribution-config --id "$id" \
           --query 'ETag' --output text)
  aws cloudfront get-distribution-config --id "$id" \
    --query 'DistributionConfig' --output json \
    | jq '.Enabled=false' > /tmp/cfg.json
  aws cloudfront update-distribution --id "$id" --if-match "$etag" \
    --distribution-config file:///tmp/cfg.json || true
  echo "Wait until CloudFront $id is Deployed + Disabled, then:"
  echo "  aws cloudfront delete-distribution --id $id --if-match <new-etag>"
done

# 7. CloudWatch log groups (Lambda + API GW)
for lg in $(aws logs describe-log-groups \
             --log-group-name-prefix "/aws/lambda/gnawlab-bkp" \
             --query 'logGroups[].logGroupName' --output text); do
  aws logs delete-log-group --log-group-name "$lg" || true
done

# 8. KMS CMKs (schedule for deletion, 7-day window)
for k in $(aws kms list-aliases \
            --query "Aliases[?starts_with(AliasName, 'alias/gnawlab-bkp')].TargetKeyId" \
            --output text); do
  aws kms schedule-key-deletion --key-id "$k" --pending-window-in-days 7 || true
done

# 9. IAM roles + policies
for r in $(aws iam list-roles \
            --query "Roles[?starts_with(RoleName, 'gnawlab-bkp')].RoleName" \
            --output text); do
  for p in $(aws iam list-attached-role-policies --role-name "$r" \
              --query 'AttachedPolicies[].PolicyArn' --output text); do
    aws iam detach-role-policy --role-name "$r" --policy-arn "$p" || true
  done
  for p in $(aws iam list-role-policies --role-name "$r" \
              --query 'PolicyNames[]' --output text); do
    aws iam delete-role-policy --role-name "$r" --policy-name "$p" || true
  done
  aws iam delete-role --role-name "$r" || true
done

for p in $(aws iam list-policies --scope Local \
            --query "Policies[?starts_with(PolicyName, 'gnawlab-bkp')].Arn" \
            --output text); do
  aws iam delete-policy --policy-arn "$p" || true
done
```

## Remove Local Files

```bash
# Remove Terraform state and cache
rm -rf terraform/.terraform
rm -f  terraform/.terraform.lock.hcl
rm -f  terraform/terraform.tfstate*

# Remove tfvars if you created one
rm -f  terraform/terraform.tfvars
```

## Verify No Resources Remain

Check for any lingering resources tagged with this scenario:

```bash
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Scenario,Values=bedrock-kb-poisoning \
  --region us-east-1 --profile GnawLab
```

Expected:

```json
{
    "ResourceTagMappingList": []
}
```

> **Note:** Resources created by Bedrock and OpenSearch Serverless services
> sometimes do not propagate the `Scenario` tag to the *Resource Groups
> Tagging API* immediately. If the list above is empty but you still see
> `bkp-kb-…` collections in the OpenSearch console, wait 5 minutes and
> retry the manual checklist.

## Cost Verification

Check your AWS billing to make sure the long-running services have stopped:

1. [AWS Billing Console](https://console.aws.amazon.com/billing/) → *Bills*
2. Look at the current month's *OpenSearch Serverless* (OCU-hour) and *Amazon
   Bedrock* lines. After destroy completes, both should stop accumulating
   charges within ~30 minutes.

If OpenSearch Serverless OCU-hours are still accruing 1 h after `terraform
destroy`, the collection was orphaned — re-run the **OpenSearch Serverless**
section of the manual checklist.
