# Golden Drift - Cleanup Guide

## Before You Run Terraform Destroy

This scenario has two separate cleanup tracks:
1. **Your personal AWS account** — the malicious AMI and its EBS snapshot you created during the attack
2. **Target account** — all resources deployed by Terraform

Complete Step 1 first, otherwise the malicious AMI stays public indefinitely.

### Pre-Cleanup Checklist

**1. Deregister the malicious AMI and delete its snapshot (your personal account):**

```bash
# Run with your personal AWS account profile
export AWS_PROFILE=<your-personal-profile>

# Find the malicious AMI you registered
aws ec2 describe-images --owners self \
  --filters "Name=name,Values=gnawlab-golden-ticketing-*" \
  --query 'Images[*].[ImageId,Name,Public]' \
  --output table

# For each malicious AMI found:
# 1. Get the associated snapshot IDs
SNAPSHOT_IDS=$(aws ec2 describe-images --owners self \
  --filters "Name=name,Values=gnawlab-golden-ticketing-*" \
  --query 'Images[*].BlockDeviceMappings[*].Ebs.SnapshotId' \
  --output text)

# 2. Deregister the AMI (removes launch permission but keeps snapshot)
for AMI_ID in $(aws ec2 describe-images --owners self \
  --filters "Name=name,Values=gnawlab-golden-ticketing-*" \
  --query 'Images[*].ImageId' --output text); do
    aws ec2 deregister-image --image-id "$AMI_ID"
    echo "Deregistered: $AMI_ID"
done

# 3. Delete the underlying EBS snapshot(s)
for SNAP_ID in $SNAPSHOT_IDS; do
  aws ec2 delete-snapshot --snapshot-id "$SNAP_ID"
  echo "Deleted snapshot: $SNAP_ID"
done
```

**2. Terminate any temporary EC2 instances you launched in your personal account:**

```bash
# Check for running instances tagged for this scenario
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=whoami-ami-baker-*" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name,Tags[?Key==`Name`].Value|[0]]' \
  --output table

# Terminate if found
# aws ec2 terminate-instances --instance-ids <instance-id>
```

**3. Restore AMI Block Public Access in your personal account:**

```bash
aws ec2 enable-image-block-public-access \
  --image-block-public-access-state block-new-sharing \
  --region us-east-1
```

**4. Delete temporary SSH resources from your personal account:**

```bash
# Delete the temporary security group used for AMI baking
aws ec2 delete-security-group --group-name whoami-ami-baker-<scenario-id>

# Delete the EC2 key pair and local private key
aws ec2 delete-key-pair --key-name whoami-<scenario-id>
rm -f ~/whoami-<scenario-id>.pem
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

> **Note:** Destroy takes 2–5 minutes. The golden AMI and its source instance are also removed.

### Step 3: Verify Cleanup

```bash
terraform show
```

Should output: `No state.` or empty state.

---

## Manual Cleanup Checklist

If `terraform destroy` fails, manually delete these resources in order:

### AWS Console

1. **Auto Scaling Group**
   - Go to [EC2 Console → Auto Scaling Groups](https://console.aws.amazon.com/ec2/home#AutoScalingGroups)
   - Search for group containing `gnawlab-golden`
   - Set desired count to 0, wait for instances to terminate
   - Delete the group

2. **Application Load Balancer**
   - Go to [EC2 Console → Load Balancers](https://console.aws.amazon.com/ec2/home#LoadBalancers)
   - Search for ALB containing `gnawlab-golden`
   - Delete listener, then the load balancer, then the target group

3. **Lambda Function**
   - Go to [Lambda Console](https://console.aws.amazon.com/lambda/)
   - Search for function containing `gnawlab-golden-updater`
   - Delete the function and the CloudWatch log group

4. **Golden AMI and source instance**
   - Go to [EC2 Console → AMIs](https://console.aws.amazon.com/ec2/home#Images)
   - Search for AMI containing `gnawlab-golden-ticketing`
   - Deregister the AMI
   - Go to [Snapshots](https://console.aws.amazon.com/ec2/home#Snapshots) and delete the associated snapshot
   - Terminate the `ami-baker` EC2 instance

5. **SSM Parameter**
   - Go to [Systems Manager → Parameter Store](https://console.aws.amazon.com/systems-manager/parameters)
   - Search for `/gnawlab/golden/`
   - Delete the parameter

6. **Secrets Manager**
   - Go to [Secrets Manager Console](https://console.aws.amazon.com/secretsmanager/)
   - Search for secret containing `gnawlab-golden-flag`
   - Delete the secret (force delete without recovery window)

7. **IAM Resources**
   - Delete IAM User `gnawlab-golden-attacker-*` (and its access key + inline policy)
   - Delete IAM Role `gnawlab-golden-instance-role-*` (and its inline policy)
   - Delete IAM Role `gnawlab-golden-updater-role-*` (and its inline policy)
   - Delete IAM Instance Profile `gnawlab-golden-instance-profile-*`

8. **VPC**
   - Go to [VPC Console](https://console.aws.amazon.com/vpc/)
   - Search for VPC containing `gnawlab-golden`
   - Delete security groups, subnets, route tables, internet gateway, then the VPC

### AWS CLI

```bash
export AWS_PROFILE=GnawLab
export AWS_REGION=us-east-1

# Replace with the 8-character scenario suffix
SCENARIO_ID="<your-8-char-scenario-id>"

# Delete Lambda + EventBridge rule
aws events remove-targets --rule "gnawlab-golden-updater-schedule-${SCENARIO_ID}" --ids golden-updater-lambda
aws events delete-rule --name "gnawlab-golden-updater-schedule-${SCENARIO_ID}"
aws lambda delete-function --function-name "gnawlab-golden-updater-${SCENARIO_ID}"
aws logs delete-log-group --log-group-name "/aws/lambda/gnawlab-golden-updater-${SCENARIO_ID}"

# Delete SSM Parameter
aws ssm delete-parameter --name "/gnawlab/golden/${SCENARIO_ID}/golden-ami/web"

# Delete Secrets Manager secret (immediate, no recovery window)
aws secretsmanager delete-secret \
  --secret-id "gnawlab-golden-flag-${SCENARIO_ID}" \
  --force-delete-without-recovery
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

## Remove Attacker Profile (Optional)

Edit `~/.aws/credentials` and remove the `[attacker]` section:

```bash
# Or use AWS CLI
aws configure --profile attacker set aws_access_key_id ""
aws configure --profile attacker set aws_secret_access_key ""
```

---

## Verify No Resources Remain

Check for remaining resources by tag:

```bash
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Scenario,Values=golden-drift \
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

Check your AWS billing to ensure no unexpected charges:

1. Go to [AWS Billing Console](https://console.aws.amazon.com/billing/)
2. Check "Bills" for current month
3. Verify EC2, ALB, Lambda, and Secrets Manager show minimal or no charges
