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

---

## Manual Cleanup Checklist

If Terraform destroy fails, manually delete these resources **in order**:

### AWS Console

1. **EC2 Instances**
   - Go to [EC2 Console](https://console.aws.amazon.com/ec2/)
   - Search for instances containing `legacy-bridge`
   - Terminate both `Public-Gateway-Server` and `Shadow-API-Server`
   - Wait until both instances reach `terminated` state before proceeding

2. **NAT Gateway**
   - Go to [VPC Console → NAT Gateways](https://console.aws.amazon.com/vpc/home#NatGateways)
   - Search for NAT Gateway containing `legacy-bridge`
   - Delete it and wait until status changes to `deleted`

3. **Elastic IPs**
   - Go to [EC2 Console → Elastic IPs](https://console.aws.amazon.com/ec2/home#Addresses)
   - Search for EIPs tagged with `legacy-bridge`
   - Release them (must be done after NAT Gateway deletion)

4. **Security Groups**
   - Go to [EC2 Console → Security Groups](https://console.aws.amazon.com/ec2/home#SecurityGroups)
   - Search for groups containing `legacy-bridge`
   - Delete all associated security groups (except default)

5. **S3 Bucket**
   - Go to [S3 Console](https://console.aws.amazon.com/s3/)
   - Find bucket `legacy-bridge-pii-vault-<suffix>`
   - Empty the bucket first, then delete it

6. **VPC**
   - Go to [VPC Console](https://console.aws.amazon.com/vpc/)
   - Search for VPC containing `legacy-bridge`
   - Delete subnets, route tables, and internet gateway
   - Delete the VPC

7. **IAM Roles**
   - Go to [IAM Console → Roles](https://console.aws.amazon.com/iam/home#/roles)
   - Find roles containing `legacy-bridge`
   - For each role: detach managed policies → delete inline policies → delete instance profile → delete role
   - Target roles: `legacy-bridge-Gateway-App-Role-<suffix>`, `legacy-bridge-Shadow-API-Role-<suffix>`

### AWS CLI

```bash
# Set profile
export AWS_PROFILE=GnawLab
export AWS_REGION=us-east-1

# Terminate EC2 instances
aws ec2 terminate-instances --instance-ids $(aws ec2 describe-instances \
  --filters "Name=tag:Scenario,Values=legacy-bridge" \
  --query 'Reservations[*].Instances[*].InstanceId' --output text)

# Delete NAT Gateway (get ID first, then delete)
NGW_ID=$(aws ec2 describe-nat-gateways \
  --filter "Name=tag:Scenario,Values=legacy-bridge" \
  --query 'NatGateways[0].NatGatewayId' --output text)
aws ec2 delete-nat-gateway --nat-gateway-id ${NGW_ID}

# Release Elastic IPs
EIP_ALLOC=$(aws ec2 describe-addresses \
  --filters "Name=tag:Scenario,Values=legacy-bridge" \
  --query 'Addresses[*].AllocationId' --output text)
for alloc in ${EIP_ALLOC}; do
  aws ec2 release-address --allocation-id ${alloc}
done

# Empty and delete S3 bucket
BUCKET=$(aws s3api list-buckets \
  --query "Buckets[?starts_with(Name, 'legacy-bridge-pii-vault')].Name" \
  --output text)
aws s3 rm s3://${BUCKET} --recursive
aws s3 rb s3://${BUCKET}

# Delete IAM roles
SUFFIX="<your-8-char-suffix>"

# Gateway App Role
aws iam detach-role-policy \
  --role-name legacy-bridge-Gateway-App-Role-${SUFFIX} \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
aws iam remove-role-from-instance-profile \
  --instance-profile-name legacy-bridge-Gateway-App-Profile-${SUFFIX} \
  --role-name legacy-bridge-Gateway-App-Role-${SUFFIX}
aws iam delete-instance-profile \
  --instance-profile-name legacy-bridge-Gateway-App-Profile-${SUFFIX}
aws iam delete-role --role-name legacy-bridge-Gateway-App-Role-${SUFFIX}

# Shadow API Role
aws iam detach-role-policy \
  --role-name legacy-bridge-Shadow-API-Role-${SUFFIX} \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
aws iam delete-role-policy \
  --role-name legacy-bridge-Shadow-API-Role-${SUFFIX} \
  --policy-name legacy-bridge-shadow-api-s3-${SUFFIX}
aws iam remove-role-from-instance-profile \
  --instance-profile-name legacy-bridge-Shadow-API-Profile-${SUFFIX} \
  --role-name legacy-bridge-Shadow-API-Role-${SUFFIX}
aws iam delete-instance-profile \
  --instance-profile-name legacy-bridge-Shadow-API-Profile-${SUFFIX}
aws iam delete-role --role-name legacy-bridge-Shadow-API-Role-${SUFFIX}
```

---

## Remove Local Files

```bash
# Remove Terraform state and cache
rm -rf terraform/.terraform
rm -f terraform/.terraform.lock.hcl
rm -f terraform/terraform.tfstate*
# Remove tfvars if created
rm -f terraform/terraform.tfvars
```

---

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

---

## Cost Verification

Check your AWS billing to ensure no unexpected charges:

1. Go to [AWS Billing Console](https://console.aws.amazon.com/billing/)
2. Check "Bills" for current month
3. Verify EC2, NAT Gateway, S3, and VPC show minimal or no charges