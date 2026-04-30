# Metadata Pivot - Cleanup Guide

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

1. **EC2 Instance**
   - Go to [EC2 Console](https://console.aws.amazon.com/ec2/)
   - Search for instance containing `gnawlab-metapivot`
   - Terminate the instance

2. **S3 Bucket**
   - Go to [S3 Console](https://s3.console.aws.amazon.com/s3/)
   - Search for bucket containing `gnawlab-metapivot`
   - Empty the bucket first (select all objects → Delete)
   - Delete the bucket

3. **IAM Role and Instance Profile**
   - Go to [IAM Console → Roles](https://console.aws.amazon.com/iam/home#/roles)
   - Search for role containing `gnawlab-metapivot`
   - Delete inline policies first
   - Delete the role
   - Go to [IAM Console → Instance Profiles](https://console.aws.amazon.com/iam/home#/instance_profiles)
   - Delete the instance profile

4. **VPC Resources**
   - Go to [VPC Console](https://console.aws.amazon.com/vpc/)
   - Search for VPC containing `gnawlab-metapivot`
   - Delete in order: Security Group → Subnet → Route Table → Internet Gateway → VPC

### AWS CLI

```bash
# Set profile
export AWS_PROFILE=GnawLab
export AWS_REGION=us-east-1

# Find scenario ID from resource names
SCENARIO_ID="<your-8-char-scenario-id>"

# Terminate EC2 instance
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Scenario,Values=metadata-pivot" "Name=instance-state-name,Values=running,stopped" \
  --query "Reservations[].Instances[].InstanceId" --output text)
if [ -n "$INSTANCE_ID" ]; then
  aws ec2 terminate-instances --instance-ids $INSTANCE_ID
  echo "Waiting for instance termination..."
  aws ec2 wait instance-terminated --instance-ids $INSTANCE_ID
fi

# Delete S3 bucket
BUCKET=$(aws s3 ls | grep gnawlab-metapivot | awk '{print $3}')
if [ -n "$BUCKET" ]; then
  aws s3 rb s3://$BUCKET --force
fi

# Delete IAM resources
ROLE_NAME="gnawlab-metapivot-role-${SCENARIO_ID}"
PROFILE_NAME="gnawlab-metapivot-profile-${SCENARIO_ID}"

# Remove role from instance profile and delete
aws iam remove-role-from-instance-profile --instance-profile-name $PROFILE_NAME --role-name $ROLE_NAME 2>/dev/null
aws iam delete-instance-profile --instance-profile-name $PROFILE_NAME 2>/dev/null

# Delete inline policy and role
aws iam delete-role-policy --role-name $ROLE_NAME --policy-name "gnawlab-metapivot-policy-${SCENARIO_ID}" 2>/dev/null
aws iam delete-role --role-name $ROLE_NAME 2>/dev/null

# Delete VPC resources (get VPC ID first)
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Scenario,Values=metadata-pivot" --query "Vpcs[].VpcId" --output text)
if [ -n "$VPC_ID" ]; then
  # Delete security group
  SG_ID=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=gnawlab-metapivot-*" --query "SecurityGroups[].GroupId" --output text)
  aws ec2 delete-security-group --group-id $SG_ID 2>/dev/null
  
  # Delete subnet
  SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[].SubnetId" --output text)
  aws ec2 delete-subnet --subnet-id $SUBNET_ID 2>/dev/null
  
  # Delete route table (non-main)
  RT_ID=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" "Name=association.main,Values=false" --query "RouteTables[].RouteTableId" --output text)
  aws ec2 delete-route-table --route-table-id $RT_ID 2>/dev/null
  
  # Detach and delete internet gateway
  IGW_ID=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query "InternetGateways[].InternetGatewayId" --output text)
  aws ec2 detach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID 2>/dev/null
  aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID 2>/dev/null
  
  # Delete VPC
  aws ec2 delete-vpc --vpc-id $VPC_ID
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

## Remove Stolen Profile (Optional)

If you configured a `stolen` profile during the challenge:

```bash
# Edit ~/.aws/credentials and remove the [stolen] section
# Or use AWS CLI
aws configure --profile stolen set aws_access_key_id ""
aws configure --profile stolen set aws_secret_access_key ""
aws configure --profile stolen set aws_session_token ""
```

## Verify No Resources Remain

Check for remaining resources by tag:

```bash
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Scenario,Values=metadata-pivot \
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
3. Verify EC2 and S3 show minimal or no charges
