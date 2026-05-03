# S3 Data Heist - Cleanup Guide

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

1. **S3 Bucket**
   - Go to [S3 Console](https://s3.console.aws.amazon.com/s3/)
   - Search for bucket containing `gnawlab-s3heist`
   - Empty the bucket first (select all objects → Delete)
   - Delete the bucket

2. **IAM User**
   - Go to [IAM Console → Users](https://console.aws.amazon.com/iam/home#/users)
   - Search for user containing `gnawlab-s3heist`
   - Delete access keys first (Security credentials tab)
   - Delete inline policies (Permissions tab)
   - Delete the user

### AWS CLI

```bash
# Set profile
export AWS_PROFILE=GnawLab

# Find and delete S3 bucket
BUCKET=$(aws s3 ls | grep gnawlab-s3heist | awk '{print $3}')
if [ -n "$BUCKET" ]; then
  echo "Deleting bucket: $BUCKET"
  aws s3 rb s3://$BUCKET --force
fi

# Find and delete IAM user
USER=$(aws iam list-users --query "Users[?contains(UserName, 'gnawlab-s3heist')].UserName" --output text)
if [ -n "$USER" ]; then
  echo "Deleting user: $USER"
  
  # Delete access keys
  for KEY in $(aws iam list-access-keys --user-name $USER --query 'AccessKeyMetadata[].AccessKeyId' --output text); do
    aws iam delete-access-key --user-name $USER --access-key-id $KEY
  done
  
  # Delete inline policies
  for POLICY in $(aws iam list-user-policies --user-name $USER --query 'PolicyNames[]' --output text); do
    aws iam delete-user-policy --user-name $USER --policy-name $POLICY
  done
  
  # Delete user
  aws iam delete-user --user-name $USER
fi
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

## Remove Victim Profile (Optional)

Edit `~/.aws/credentials` and remove the `[victim]` section:

```bash
# Or use AWS CLI
aws configure --profile victim set aws_access_key_id ""
aws configure --profile victim set aws_secret_access_key ""
```

## Verify No Resources Remain

Check for remaining resources by tag:

```bash
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Scenario,Values=s3-data-heist \
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
3. Verify S3 and IAM show minimal or no charges
