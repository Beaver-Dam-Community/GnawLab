# {{Scenario Name}} - Cleanup Guide

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

## Manual Cleanup Checklist

If Terraform destroy fails, manually delete these resources:

### AWS Console

<!-- List resources in deletion order -->

1. **Resource Type 1**
   - Go to [Console Link](https://console.aws.amazon.com/...)
   - Search for resources containing `gnawlab-{{scenario}}`
   - Delete dependencies first
   - Delete the resource

2. **Resource Type 2**
   - ...

### AWS CLI

```bash
# Set profile
export AWS_PROFILE=GnawLab
export AWS_REGION=us-east-1

# Find scenario ID from resource names
SCENARIO_ID="<your-8-char-scenario-id>"

# Delete resources (scenario-specific commands)
# ...
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

## Remove Challenge Profile (Optional)

If you configured a profile during the challenge (e.g., `victim`, `stolen`):

```bash
# Edit ~/.aws/credentials and remove the profile section
# Or clear the values
aws configure --profile <profile_name> set aws_access_key_id ""
aws configure --profile <profile_name> set aws_secret_access_key ""
aws configure --profile <profile_name> set aws_session_token ""
```

## Verify No Resources Remain

Check for remaining resources by tag:

```bash
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Scenario,Values={{scenario-tag}} \
  --region us-east-1 \
  --profile GnawLab
```

Should return empty `ResourceTagMappingList`:

```json
{
    "ResourceTagMappingList": []
}
```

## Cost Verification

Check your AWS billing to ensure no unexpected charges:

1. Go to [AWS Billing Console](https://console.aws.amazon.com/billing/)
2. Check "Bills" for current month
3. Verify relevant services show minimal or no charges
