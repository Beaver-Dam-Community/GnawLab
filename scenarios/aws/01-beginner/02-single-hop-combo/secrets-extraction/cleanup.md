# Secrets Extraction - Cleanup Guide

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

1. **ECS Service**
   - Go to [ECS Console](https://console.aws.amazon.com/ecs/)
   - Find cluster containing `gnawlab-secrets`
   - Delete the service first (set desired count to 0)
   - Delete the cluster

2. **Application Load Balancer**
   - Go to [EC2 Console → Load Balancers](https://console.aws.amazon.com/ec2/home#LoadBalancers)
   - Search for ALB containing `gnawlab-secrets`
   - Delete listeners first
   - Delete the load balancer
   - Delete the target group

3. **Security Groups**
   - Go to [EC2 Console → Security Groups](https://console.aws.amazon.com/ec2/home#SecurityGroups)
   - Search for groups containing `gnawlab-secrets`
   - Delete ECS security group first, then ALB security group

4. **VPC**
   - Go to [VPC Console](https://console.aws.amazon.com/vpc/)
   - Search for VPC containing `gnawlab-secrets`
   - Delete subnets, route tables, internet gateway
   - Delete the VPC

5. **IAM Roles**
   - Go to [IAM Console → Roles](https://console.aws.amazon.com/iam/home#/roles)
   - Search for roles containing `gnawlab-secrets`
   - Delete inline policies first
   - Delete the roles

6. **Secrets Manager**
   - Go to [Secrets Manager Console](https://console.aws.amazon.com/secretsmanager/)
   - Search for secret containing `gnawlab-secrets`
   - Delete the secret (force delete without recovery)

7. **KMS Key**
   - Go to [KMS Console](https://console.aws.amazon.com/kms/)
   - Search for key containing `gnawlab-secrets`
   - Schedule key deletion (minimum 7 days)

### AWS CLI

```bash
# Set profile
export AWS_PROFILE=GnawLab
export AWS_REGION=us-east-1

# Find scenario ID from resource names
SCENARIO_ID="<your-8-char-scenario-id>"

# Delete ECS service and cluster
aws ecs update-service --cluster gnawlab-secrets-cluster-${SCENARIO_ID} \
  --service gnawlab-secrets-service-${SCENARIO_ID} --desired-count 0
aws ecs delete-service --cluster gnawlab-secrets-cluster-${SCENARIO_ID} \
  --service gnawlab-secrets-service-${SCENARIO_ID} --force
aws ecs delete-cluster --cluster gnawlab-secrets-cluster-${SCENARIO_ID}

# Delete ALB
ALB_ARN=$(aws elbv2 describe-load-balancers --names gnawlab-secrets-alb-${SCENARIO_ID} \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text)
aws elbv2 delete-load-balancer --load-balancer-arn ${ALB_ARN}

# Delete Secrets Manager secret
aws secretsmanager delete-secret --secret-id gnawlab-secrets-flag-${SCENARIO_ID} \
  --force-delete-without-recovery
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
  --tag-filters Key=Scenario,Values=secrets-extraction \
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
3. Verify ECS, ALB, and Secrets Manager show minimal or no charges
