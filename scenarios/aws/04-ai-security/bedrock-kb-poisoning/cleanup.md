# Bedrock Knowledge Base Poisoning - Cleanup Guide

## TL;DR

```bash
cd terraform
terraform destroy
```

That's it. The Terraform module includes destroy-time hooks that handle the
two situations where a naive `terraform destroy` would otherwise stall:

| Situation | Handled by |
|---|---|
| Knowledge Base has an `IN_PROGRESS` / `STARTING` ingestion job | `null_resource.predestroy_kb_jobs` (in `bedrock.tf`) |
| Workspace S3 bucket has accumulated noncurrent versions + delete markers from FAQ saves | `null_resource.predestroy_workspace_bucket` (in `bedrock.tf`) + `force_destroy = true` |
| Bedrock Agent has an alias bound to its `DRAFT` version | Terraform deletes `aws_bedrockagent_agent_alias.prod` before the agent itself, no manual help needed |
| OpenSearch Serverless collection still referenced by KB | `aws_bedrockagent_knowledge_base.main` is destroyed before the collection (explicit `depends_on`) |

Expected wall-clock time: **~6–9 min**. CloudFront is the slowest component
(it has to fully `Disabled` → `Deleted`).

## Standard Cleanup

```bash
export AWS_PROFILE=GnawLab
export AWS_REGION=us-east-1

cd terraform
terraform destroy
```

Type `yes` when prompted.

You should see lines like the following early in the output, emitted by the
destroy-time hooks:

```text
null_resource.predestroy_kb_jobs (local-exec): [predestroy_kb_jobs] cancelling in-flight ingestion jobs for KB=...
null_resource.predestroy_workspace_bucket (local-exec): [predestroy_workspace_bucket] purging versions+markers from gnawlab-bkp-...-workspace
```

### Verify the destroy completed

```bash
terraform show
# expected: "No state."

aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Scenario,Values=bedrock-kb-poisoning \
  --region us-east-1 --profile GnawLab \
  --query 'ResourceTagMappingList[].ResourceARN' --output table
# expected: empty
```

> **Tagging API caveat.** Bedrock Agent / KMS keys can show up here for a
> few minutes after destroy with state `PendingDeletion` (KMS) or
> `ResourceNotFoundException` (Agent — tagging API cache). Re-running the
> command 5–10 min later returns an empty list. Anything *not* in
> `PendingDeletion` after that point should be cleaned up via the manual
> checklist below.

## Remove Local Files

```bash
# Drop Terraform state, lockfile and provider cache
rm -rf terraform/.terraform
rm -f  terraform/.terraform.lock.hcl
rm -f  terraform/terraform.tfstate*

# Drop your tfvars override (if any)
rm -f  terraform/terraform.tfvars
```

## Manual Cleanup Checklist (Fallback)

You should not need this — the destroy hooks above are what makes the
scenario "any-state-destroyable" — but if `terraform destroy` reports a
`ConflictException` / `ValidationException` on Bedrock or OpenSearch
Serverless, run the section that matches the failing resource and re-run
`terraform destroy`.

> All snippets below filter on the shared `gnawlab-bkp-` prefix that every
> resource in this scenario shares (the trailing `-${scenario_id}` keeps
> them unique per deployment). They will not touch other scenarios in the
> same account.

### 1. Bedrock Agent (delete alias → agent)

```bash
for a in $(aws bedrock-agent list-agents \
            --query "agentSummaries[?contains(agentName, 'gnawlab-bkp')].agentId" \
            --output text); do
  for al in $(aws bedrock-agent list-agent-aliases --agent-id "$a" \
                --query 'agentAliasSummaries[].agentAliasId' --output text); do
    aws bedrock-agent delete-agent-alias --agent-id "$a" --agent-alias-id "$al" || true
  done
  aws bedrock-agent delete-agent --agent-id "$a" --skip-resource-in-use-check || true
done
```

### 2. Bedrock Knowledge Base (stop jobs → delete data source → delete KB)

```bash
for kb in $(aws bedrock-agent list-knowledge-bases \
             --query "knowledgeBaseSummaries[?contains(name, 'gnawlab-bkp')].knowledgeBaseId" \
             --output text); do
  for ds in $(aws bedrock-agent list-data-sources --knowledge-base-id "$kb" \
                --query 'dataSourceSummaries[].dataSourceId' --output text); do
    for j in $(aws bedrock-agent list-ingestion-jobs \
                 --knowledge-base-id "$kb" --data-source-id "$ds" \
                 --query "ingestionJobSummaries[?status=='IN_PROGRESS' || status=='STARTING'].ingestionJobId" \
                 --output text); do
      aws bedrock-agent stop-ingestion-job \
        --knowledge-base-id "$kb" --data-source-id "$ds" --ingestion-job-id "$j" || true
    done
    aws bedrock-agent delete-data-source \
      --knowledge-base-id "$kb" --data-source-id "$ds" || true
  done
  aws bedrock-agent delete-knowledge-base --knowledge-base-id "$kb" || true
done
```

### 3. OpenSearch Serverless collection + policies

```bash
for c in $(aws opensearchserverless list-collections \
             --query "collectionSummaries[?starts_with(name, 'gnawlab-bkp-')].name" \
             --output text); do
  cid=$(aws opensearchserverless batch-get-collection --names "$c" \
          --query 'collectionDetails[0].id' --output text)
  aws opensearchserverless delete-collection --id "$cid" || true
done

for kind in encryption network; do
  for p in $(aws opensearchserverless list-security-policies --type "$kind" \
               --query "securityPolicySummaries[?starts_with(name, 'gnawlab-bkp-')].name" \
               --output text); do
    aws opensearchserverless delete-security-policy --type "$kind" --name "$p" || true
  done
done

for p in $(aws opensearchserverless list-access-policies --type data \
             --query "accessPolicySummaries[?starts_with(name, 'gnawlab-bkp-')].name" \
             --output text); do
  aws opensearchserverless delete-access-policy --type data --name "$p" || true
done
```

### 4. Cognito User Pool (delete domain first, then pool)

```bash
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
```

### 5. S3 buckets (versioned)

```bash
empty_bucket() {
  local b="$1"
  [ -z "$b" ] && return 0
  while :; do
    out=$(aws s3api list-object-versions --bucket "$b" --max-keys 1000 --output json 2>/dev/null)
    [ -z "$out" ] && break
    n=$(echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('Versions',[]) or [])+len(d.get('DeleteMarkers',[]) or []))")
    [ "$n" = "0" ] && break
    echo "$out" | python3 -c "
import sys, json
d = json.load(sys.stdin)
items  = [{'Key': v['Key'], 'VersionId': v['VersionId']} for v in (d.get('Versions') or [])]
items += [{'Key': v['Key'], 'VersionId': v['VersionId']} for v in (d.get('DeleteMarkers') or [])]
print(json.dumps({'Objects': items, 'Quiet': True}))
" > /tmp/_del.json
    aws s3api delete-objects --bucket "$b" --delete file:///tmp/_del.json >/dev/null 2>&1 || true
  done
}

for b in $(aws s3api list-buckets \
            --query "Buckets[?starts_with(Name, 'gnawlab-bkp')].Name" \
            --output text); do
  empty_bucket "$b"
  aws s3api delete-bucket --bucket "$b" || true
done
```

### 6. CloudFront distribution

```bash
for id in $(aws cloudfront list-distributions \
             --query "DistributionList.Items[?starts_with(Comment, 'TokTok-Support console')].Id" \
             --output text); do
  etag=$(aws cloudfront get-distribution-config --id "$id" --query 'ETag' --output text)
  aws cloudfront get-distribution-config --id "$id" --query 'DistributionConfig' --output json \
    | jq '.Enabled=false' > /tmp/cfg.json
  aws cloudfront update-distribution --id "$id" --if-match "$etag" \
    --distribution-config file:///tmp/cfg.json || true
  echo "Wait until CloudFront $id is Deployed + Disabled, then:"
  echo "  aws cloudfront delete-distribution --id $id --if-match <new-etag>"
done
```

### 7. CloudWatch Logs / KMS / IAM (catch-alls)

```bash
for lg in $(aws logs describe-log-groups \
             --log-group-name-prefix "/aws/lambda/gnawlab-bkp" \
             --query 'logGroups[].logGroupName' --output text); do
  aws logs delete-log-group --log-group-name "$lg" || true
done

for k in $(aws kms list-aliases \
            --query "Aliases[?starts_with(AliasName, 'alias/gnawlab-bkp')].TargetKeyId" \
            --output text); do
  aws kms schedule-key-deletion --key-id "$k" --pending-window-in-days 7 || true
done

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

## Cost Verification

Check the *AWS Billing Console* → current month → these line items should
**stop** accruing within ~30 minutes after destroy completes:

- **Amazon Bedrock** — model invocations + Knowledge Base storage
- **OpenSearch Serverless** — OCU-hour
- **CloudFront** — request volume
- **AWS WAF** — web ACL hours

KMS keys remain in the `PendingDeletion` state for 7 days; they are
**not billable** during that window, but if you need to recreate the
scenario before then either pick a different `scenario_id` (a fresh
`terraform init` does this automatically) or `aws kms cancel-key-deletion`
the existing one.
