# Obfuscated Policy - Cleanup Guide

> **Security Note**: Use placeholders for all AWS Account IDs, Access Keys, and Secret Keys.
> - Account ID: `123456789012`
> - Access Key: `AKIAIOSFODNN7EXAMPLE` or `ASIAXXXXXXXXXXX`
> - Secret Key: `xxxxxxxx` or mask actual values

## Automated Cleanup (Recommended)

### Step 1: Detach and Delete Manually-Created Policies

During the scenario you created customer-managed policies and attached them to the attacker user. Detach and delete them before running `terraform destroy`:

```bash
# Set the attacker user name from Terraform output
USER_NAME=$(terraform -chdir=terraform output -json verification | jq -r '.user_arn' | awk -F/ '{print $NF}')
ACCOUNT_ID=$(aws sts get-caller-identity --profile GnawLab --query Account --output text)

# List attached customer-managed policies
aws iam list-attached-user-policies \
  --user-name "$USER_NAME" \
  --profile GnawLab

# For each non-AWS-managed policy, detach and delete
for ARN in $(aws iam list-attached-user-policies \
  --user-name "$USER_NAME" --profile GnawLab \
  --query "AttachedPolicies[?starts_with(PolicyArn, 'arn:aws:iam::${ACCOUNT_ID}:policy/')].PolicyArn" \
  --output text); do
    aws iam detach-user-policy --user-name "$USER_NAME" --policy-arn "$ARN" --profile GnawLab
    aws iam delete-policy --policy-arn "$ARN" --profile GnawLab
done
```

### Step 2: Navigate to Terraform Directory

```bash
cd terraform
```

### Step 3: Destroy All Resources

```bash
terraform destroy
```

Type `yes` when prompted.

### Step 4: Verify Cleanup

```bash
terraform show
```

Should output `No state.` or empty state.

## Manual Cleanup Checklist

If `terraform destroy` fails, manually delete the following resources:

- [ ] Customer-managed IAM policies created by the attacker (any policy outside the Terraform state)
- [ ] IAM User and access key
- [ ] S3 buckets (flag bucket and CloudTrail log bucket - empty them first)
- [ ] CloudTrail trail
- [ ] EventBridge rule
- [ ] Lambda function and CloudWatch log group
- [ ] IAM role for the Lambda

### AWS CLI Manual Steps

```bash
export AWS_PROFILE=GnawLab
export AWS_REGION=us-east-1

# Find the scenario ID (8-char suffix on resource names)
SCENARIO_ID="<your-8-char-scenario-id>"

# Delete CloudTrail
aws cloudtrail delete-trail --name "gnawlab-iampoly-trail-${SCENARIO_ID}"

# Delete EventBridge rule and target
aws events remove-targets --rule "gnawlab-iampoly-rule-${SCENARIO_ID}" --ids detector-lambda
aws events delete-rule --name "gnawlab-iampoly-rule-${SCENARIO_ID}"

# Delete Lambda
aws lambda delete-function --function-name "gnawlab-iampoly-detector-${SCENARIO_ID}"

# Empty and delete S3 buckets
aws s3 rm "s3://gnawlab-iampoly-flag-${SCENARIO_ID}" --recursive
aws s3 rb "s3://gnawlab-iampoly-flag-${SCENARIO_ID}" --force
aws s3 rm "s3://gnawlab-iampoly-trail-${SCENARIO_ID}" --recursive
aws s3 rb "s3://gnawlab-iampoly-trail-${SCENARIO_ID}" --force
```

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

## Cost Verification

1. Go to [AWS Billing Console](https://console.aws.amazon.com/billing/)
2. Check current month bills for: Lambda, S3, CloudTrail, EventBridge
3. Confirm minimal or zero charges remain
