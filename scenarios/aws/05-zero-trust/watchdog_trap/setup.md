# Watchdog Trap - Setup

## Prerequisites

- AWS CLI configured with sufficient permissions
- Terraform >= 1.5.0
- git
- python3 (for URL encoding credentials during CodeCommit seeding)

## Deploy

```bash
cd terraform
terraform init
terraform apply -auto-approve
```

Terraform will provision the following resources:
- VPC with public, private, and tools subnets
- EC2 instances: `webapp` (internet-facing), `prowler` (internal), `steampipe` (internal)
- ALB, ECS Fargate service (`jsn-app`)
- CodePipeline, CodeBuild, CodeDeploy, CodeCommit (`jsn-config`), ECR
- S3 artifact bucket, CloudWatch Log Group (`/corp/deploy-pipeline`)
- Secrets Manager secret (FLAG)

## Seed CodeCommit Repository

After `terraform apply` completes, seed the initial files into the CodeCommit repository:

### 1. Retrieve outputs

```bash
cd terraform

CLONE_URL=$(terraform output -raw codecommit_clone_url_http)
GIT_USER=$(terraform output -raw dev_user_codecommit_username)
GIT_PASS=$(terraform output -raw dev_user_codecommit_password)
EXEC_ROLE_ARN=$(terraform output -raw ecs_task_execution_role_arn)
FLAG_SECRET_ARN=$(terraform output -raw flag_secret_arn)
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || aws configure get region)
PROJECT_NAME="jsn"
```

### 2. URL-encode credentials and clone

```bash
ENC_USER=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$GIT_USER")
ENC_PASS=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$GIT_PASS")

REPO_HOST="${CLONE_URL#https://}"
AUTH_URL="https://${ENC_USER}:${ENC_PASS}@${REPO_HOST}"

TMPDIR=$(mktemp -d)
git clone "$AUTH_URL" "$TMPDIR/jsn-config"
cd "$TMPDIR/jsn-config"
git checkout -b main 2>/dev/null || git checkout main
```

### 3. Copy seed files

```bash
SEED_DIR="<repo_root>/assets/seed"

# Copy Dockerfile as-is
cp "$SEED_DIR/Dockerfile" Dockerfile

# Substitute PROJECT_NAME in appspec.yml
sed "s/PROJECT_NAME/${PROJECT_NAME}/g" "$SEED_DIR/appspec.yml" > appspec.yml

# Substitute all placeholders in task-definition.json
sed \
  -e "s|PROJECT_NAME|${PROJECT_NAME}|g" \
  -e "s|EXEC_ROLE_ARN|${EXEC_ROLE_ARN}|g" \
  -e "s|FLAG_SECRET_ARN|${FLAG_SECRET_ARN}|g" \
  -e "s|AWS_REGION|${AWS_REGION}|g" \
  "$SEED_DIR/task-definition.json.tmpl" > task-definition.json
```

> The `task-definition.json` intentionally has **no** `command` field — participants must inject it to complete the scenario.

### 4. Commit and push

```bash
git config user.email "ops@jsn.internal"
git config user.name "JSN Ops"
git add -A
git commit -m "Initial commit: scenario seed files"
git push origin main
```

### 5. Trigger CodePipeline initial run

```bash
PIPELINE_NAME=$(terraform output -raw pipeline_name)
aws codepipeline start-pipeline-execution \
  --name "$PIPELINE_NAME" \
  --region "$AWS_REGION"
```

Wait approximately 5–10 minutes for the pipeline to complete and the ECS service to become healthy.

### 6. Verify CloudWatch credential log exists

```bash
aws logs filter-log-events \
  --log-group-name "/corp/deploy-pipeline" \
  --filter-pattern "git clone" \
  --region "$AWS_REGION" \
  --query 'length(events)' \
  --output text
```

The output should be greater than `0`. If not, check CodeBuild logs manually in the AWS Console.

## Starting Point

After deployment, provide participants with only:

- **Web Application URL**: `http://<webapp_ip>` (from `terraform output webapp_public_ip`)

## Verify

```bash
curl http://<webapp_ip>
```

Expected: HTML page for the JSN Incident Report Generator.
