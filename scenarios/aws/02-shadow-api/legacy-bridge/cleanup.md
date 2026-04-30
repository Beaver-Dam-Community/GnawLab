# legacy-bridge - Cleanup Guide

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

1. **EC2 Instances**
   - Go to [EC2 Console](https://console.aws.amazon.com/ec2/)
   - Find instances `legacy-bridge-public-gateway` and `legacy-bridge-shadow-api`
   - Select both instances and terminate

2. **Security Groups**
   - Go to [EC2 Console → Security Groups](https://console.aws.amazon.com/ec2/home#SecurityGroups)
   - Search for groups containing `legacy-bridge`
   - Delete all security groups associated with legacy-bridge (except default)

3. **S3 Bucket**
   - Go to [S3 Console](https://console.aws.amazon.com/s3/)
   - Find bucket `prime-pii-vault-*`
   - Empty the bucket first, then delete it

4. **VPC**
   - Go to [VPC Console](https://console.aws.amazon.com/vpc/)
   - Search for VPC containing `legacy-bridge`
   - Delete subnets, route tables, internet gateway
   - Delete the VPC

5. **IAM Roles**
   - Go to [IAM Console → Roles](https://console.aws.amazon.com/iam/home#/roles)
   - Find roles `Gateway-App-Role` and `Shadow-API-Role`
   - Delete inline policies first
   - Delete the roles

6. **Elastic IPs**
   - Go to [EC2 Console → Elastic IPs](https://console.aws.amazon.com/ec2/home#Addresses)
   - Search for unassociated IPs from legacy-bridge
   - Release them

7. **Network Interfaces**
   - Go to [EC2 Console → Network Interfaces](https://console.aws.amazon.com/ec2/home#NetworkInterfaces)
   - Search for interfaces containing `legacy-bridge`
   - Delete any remaining interfaces

### AWS CLI

```bash
# Set profile
export AWS_PROFILE=GnawLab
export AWS_REGION=us-east-1

# Terminate EC2 instances
aws ec2 terminate-instances --instance-ids $(aws ec2 describe-instances \
  --filters "Name=tag:Scenario,Values=legacy-bridge" \
  --query 'Reservations[*].Instances[*].InstanceId' --output text)

# Delete security groups
aws ec2 describe-security-groups --filters "Name=tag:Scenario,Values=legacy-bridge" \
  --query 'SecurityGroups[*].GroupId' --output text | xargs -I {} \
  aws ec2 delete-security-group --group-id {}

# Empty and delete S3 bucket
aws s3 rm s3://prime-pii-vault-* --recursive
aws s3 rb s3://prime-pii-vault-*

# Delete IAM roles
aws iam delete-role-policy --role-name Gateway-App-Role --policy-name gateway-policy
aws iam delete-role --role-name Gateway-App-Role
aws iam delete-role-policy --role-name Shadow-API-Role --policy-name shadow-api-policy
aws iam delete-role --role-name Shadow-API-Role
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
  --tag-filters Key=Scenario,Values=legacy-bridge \
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
3. Verify EC2, S3, and VPC show minimal or no charges