# Hidden Track - Cleanup Guide

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

> **Note:** S3 buckets have `force_destroy = true` — all objects including
> versioned files and Delete Markers are removed automatically.
> GuardDuty Malware Protection plan is also destroyed.

### Step 3: Verify

```bash
terraform show
```

Expected: `No state.` or empty output.

## Manual Cleanup Checklist

If Terraform destroy fails, manually delete these resources:

### AWS Console

1. **S3 Buckets**
   - Go to [S3 Console](https://console.aws.amazon.com/s3/)
   - Search for buckets containing `beaversound`
   - Empty each bucket (including versions and delete markers)
   - Delete the buckets

2. **Lambda Function and Layer**
   - Go to [Lambda Console](https://console.aws.amazon.com/lambda/)
   - Search for function containing `beaversound-process-upload`
   - Delete the function
   - Under Layers, search for `beaversound-exiftool` and delete all versions

3. **EC2 Instance**
   - Go to [EC2 Console → Instances](https://console.aws.amazon.com/ec2/home#Instances)
   - Search for instances tagged `Scenario=hidden-track`
   - Terminate the instance

4. **IAM Roles**
   - Go to [IAM Console → Roles](https://console.aws.amazon.com/iam/home#/roles)
   - Search for roles containing `beaversound-`
   - Delete inline policies first, then delete the roles

5. **GuardDuty**
   - Go to [GuardDuty Console](https://console.aws.amazon.com/guardduty/)
   - Under S3 Protection → Malware Protection, delete the protection plan for the uploads bucket

6. **VPC**
   - Go to [VPC Console](https://console.aws.amazon.com/vpc/)
   - Search for VPC tagged `Scenario=hidden-track`
   - Delete security groups, subnets, route tables, internet gateway
   - Delete the VPC

### AWS CLI

```bash
export AWS_PROFILE=GnawLab
export AWS_REGION=us-east-1

# 1. Find and empty S3 buckets (including versions and delete markers)
for BUCKET in $(aws s3 ls | grep beaversound | awk '{print $3}'); do
  echo "Emptying $BUCKET ..."
  aws s3api delete-objects --bucket "$BUCKET" \
    --delete "$(aws s3api list-object-versions --bucket "$BUCKET" \
      --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
      --output json 2>/dev/null)" 2>/dev/null || true
  aws s3api delete-objects --bucket "$BUCKET" \
    --delete "$(aws s3api list-object-versions --bucket "$BUCKET" \
      --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
      --output json 2>/dev/null)" 2>/dev/null || true
  aws s3 rb "s3://$BUCKET" --force
done

# 2. Delete Lambda function and layer
LAMBDA=$(aws lambda list-functions \
  --query "Functions[?starts_with(FunctionName,'beaversound-process-upload')].FunctionName" \
  --output text)
[ -n "$LAMBDA" ] && aws lambda delete-function --function-name "$LAMBDA"

LAYER=$(aws lambda list-layers \
  --query "Layers[?starts_with(LayerName,'beaversound-exiftool')].LayerName" \
  --output text)
if [ -n "$LAYER" ]; then
  VERSION=$(aws lambda list-layer-versions --layer-name "$LAYER" \
    --query 'LayerVersions[0].Version' --output text)
  aws lambda delete-layer-version --layer-name "$LAYER" --version-number "$VERSION"
fi

# 3. Terminate EC2 instance
INSTANCE=$(aws ec2 describe-instances \
  --filters "Name=tag:Scenario,Values=hidden-track" "Name=instance-state-name,Values=running,stopped" \
  --query "Reservations[].Instances[].InstanceId" --output text)
if [ -n "$INSTANCE" ]; then
  aws ec2 terminate-instances --instance-ids "$INSTANCE"
  aws ec2 wait instance-terminated --instance-ids "$INSTANCE"
fi

# 4. Delete IAM roles (detach/delete policies first)
for ROLE in $(aws iam list-roles \
  --query "Roles[?starts_with(RoleName,'beaversound-')].RoleName" --output text); do
  for POLICY in $(aws iam list-role-policies --role-name "$ROLE" \
    --query 'PolicyNames[]' --output text); do
    aws iam delete-role-policy --role-name "$ROLE" --policy-name "$POLICY"
  done
  for PROFILE in $(aws iam list-instance-profiles-for-role --role-name "$ROLE" \
    --query 'InstanceProfiles[].InstanceProfileName' --output text); do
    aws iam remove-role-from-instance-profile --instance-profile-name "$PROFILE" --role-name "$ROLE"
    aws iam delete-instance-profile --instance-profile-name "$PROFILE"
  done
  aws iam delete-role --role-name "$ROLE"
done

# 5. Delete GuardDuty Malware Protection plans
for PLAN in $(aws guardduty list-malware-protection-plans \
  --query 'MalwareProtectionPlanIds[]' --output text 2>/dev/null); do
  aws guardduty delete-malware-protection-plan --malware-protection-plan-id "$PLAN"
done

# 6. Delete VPC resources
VPC=$(aws ec2 describe-vpcs --filters "Name=tag:Scenario,Values=hidden-track" \
  --query "Vpcs[0].VpcId" --output text)
if [ -n "$VPC" ] && [ "$VPC" != "None" ]; then
  SG=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC" \
    "Name=group-name,Values=gnawlab-beaversound-*" \
    --query "SecurityGroups[0].GroupId" --output text)
  [ -n "$SG" ] && aws ec2 delete-security-group --group-id "$SG" 2>/dev/null

  SUBNET=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC" \
    --query "Subnets[0].SubnetId" --output text)
  [ -n "$SUBNET" ] && aws ec2 delete-subnet --subnet-id "$SUBNET" 2>/dev/null

  RT=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC" \
    "Name=association.main,Values=false" --query "RouteTables[0].RouteTableId" --output text)
  [ -n "$RT" ] && aws ec2 delete-route-table --route-table-id "$RT" 2>/dev/null

  IGW=$(aws ec2 describe-internet-gateways \
    --filters "Name=attachment.vpc-id,Values=$VPC" \
    --query "InternetGateways[0].InternetGatewayId" --output text)
  if [ -n "$IGW" ] && [ "$IGW" != "None" ]; then
    aws ec2 detach-internet-gateway --internet-gateway-id "$IGW" --vpc-id "$VPC"
    aws ec2 delete-internet-gateway --internet-gateway-id "$IGW"
  fi

  aws ec2 delete-vpc --vpc-id "$VPC"
fi
```

## Remove Local Files

```bash
rm -f terraform/exiftool-layer.zip
rm -f terraform/lambda.zip
rm -rf terraform/.terraform
rm -f terraform/.terraform.lock.hcl
rm -f terraform/terraform.tfstate*
rm -f terraform/terraform.tfvars
rm -f assets/payloads/malicious.mp4
```

## Unset Stolen Credentials (Optional)

If you exported the stolen Lambda credentials as environment variables during the exercise, clear them:

```bash
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_SESSION_TOKEN
unset AWS_DEFAULT_REGION
unset VAULT_BUCKET
unset UPLOADS_BUCKET
```

## Verify No Resources Remain

```bash
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Scenario,Values=hidden-track \
  --region us-east-1 \
  --profile GnawLab \
  --query 'ResourceTagMappingList[].ResourceARN'
```

Expected:

```json
{
    "ResourceTagMappingList": []
}
```

## Cost Verification

Check your AWS billing to ensure no unexpected charges:

1. Go to [AWS Billing Console](https://console.aws.amazon.com/billing/)
2. Check "Bills" for current month
3. Verify EC2, Lambda, S3, and GuardDuty show minimal or no charges
