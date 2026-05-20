# Obfuscated Policy - Cleanup Guide

## Before You Run Terraform Destroy

This scenario allows participants to create customer-managed IAM policies via `iam:CreatePolicy`. These policies are **not tracked by Terraform** and will block `terraform destroy` from removing the attacker user (the user has policies still attached). Complete the pre-cleanup steps below first.

### Pre-Cleanup Checklist

**1. Detach and delete attacker-created customer-managed policies:**

```bash
# Resolve the attacker user name from Terraform output
USER_NAME=$(terraform -chdir=terraform output -json verification | jq -r '.user_arn' | awk -F/ '{print $NF}')
ACCOUNT_ID=$(aws sts get-caller-identity --profile GnawLab --query Account --output text)

# List currently attached customer-managed policies on the attacker user
aws iam list-attached-user-policies \
  --user-name "$USER_NAME" \
  --profile GnawLab

# Detach and delete every customer-managed policy attached to the user
for ARN in $(aws iam list-attached-user-policies \
  --user-name "$USER_NAME" --profile GnawLab \
  --query "AttachedPolicies[?starts_with(PolicyArn, 'arn:aws:iam::${ACCOUNT_ID}:policy/')].PolicyArn" \
  --output text); do
    aws iam detach-user-policy --user-name "$USER_NAME" --policy-arn "$ARN" --profile GnawLab
    aws iam delete-policy --policy-arn "$ARN" --profile GnawLab
done
```

**2. Delete any orphan customer-managed policies (created but never attached):**

```bash
# Delete by name. Ignored when the policy does not exist.
for NAME in naive-list naive-get list-bypass get-bypass; do
    aws iam delete-policy \
      --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${NAME}" \
      --profile GnawLab 2>/dev/null && echo "Deleted: ${NAME}"
done
```

---

## Automated Cleanup (Recommended)

### Step 1: Navigate to Terraform Directory

```bash
cd terraform
```

### Step 2: Destroy All Resources

```bash
terraform destroy
```

Type `yes` when prompted.

### Step 3: Verify Cleanup

```bash
terraform show
```

Should output: `No state.` or empty state.

---

## Manual Cleanup Checklist

If `terraform destroy` fails, manually delete these resources in order:

### AWS Console

1. **Customer-managed IAM Policies (attacker-created)**
   - Go to [IAM Console → Policies](https://console.aws.amazon.com/iam/home#/policies)
   - Filter: Customer managed
   - Detach from the attacker user, then delete every policy created during the challenge

2. **IAM User**
   - Go to [IAM Console → Users](https://console.aws.amazon.com/iam/home#/users)
   - Search for user containing `gnawlab-iampoly-attacker`
   - Delete access keys first
   - Detach the Permission Boundary
   - Delete inline policies, then delete the user

3. **IAM Permission Boundary policy**
   - Go to [IAM Console → Policies](https://console.aws.amazon.com/iam/home#/policies)
   - Search for policy containing `gnawlab-iampoly-boundary`, delete it

4. **Lambda Function**
   - Go to [Lambda Console](https://console.aws.amazon.com/lambda/)
   - Search for function containing `gnawlab-iampoly-detector`, delete it

5. **CloudWatch Log Group**
   - Go to [CloudWatch Console → Log groups](https://console.aws.amazon.com/cloudwatch/home#logsV2:log-groups)
   - Search for `/aws/lambda/gnawlab-iampoly-detector`, delete it

6. **EventBridge Rule**
   - Go to [EventBridge Console](https://console.aws.amazon.com/events/)
   - Search for rule containing `gnawlab-iampoly-rule`
   - Remove targets first, then delete the rule

7. **CloudTrail Trail**
   - Go to [CloudTrail Console](https://console.aws.amazon.com/cloudtrail/)
   - Search for trail containing `gnawlab-iampoly-trail`, delete it

8. **S3 Buckets**
   - Go to [S3 Console](https://s3.console.aws.amazon.com/s3/)
   - Search for buckets containing `gnawlab-iampoly`
   - Empty each bucket first, then delete

9. **IAM Role for the Detection Lambda**
   - Go to [IAM Console → Roles](https://console.aws.amazon.com/iam/home#/roles)
   - Search for role containing `gnawlab-iampoly-detector-role`
   - Delete inline policies and detach managed policies first
   - Delete the role

### AWS CLI

```bash
export AWS_PROFILE=GnawLab
export AWS_REGION=us-east-1

# Replace with the 8-character scenario suffix
SCENARIO_ID="<your-8-char-scenario-id>"

# Delete CloudTrail
aws cloudtrail delete-trail --name "gnawlab-iampoly-trail-${SCENARIO_ID}"

# Delete EventBridge rule (remove targets first)
aws events remove-targets --rule "gnawlab-iampoly-rule-${SCENARIO_ID}" --ids detector-lambda
aws events delete-rule --name "gnawlab-iampoly-rule-${SCENARIO_ID}"

# Delete Lambda + log group
aws lambda delete-function --function-name "gnawlab-iampoly-detector-${SCENARIO_ID}"
aws logs delete-log-group --log-group-name "/aws/lambda/gnawlab-iampoly-detector-${SCENARIO_ID}"

# Empty and delete S3 buckets
aws s3 rm "s3://gnawlab-iampoly-flag-${SCENARIO_ID}" --recursive
aws s3 rb "s3://gnawlab-iampoly-flag-${SCENARIO_ID}" --force
aws s3 rm "s3://gnawlab-iampoly-trail-${SCENARIO_ID}" --recursive
aws s3 rb "s3://gnawlab-iampoly-trail-${SCENARIO_ID}" --force
```

---

## Remove Local Files

```bash
# Remove Terraform state and cache
rm -rf terraform/.terraform
rm -f terraform/.terraform.lock.hcl
rm -f terraform/terraform.tfstate*

# Remove generated Lambda zip
rm -rf terraform/.build

# Remove tfvars if created
rm -f terraform/terraform.tfvars
```

---

## Verify No Resources Remain

Check for remaining resources by tag:

```bash
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Scenario,Values=obfuscated-policy \
  --region us-east-1 \
  --profile GnawLab
```

Should return an empty `ResourceTagMappingList`:

```json
{
    "ResourceTagMappingList": []
}
```

---

## Cost Verification

1. Go to [AWS Billing Console](https://console.aws.amazon.com/billing/)
2. Check "Bills" for current month
3. Verify Lambda, S3, CloudTrail, and EventBridge show minimal or no charges
