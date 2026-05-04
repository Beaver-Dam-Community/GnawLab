# EBS Snapshot Theft - Cleanup Guide

## Step 1: Clean Up Attacker-Created Resources (IMPORTANT)

**You MUST delete resources you created during the challenge BEFORE running terraform destroy.** Otherwise, terraform cannot delete the VPC because your EC2 instance is still using it.

### Using AWS CLI

```bash
# Switch to victim profile
export AWS_PROFILE=victim

# 1. List all EC2 instances you created (non-terminated)
echo "=== Your EC2 Instances ==="
aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[].Instances[].[InstanceId,State.Name,Tags[?Key==`Name`].Value|[0]]' \
  --output table

# Terminate instances (replace with your instance IDs)
# aws ec2 terminate-instances --instance-ids <your-instance-id>
# aws ec2 wait instance-terminated --instance-ids <your-instance-id>

# 2. List all available EBS volumes (not attached)
echo "=== Your EBS Volumes ==="
aws ec2 describe-volumes \
  --filters "Name=status,Values=available" \
  --query 'Volumes[].[VolumeId,Size,Tags[?Key==`Name`].Value|[0]]' \
  --output table

# Delete volumes (replace with your volume IDs)
# aws ec2 delete-volume --volume-id <your-volume-id>

# 3. List all key pairs
echo "=== Your Key Pairs ==="
aws ec2 describe-key-pairs \
  --query 'KeyPairs[].[KeyName,KeyPairId]' \
  --output table

# Delete key pairs you created (replace with your key name)
# aws ec2 delete-key-pair --key-name <your-key-name>

# 4. Remove local SSH key files you created
# rm -f ~/.ssh/<your-key-name>.pem
```

### Using AWS Console

1. **EC2 Instances**: Go to [EC2 Console](https://console.aws.amazon.com/ec2/) → Instances → Terminate any instances you created
2. **EBS Volumes**: Go to Volumes → Delete any volumes you created (must be "available" state)
3. **Key Pairs**: Go to Key Pairs → Delete any key pairs you created

---

## Step 2: Automated Cleanup (Terraform)

### Navigate to Terraform Directory

```bash
cd terraform
```

### Destroy All Resources

```bash
terraform destroy
```

Type `yes` when prompted.

### Verify Cleanup

```bash
terraform show
```

Should output: `No state.` or empty state.

---

## Step 3: Manual Cleanup (If Terraform Fails)

If Terraform destroy fails, manually delete these resources:

### AWS Console

1. **EC2 Instances (if any remain)**
   - Go to [EC2 Console](https://console.aws.amazon.com/ec2/)
   - Search for instances containing `gnawlab-ebstheft`
   - Terminate all matching instances

2. **EBS Volumes**
   - Go to [EC2 Console → Volumes](https://console.aws.amazon.com/ec2/home#Volumes)
   - Search for volumes containing `gnawlab-ebstheft`
   - Detach if attached, then delete

3. **EBS Snapshots**
   - Go to [EC2 Console → Snapshots](https://console.aws.amazon.com/ec2/home#Snapshots)
   - Search for snapshots containing `gnawlab-ebstheft`
   - Delete the snapshots

4. **Key Pairs**
   - Go to [EC2 Console → Key Pairs](https://console.aws.amazon.com/ec2/home#KeyPairs)
   - Search for key pairs containing `gnawlab-ebstheft`
   - Delete the key pairs

5. **Security Groups**
   - Go to [EC2 Console → Security Groups](https://console.aws.amazon.com/ec2/home#SecurityGroups)
   - Search for groups containing `gnawlab-ebstheft`
   - Delete the security groups

6. **VPC**
   - Go to [VPC Console](https://console.aws.amazon.com/vpc/)
   - Search for VPC containing `gnawlab-ebstheft`
   - Delete subnets, route tables, internet gateway
   - Delete the VPC

7. **IAM User**
   - Go to [IAM Console → Users](https://console.aws.amazon.com/iam/home#/users)
   - Search for user containing `gnawlab-ebstheft`
   - Delete access keys first (Security credentials tab)
   - Delete inline policies (Permissions tab)
   - Delete the user

### AWS CLI

```bash
# Set profile
export AWS_PROFILE=GnawLab
export AWS_REGION=us-east-1

# Find scenario ID from resource names
SCENARIO_ID="<your-8-char-scenario-id>"

# Terminate any remaining EC2 instances
aws ec2 describe-instances \
  --filters "Name=tag:ScenarioID,Values=${SCENARIO_ID}" \
  --query 'Reservations[].Instances[].InstanceId' --output text | \
  xargs -r aws ec2 terminate-instances --instance-ids

# Delete snapshots
aws ec2 describe-snapshots \
  --filters "Name=tag:ScenarioID,Values=${SCENARIO_ID}" \
  --query 'Snapshots[].SnapshotId' --output text | \
  xargs -r -n1 aws ec2 delete-snapshot --snapshot-id

# Delete volumes
aws ec2 describe-volumes \
  --filters "Name=tag:ScenarioID,Values=${SCENARIO_ID}" \
  --query 'Volumes[].VolumeId' --output text | \
  xargs -r -n1 aws ec2 delete-volume --volume-id

# Delete key pairs
aws ec2 describe-key-pairs \
  --filters "Name=tag:ScenarioID,Values=${SCENARIO_ID}" \
  --query 'KeyPairs[].KeyPairId' --output text | \
  xargs -r -n1 aws ec2 delete-key-pair --key-pair-id

# Delete IAM user
USER=$(aws iam list-users --query "Users[?contains(UserName, 'gnawlab-ebstheft')].UserName" --output text)
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

---

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
  --tag-filters Key=Scenario,Values=ebs-snapshot-theft \
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
3. Verify EC2, EBS show minimal or no charges
