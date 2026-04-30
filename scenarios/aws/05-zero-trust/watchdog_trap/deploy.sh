#!/bin/bash
# deploy.sh
# Watchdog Trap scenario deployment script
# Runs: terraform apply → CodeCommit seeding → pipeline trigger → print access info

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"
SEED_DIR="$SCRIPT_DIR/assets/seed"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()     { echo -e "${RED}[ERR]${NC}  $*" >&2; }

# ── 1. Prerequisites ──────────────────────────────────────────────────────────
info "Checking prerequisites..."
for cmd in terraform aws git python3; do
  if ! command -v "$cmd" &>/dev/null; then
    err "'$cmd' is not installed."
    exit 1
  fi
done
success "terraform / aws / git / python3 OK"

# ── 2. terraform.tfvars ───────────────────────────────────────────────────────
TFVARS="$TF_DIR/terraform.tfvars"
if [[ ! -f "$TFVARS" ]]; then
  AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
  if [[ -z "$AWS_REGION" ]]; then
    AWS_REGION="$(aws configure get region 2>/dev/null || true)"
  fi
  AWS_REGION="${AWS_REGION:-us-east-1}"

  cat > "$TFVARS" <<EOF
project_name = "beaverdam"
aws_region   = "$AWS_REGION"
EOF
  success "terraform.tfvars created: $TFVARS"
else
  info "Using existing terraform.tfvars: $TFVARS"
fi

AWS_REGION=$(grep 'aws_region' "$TFVARS" | sed 's/.*= *"\(.*\)".*/\1/')
PROJECT_NAME=$(grep 'project_name' "$TFVARS" | sed 's/.*= *"\(.*\)".*/\1/')

# ── 3. terraform init & apply ─────────────────────────────────────────────────
info "Running terraform init..."
cd "$TF_DIR"
terraform init -input=false

info "Running terraform apply..."
terraform apply -auto-approve -input=false
success "terraform apply complete"

# ── 4. CodeCommit seeding ─────────────────────────────────────────────────────
seed_codecommit() {
  info "Seeding CodeCommit repository..."

  CLONE_URL=$(terraform output -raw codecommit_clone_url_http)
  GIT_USER=$(terraform output -raw dev_user_codecommit_username)
  GIT_PASS=$(terraform output -raw dev_user_codecommit_password)
  EXEC_ROLE_ARN=$(terraform output -raw ecs_task_execution_role_arn)
  FLAG_SECRET_ARN=$(terraform output -raw flag_secret_arn)

  ENC_USER=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$GIT_USER")
  ENC_PASS=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$GIT_PASS")

  REPO_HOST="${CLONE_URL#https://}"
  AUTH_URL="https://${ENC_USER}:${ENC_PASS}@${REPO_HOST}"

  TMPDIR=$(mktemp -d)
  trap "rm -rf $TMPDIR" EXIT

  git clone "$AUTH_URL" "$TMPDIR/${PROJECT_NAME}-config"
  cd "$TMPDIR/${PROJECT_NAME}-config"

  git checkout -b main 2>/dev/null || git checkout main

  cp "$SEED_DIR/Dockerfile" Dockerfile

  sed "s/PROJECT_NAME/${PROJECT_NAME}/g" "$SEED_DIR/appspec.yml" > appspec.yml

  sed \
    -e "s|PROJECT_NAME|${PROJECT_NAME}|g" \
    -e "s|EXEC_ROLE_ARN|${EXEC_ROLE_ARN}|g" \
    -e "s|FLAG_SECRET_ARN|${FLAG_SECRET_ARN}|g" \
    -e "s|AWS_REGION|${AWS_REGION}|g" \
    "$SEED_DIR/task-definition.json.tmpl" > task-definition.json

  git config user.email "ops@beaverdam.internal"
  git config user.name "BeaverDam Ops"
  git add -A
  if git diff --cached --quiet; then
    info "No changes to seed files"
  else
    git commit -m "Initial commit: scenario seed files"
    git push origin main
  fi
  cd "$TF_DIR"

  success "CodeCommit seeding complete (Dockerfile, appspec.yml, task-definition.json)"
}

seed_codecommit

# ── 5. Trigger initial CodePipeline run ───────────────────────────────────────
info "Triggering initial CodePipeline run..."
PIPELINE_NAME=$(terraform output -raw pipeline_name)
EXECUTION_ID=$(aws codepipeline start-pipeline-execution \
  --name "$PIPELINE_NAME" \
  --region "$AWS_REGION" \
  --query 'pipelineExecutionId' \
  --output text)

# ── 6. Wait for pipeline completion ───────────────────────────────────────────
info "Waiting for pipeline to complete (up to 15 min)..."
for i in $(seq 1 90); do
  STATUS=$(aws codepipeline get-pipeline-execution \
    --pipeline-name "$PIPELINE_NAME" \
    --pipeline-execution-id "$EXECUTION_ID" \
    --region "$AWS_REGION" \
    --query 'pipelineExecution.status' \
    --output text 2>/dev/null || echo "Unknown")

  if [[ "$STATUS" == "Succeeded" ]]; then
    success "Pipeline succeeded"
    break
  elif [[ "$STATUS" == "Failed" ]] || [[ "$STATUS" == "Stopped" ]]; then
    err "Pipeline failed (status=$STATUS). Check CodePipeline logs in AWS Console."
    exit 1
  fi

  echo -n "."
  sleep 10
done
echo ""

# ── 7. Print access info ──────────────────────────────────────────────────────
WEBAPP_IP=$(terraform output -raw webapp_public_ip)

echo ""
echo "======================================================"
echo -e " ${GREEN}Deployment complete${NC}"
echo "======================================================"
echo ""
echo "  Provide participants with:"
echo "  BeaverDam Incident Report Generator: http://${WEBAPP_IP}"
echo ""
echo "  To destroy: cd terraform && terraform destroy -auto-approve"
echo "======================================================"
