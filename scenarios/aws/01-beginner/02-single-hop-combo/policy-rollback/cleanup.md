# Policy Rollback - Cleanup Guide

## Important: Policy Version Cleanup

This scenario creates additional IAM policy versions using AWS CLI (via null_resource). These versions are **NOT automatically destroyed** by `terraform destroy`.

**You MUST delete the extra policy versions manually before running terraform destroy.**

## Step 1: Get Policy ARN

```bash
cd terraform
terraform output -json verification | jq -r '.policy_arn'
```

## Step 2: List Policy Versions

```bash
POLICY_ARN=$(terraform output -json verification | jq -r '.policy_arn')

aws iam list-policy-versions \
  --policy-arn $POLICY_ARN \
  --profile GnawLab
```

## Step 3: Delete Non-Default Policy Versions

Delete v2 and v3 (keep v1 as it's the default):

```bash
aws iam delete-policy-version \
  --policy-arn $POLICY_ARN \
  --version-id v3 \
  --profile GnawLab

aws iam delete-policy-version \
  --policy-arn $POLICY_ARN \
  --version-id v2 \
  --profile GnawLab
```

> **Note:** If you rolled back to v3 during the challenge, you need to set v1 as default first:
> ```bash
> aws iam set-default-policy-version \
>   --policy-arn $POLICY_ARN \
>   --version-id v1 \
>   --profile GnawLab
> ```

## Step 4: Destroy Terraform Resources

```bash
terraform destroy
```

Type `yes` when prompted.

## Step 5: Verify Cleanup

```bash
terraform show
```

Should output: `No state.` or empty state.

## Manual Cleanup Checklist

If Terraform destroy fails, manually delete these resources:

### AWS Console

1. **IAM User**
   - Go to [IAM Console → Users](https://console.aws.amazon.com/iam/home#/users)
   - Search for user containing `gnawlab-rollback`
   - Delete access keys first
   - Delete the user

2. **IAM Policy**
   - Go to [IAM Console → Policies](https://console.aws.amazon.com/iam/home#/policies)
   - Search for policy containing `gnawlab-rollback`
   - Delete all non-default versions first
   - Delete the policy

3. **Secrets Manager**
   - Go to [Secrets Manager Console](https://console.aws.amazon.com/secretsmanager/)
   - Search for secret containing `gnawlab-rollback`
   - Delete the secret (force delete without recovery)

### AWS CLI

```bash
# Set profile
export AWS_PROFILE=GnawLab
export AWS_REGION=us-east-1

# Find scenario ID from resource names
SCENARIO_ID="<your-8-char-scenario-id>"

# Delete IAM access key and user
aws iam delete-access-key --user-name gnawlab-rollback-user-${SCENARIO_ID} \
  --access-key-id <access-key-id>
aws iam detach-user-policy --user-name gnawlab-rollback-user-${SCENARIO_ID} \
  --policy-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/gnawlab/gnawlab-rollback-policy-${SCENARIO_ID}
aws iam delete-user --user-name gnawlab-rollback-user-${SCENARIO_ID}

# Delete policy versions then policy
aws iam delete-policy-version --policy-arn <policy-arn> --version-id v3
aws iam delete-policy-version --policy-arn <policy-arn> --version-id v2
aws iam delete-policy --policy-arn <policy-arn>

# Delete Secrets Manager secret
aws secretsmanager delete-secret --secret-id gnawlab-rollback-secret-${SCENARIO_ID} \
  --force-delete-without-recovery
```

## Remove Local Files

```bash
# Remove Terraform state and cache
rm -rf terraform/.terraform
rm -f terraform/.terraform.lock.hcl
rm -f terraform/terraform.tfstate*

# Remove tfvars if created
rm -f terraform/terraform.tfvars
```

## Verify No Resources Remain

Check for remaining resources by tag:

```bash
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Scenario,Values=policy-rollback \
  --region us-east-1 \
  --profile GnawLab
```

Should return empty `ResourceTagMappingList`:

```json
{
    "ResourceTagMappingList": []
}
```
