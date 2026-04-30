# Watchdog Trap - Setup Guide

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.5.0
- [AWS CLI](https://aws.amazon.com/cli/) v2
- [Git](https://git-scm.com/) (for the CodeCommit exploitation step)
- [Python 3](https://www.python.org/) (for URL-encoding credentials during CodeCommit seeding)
- AWS Account with admin access (for resource creation)
- AWS CLI profile `GnawLab` configured with admin credentials

## Step 1: Configure AWS CLI Profile

If you haven't already, configure the `GnawLab` profile with your admin credentials:

```bash
aws configure --profile GnawLab
```

Enter your admin credentials:
- AWS Access Key ID: `<your-admin-access-key>`
- AWS Secret Access Key: `<your-admin-secret-key>`
- Default region name: `us-east-1`
- Default output format: `json`

Verify the profile works:

```bash
aws sts get-caller-identity --profile GnawLab
```

## Step 2: Navigate to Terraform Directory

```bash
cd terraform
```

## Step 3: Initialize Terraform

```bash
terraform init
```

## Step 4: Review the Plan

```bash
terraform plan
```

Review the resources that will be created:
- 1 VPC with 6 subnets (2 public, 2 private, 2 tools)
- 3 EC2 Instances (webapp, prowler, steampipe)
- 1 Application Load Balancer (Blue/Green target)
- 1 ECS Cluster, Task Definition, and Service
- 2 IAM Roles (ECS Execution Role, Task Role)
- 1 CodePipeline (Source → Build → Deploy)
- 1 CodeBuild project
- 1 CodeDeploy application + deployment group
- 1 CodeCommit repository (`beaverdam-config`)
- 1 ECR repository
- 1 S3 bucket (pipeline artifacts)
- 1 CloudWatch Log Group (`/corp/deploy-pipeline`)
- 1 Secrets Manager secret (FLAG)

## Step 5: Deploy the Scenario

```bash
terraform apply
```

Type `yes` when prompted.

> **Note:** Deployment takes approximately **10–15 minutes**. EC2 instances configure themselves via user data, then CodePipeline runs an initial build to push a Docker image to ECR before the ECS service starts.

## Step 6: Seed the CodeCommit Repository

After `terraform apply` completes, seed the initial files into the CodeCommit repository:

### 6.1 Retrieve Terraform Outputs

```bash
CLONE_URL=$(terraform output -raw codecommit_clone_url_http)
GIT_USER=$(terraform output -raw dev_user_codecommit_username)
GIT_PASS=$(terraform output -raw dev_user_codecommit_password)
EXEC_ROLE_ARN=$(terraform output -raw ecs_task_execution_role_arn)
FLAG_SECRET_ARN=$(terraform output -raw flag_secret_arn)
AWS_REGION="us-east-1"
PROJECT_NAME="beaverdam"
```

### 6.2 Clone and Seed

```bash
ENC_USER=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$GIT_USER")
ENC_PASS=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$GIT_PASS")

REPO_HOST="${CLONE_URL#https://}"
AUTH_URL="https://${ENC_USER}:${ENC_PASS}@${REPO_HOST}"

TMPDIR=$(mktemp -d)
git clone "$AUTH_URL" "$TMPDIR/beaverdam-config"
cd "$TMPDIR/beaverdam-config"
git checkout -b main 2>/dev/null || git checkout main
```

### 6.3 Copy Seed Files

```bash
SEED_DIR="<repo_root>/assets/seed"

cp "$SEED_DIR/Dockerfile" Dockerfile
sed "s/PROJECT_NAME/${PROJECT_NAME}/g" "$SEED_DIR/appspec.yml" > appspec.yml
sed \
  -e "s|PROJECT_NAME|${PROJECT_NAME}|g" \
  -e "s|EXEC_ROLE_ARN|${EXEC_ROLE_ARN}|g" \
  -e "s|FLAG_SECRET_ARN|${FLAG_SECRET_ARN}|g" \
  -e "s|AWS_REGION|${AWS_REGION}|g" \
  "$SEED_DIR/task-definition.json.tmpl" > task-definition.json
```

> The `task-definition.json` intentionally has **no** `command` field — participants must inject it to complete the scenario.

### 6.4 Commit and Push

```bash
git config user.email "ops@beaverdam.internal"
git config user.name "BeaverDam Ops"
git add -A
git commit -m "Initial commit: scenario seed files"
git push origin main
```

### 6.5 Trigger Initial Pipeline Run

```bash
PIPELINE_NAME=$(terraform output -raw pipeline_name)
aws codepipeline start-pipeline-execution \
  --name "$PIPELINE_NAME" \
  --region "$AWS_REGION" \
  --profile GnawLab
```

Wait approximately **5–10 minutes** for the pipeline to complete and the ECS service to become healthy.

### 6.6 Verify CloudWatch Credential Log Exists

```bash
aws logs filter-log-events \
  --log-group-name "/corp/deploy-pipeline" \
  --filter-pattern "Cloning https" \
  --region "$AWS_REGION" \
  --profile GnawLab \
  --query 'length(events)' \
  --output text
```

Output should be greater than `0`. If not, check CodeBuild logs in the AWS Console.

## Step 7: Get the Web Application URL

```bash
terraform output webapp_url
```

Example output:
```
"http://34.192.221.168"
```

## Step 8: Start the Challenge!

Provide participants with only:
- **Web Application URL**: `http://<webapp-public-ip>`

See [walkthrough.md](./walkthrough.md) if you need hints.

## Troubleshooting

### Web application not loading

EC2 user data takes 3–5 minutes to complete. If still unavailable after 10 minutes:

```bash
# Get webapp instance ID
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=*beaverdam*webapp*" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text --profile GnawLab --region us-east-1)

aws ec2 describe-instance-status \
  --instance-ids $INSTANCE_ID \
  --profile GnawLab --region us-east-1
```

### Prowler or Steampipe not responding

These instances take 5–10 minutes to install dependencies on first boot. If still unavailable after 10 minutes:

```bash
terraform apply -replace=module.ec2.aws_instance.steampipe
```

### CloudWatch credential log not found

The initial CodeBuild run must complete successfully for the log to appear. Check CodeBuild project logs in the AWS Console under the `beaverdam-build` project.

### Terraform state issues

```bash
terraform refresh
```

## Cost Estimate

This scenario uses:
- EC2 t3.micro/small × 3 (webapp, prowler, steampipe): ~$0.03–0.05/hour each
- ECS Fargate (0.25 vCPU, 0.5 GB): ~$0.01/hour
- Application Load Balancer: ~$0.02/hour
- CodePipeline: ~$1.00/month
- Secrets Manager: ~$0.40/month
- NAT Gateway: ~$0.05/hour

**Estimated cost: ~$0.20–0.30/hour**

Always run `terraform destroy` when finished to avoid unexpected charges.
