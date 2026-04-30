# Watchdog Trap - Cleanup Guide

## Before You Run Terraform Destroy

This scenario uses ECS Blue/Green deployment via CodeDeploy. If you modified the task definition and triggered the pipeline, there may be active deployments or additional ECS tasks running. Complete the pre-cleanup steps below first.

### Pre-Cleanup Checklist

**1. Stop any active CodePipeline execution:**

```bash
PIPELINE_NAME=$(cd terraform && terraform output -raw pipeline_name)

aws codepipeline list-pipeline-executions \
  --pipeline-name "$PIPELINE_NAME" \
  --profile GnawLab --region us-east-1 \
  --query 'pipelineExecutionSummaries[?status==`InProgress`]'

# Stop in-progress execution if found
aws codepipeline stop-pipeline-execution \
  --pipeline-name "$PIPELINE_NAME" \
  --pipeline-execution-id <execution-id> \
  --abandon \
  --profile GnawLab --region us-east-1
```

**2. Delete all ECR images** (required before Terraform can destroy the ECR repo):

```bash
ECR_REPO=$(cd terraform && terraform output -raw ecr_repository_url | cut -d/ -f2)

aws ecr list-images --repository-name "$ECR_REPO" \
  --query 'imageIds[*]' --output json --profile GnawLab --region us-east-1 | \
aws ecr batch-delete-image \
  --repository-name "$ECR_REPO" \
  --image-ids file:///dev/stdin \
  --profile GnawLab --region us-east-1
```

**3. Empty S3 artifact bucket** (required before Terraform can destroy the bucket):

```bash
BUCKET=$(cd terraform && terraform output -raw s3_artifact_bucket)
aws s3 rm "s3://${BUCKET}" --recursive --profile GnawLab
aws s3api list-object-versions --bucket "$BUCKET" \
  --query 'Versions[*].{Key:Key,VersionId:VersionId}' --output json --profile GnawLab | \
  jq -c '.[]' | while read obj; do
    KEY=$(echo $obj | jq -r '.Key')
    VID=$(echo $obj | jq -r '.VersionId')
    aws s3api delete-object --bucket "$BUCKET" --key "$KEY" --version-id "$VID" --profile GnawLab
  done
```

**4. Close your reverse shell connection** (if still active):

```bash
exit
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

> **Note:** Destroy takes approximately **5–10 minutes**. ECS services must drain connections before deletion.

### Step 3: Verify Cleanup

```bash
terraform show
```

Should output: `No state.` or empty state.

---

## Manual Cleanup Checklist

If `terraform destroy` fails, manually delete these resources in order:

### AWS Console

1. **ECS Service**
   - Go to [ECS Console](https://console.aws.amazon.com/ecs/)
   - Find cluster containing `beaverdam`
   - Set desired count to 0, wait for tasks to stop
   - Delete the service, then the cluster

2. **CodeDeploy**
   - Go to [CodeDeploy Console](https://console.aws.amazon.com/codesuite/codedeploy/)
   - Find application containing `beaverdam`
   - Delete the deployment group first, then the application

3. **CodePipeline**
   - Go to [CodePipeline Console](https://console.aws.amazon.com/codesuite/codepipeline/)
   - Find pipeline containing `beaverdam`, delete it

4. **CodeBuild**
   - Go to [CodeBuild Console](https://console.aws.amazon.com/codesuite/codebuild/)
   - Find project containing `beaverdam`, delete it

5. **CodeCommit**
   - Go to [CodeCommit Console](https://console.aws.amazon.com/codesuite/codecommit/)
   - Find repository `beaverdam-config`, delete it

6. **ECR Repository**
   - Go to [ECR Console](https://console.aws.amazon.com/ecr/)
   - Find repository containing `beaverdam`
   - Delete all images first, then delete the repository

7. **Application Load Balancer**
   - Go to [EC2 Console → Load Balancers](https://console.aws.amazon.com/ec2/home#LoadBalancers)
   - Find ALB containing `beaverdam`
   - Delete listeners, then load balancer, then target groups

8. **EC2 Instances**
   - Go to [EC2 Console → Instances](https://console.aws.amazon.com/ec2/home#Instances)
   - Filter by tag `Name=*beaverdam*`
   - Terminate all 3 instances (webapp, prowler, steampipe)

9. **VPC**
   - Go to [VPC Console](https://console.aws.amazon.com/vpc/)
   - Find VPC containing `beaverdam`
   - Delete NAT Gateway first (wait for full deletion)
   - Release Elastic IPs
   - Delete subnets, route tables, internet gateway, then the VPC

10. **IAM Roles**
    - Go to [IAM Console → Roles](https://console.aws.amazon.com/iam/home#/roles)
    - Search for roles containing `beaverdam`
    - Delete inline/attached policies first, then the roles

11. **Secrets Manager**
    - Go to [Secrets Manager Console](https://console.aws.amazon.com/secretsmanager/)
    - Find secret containing `beaverdam`, force delete without recovery window

12. **S3 Bucket**
    - Go to [S3 Console](https://s3.console.aws.amazon.com/s3/)
    - Find bucket containing `beaverdam`
    - Empty the bucket first, then delete it

13. **CloudWatch Log Group**
    - Go to [CloudWatch Console → Log Groups](https://console.aws.amazon.com/cloudwatch/home#logsV2:log-groups)
    - Find `/corp/deploy-pipeline`, delete it

---

## Remove Local Files

```bash
rm -rf terraform/.terraform
rm -f terraform/.terraform.lock.hcl
rm -f terraform/terraform.tfstate*
rm -f terraform/terraform.tfvars
```

---

## Verify No Resources Remain

```bash
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Scenario,Values=beaverdam-watchdog-trap \
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

1. Go to [AWS Billing Console](https://console.aws.amazon.com/billing/)
2. Check "Bills" for current month
3. Verify EC2, ECS, CodePipeline, and NAT Gateway show minimal or no charges

> **Note:** NAT Gateway charges accrue per hour even when idle. Ensure it is deleted after the scenario.
