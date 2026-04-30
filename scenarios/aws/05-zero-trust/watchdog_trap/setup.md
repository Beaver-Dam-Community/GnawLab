# Watchdog Trap - Setup Guide

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.5.0
- [AWS CLI](https://aws.amazon.com/cli/) v2
- [Git](https://git-scm.com/)
- [Python 3](https://www.python.org/)
- AWS Account with admin access
- AWS credentials configured (default profile or environment variables)

---

## Option 1: Automated Setup (Recommended)

Run the deployment script from the scenario root directory:

```bash
chmod +x deploy.sh
./deploy.sh
```

The script handles terraform apply, CodeCommit seeding, pipeline trigger, and prints the participant URL when complete. Deployment takes approximately **15–20 minutes**.

When finished:
```
======================================================
 Deployment complete
======================================================

  Provide participants with:
  BeaverDam Incident Report Generator: http://<WEBAPP_IP>

  To destroy: cd terraform && terraform destroy -auto-approve
======================================================
```

---

## Option 2: Manual Setup

### Step 1: Configure AWS Credentials

```bash
aws configure
```

Verify:

```bash
aws sts get-caller-identity
```

### Step 2: Navigate to Terraform Directory

```bash
cd terraform
```

### Step 3: Initialize Terraform

```bash
terraform init
```

### Step 4: Review the Plan

```bash
terraform plan
```

Resources that will be created:
- 1 VPC with 6 subnets (2 public, 2 private, 2 tools)
- 3 EC2 Instances (webapp, prowler, steampipe)
- 1 Application Load Balancer (Blue/Green target)
- 1 ECS Cluster, Task Definition, and Service
- 2 IAM Roles (ECS Execution Role, Task Role)
- 1 CodePipeline (Source → Build → Deploy)
- 1 CodeBuild project
- 1 CodeDeploy application + deployment group
- 1 CodeCommit repository (`gnawlab-watchdog-config-<id>`)
- 1 ECR repository
- 1 S3 bucket (pipeline artifacts)
- 1 CloudWatch Log Group (`/corp/deploy-pipeline-<id>`)
- 1 Secrets Manager secret (FLAG)

### Step 5: Deploy the Scenario

```bash
terraform apply
```

Type `yes` when prompted.

> **Note:** Deployment takes approximately **10–15 minutes**. EC2 instances configure themselves via user data, then CodePipeline runs an initial build to push a Docker image to ECR before the ECS service starts.

### Step 6: Seed the CodeCommit Repository

After `terraform apply` completes, seed the initial files into the CodeCommit repository:

#### 6.1 Retrieve Terraform Outputs

```bash
CLONE_URL=$(terraform output -raw codecommit_clone_url_http)
GIT_USER=$(terraform output -raw dev_user_codecommit_username)
GIT_PASS=$(terraform output -raw dev_user_codecommit_password)
EXEC_ROLE_ARN=$(terraform output -raw ecs_task_execution_role_arn)
FLAG_SECRET_ARN=$(terraform output -raw flag_secret_arn)
LOG_GROUP_NAME=$(terraform output -raw log_group_name)
AWS_REGION="us-east-1"
PROJECT_NAME="beaverdam"
```

#### 6.2 Clone and Seed

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

#### 6.3 Copy Seed Files

```bash
SEED_DIR="<repo_root>/scenarios/aws/05-zero-trust/watchdog_trap/assets/seed"

cp "$SEED_DIR/Dockerfile" Dockerfile
sed "s/PROJECT_NAME/${PROJECT_NAME}/g" "$SEED_DIR/appspec.yml" > appspec.yml
sed \
  -e "s|PROJECT_NAME|${PROJECT_NAME}|g" \
  -e "s|EXEC_ROLE_ARN|${EXEC_ROLE_ARN}|g" \
  -e "s|FLAG_SECRET_ARN|${FLAG_SECRET_ARN}|g" \
  -e "s|AWS_REGION|${AWS_REGION}|g" \
  -e "s|LOG_GROUP_NAME|${LOG_GROUP_NAME}|g" \
  "$SEED_DIR/task-definition.json.tmpl" > task-definition.json
```

> The `task-definition.json` intentionally has **no** `command` field — participants must inject it to complete the scenario.

#### 6.4 Commit and Push

```bash
git config user.email "ops@beaverdam.internal"
git config user.name "BeaverDam Ops"
git add -A
git commit -m "Initial commit: scenario seed files"
git push origin main
```

#### 6.5 Trigger Initial Pipeline Run

```bash
PIPELINE_NAME=$(terraform output -raw pipeline_name)
aws codepipeline start-pipeline-execution \
  --name "$PIPELINE_NAME" \
  --region "$AWS_REGION"
```

Wait approximately **5–10 minutes** for the pipeline to complete and the ECS service to become healthy.

### Step 7: Get the Web Application URL

```bash
terraform output webapp_public_ip
```

### Step 8: Start the Challenge

Provide participants with only:
- **Web Application URL**: `http://<webapp-public-ip>`

See [walkthrough.md](./walkthrough.md) if you need hints.

---

## Troubleshooting

### Web application not loading

EC2 user data takes 3–5 minutes to complete. If still unavailable after 10 minutes:

```bash
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=*beaverdam*webapp*" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text --region us-east-1)

aws ec2 describe-instance-status \
  --instance-ids $INSTANCE_ID \
  --region us-east-1
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

---

## Cost Estimate

- EC2 t3.micro/small × 3 (webapp, prowler, steampipe): ~$0.03–0.05/hour each
- ECS Fargate (0.25 vCPU, 0.5 GB): ~$0.01/hour
- Application Load Balancer: ~$0.02/hour
- CodePipeline: ~$1.00/month
- Secrets Manager: ~$0.40/month
- NAT Gateway: ~$0.05/hour

**Estimated cost: ~$0.20–0.30/hour**

Always run `terraform destroy` when finished to avoid unexpected charges.
