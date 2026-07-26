#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/setup-gitlab.log) 2>&1

REGION="${region}"
ATLANTIS_PRIVATE_IP="${atlantis_private_ip}"
WEBHOOK_SECRET="${webhook_secret}"
SSM_TOKEN_PATH="${ssm_token_path}"
SETUP_BUCKET="${setup_bucket}"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y curl openssh-server ca-certificates tzdata perl jq awscli

# Download infra-repo seed files from S3
aws s3 cp --region "$REGION" "s3://$SETUP_BUCKET/infra-repo/main.tf" /tmp/repo-main.tf
aws s3 cp --region "$REGION" "s3://$SETUP_BUCKET/infra-repo/variables.tf" /tmp/repo-variables.tf
aws s3 cp --region "$REGION" "s3://$SETUP_BUCKET/infra-repo/atlantis.yaml" /tmp/repo-atlantis.yaml
aws s3 cp --region "$REGION" "s3://$SETUP_BUCKET/infra-repo/SECURITY_REVIEW.md" /tmp/repo-security-review.md
aws s3 cp --region "$REGION" "s3://$SETUP_BUCKET/infra-repo/docs/adr/0003-deploy-pipeline.md" /tmp/repo-adr-deploy.md
aws s3 cp --region "$REGION" "s3://$SETUP_BUCKET/infra-repo/docs/slack-2024-03.txt" /tmp/repo-slack.txt
aws s3 cp --region "$REGION" "s3://$SETUP_BUCKET/infra-repo/README.md" /tmp/repo-readme.md
aws s3 cp --region "$REGION" "s3://$SETUP_BUCKET/infra-repo/docs/incident-2024-02.md" /tmp/repo-incident.md
aws s3 cp --region "$REGION" "s3://$SETUP_BUCKET/infra-repo/.env.example" /tmp/repo-env-example

curl -fsSL https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh | bash

IMDS_TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
  "http://169.254.169.254/latest/meta-data/public-ipv4")
PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
  "http://169.254.169.254/latest/meta-data/local-ipv4")
# Use private IP for external_url so Atlantis webhook validation matches --gitlab-hostname
EXTERNAL_URL="http://$PRIVATE_IP" apt-get install -y gitlab-ce

echo "Waiting for GitLab to initialize (this can take up to 15 minutes)..."
MAX_ATTEMPTS=80
ATTEMPT=0
until curl -sf http://localhost/-/health > /dev/null 2>&1; do
  ATTEMPT=$((ATTEMPT + 1))
  if [ $ATTEMPT -ge $MAX_ATTEMPTS ]; then
    echo "ERROR: GitLab did not become healthy within 20 minutes."
    exit 1
  fi
  echo "Waiting... ($ATTEMPT/$MAX_ATTEMPTS)"
  sleep 15
done
# Extra stabilization time after health check passes
sleep 60

echo "GitLab is ready. Running initial configuration..."

# Create root PAT using Rails runner.
# Use symbol array for scopes and skip password change to avoid validation errors.
ROOT_TOKEN=$(gitlab-rails runner "
  token = User.find_by(username: 'root').personal_access_tokens.create!(
    name: 'setup-token',
    scopes: [:api, :sudo],
    expires_at: 30.days.from_now
  )
  puts token.token
" 2>&1 | grep '^glpat-' | tail -1)

if [ -z "$ROOT_TOKEN" ]; then
  echo "ERROR: Failed to obtain root API token."
  exit 1
fi
echo "Root token obtained."

# Allow webhooks to internal/private network addresses (required for Atlantis)
curl -sf -X PUT "http://localhost/api/v4/application/settings" \
  -H "PRIVATE-TOKEN: $ROOT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"allow_local_requests_from_web_hooks_and_services":true,"signup_enabled":false}' > /dev/null

OPS_USER_ID=$(curl -sf -X POST "http://localhost/api/v4/users" \
  -H "PRIVATE-TOKEN: $ROOT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"username":"platform","name":"platform","email":"ops@beavercorp.internal","password":"BvrOps@2024","skip_confirmation":true}' \
  | jq -r '.id')
echo "Created platform user (id: $OPS_USER_ID)."

PROJECT_ID=$(curl -sf -X POST "http://localhost/api/v4/projects" \
  -H "PRIVATE-TOKEN: $ROOT_TOKEN" \
  -H "SUDO: $OPS_USER_ID" \
  -H "Content-Type: application/json" \
  -d '{"name":"infra-repo","visibility":"private","initialize_with_readme":false}' \
  | jq -r '.id')
echo "Created infra-repo (id: $PROJECT_ID)."

push_file() {
  local filename=$1
  local filepath=$2
  local message=$3
  local content
  content=$(base64 -w0 < "$filepath")
  curl -sf -X POST "http://localhost/api/v4/projects/$PROJECT_ID/repository/files/$filename" \
    -H "PRIVATE-TOKEN: $ROOT_TOKEN" \
    -H "SUDO: $OPS_USER_ID" \
    -H "Content-Type: application/json" \
    -d "{\"branch\":\"main\",\"encoding\":\"base64\",\"content\":\"$content\",\"commit_message\":\"$message\"}" > /dev/null
  echo "Pushed $filename."
}

push_file "main.tf"             /tmp/repo-main.tf             "feat: S3 storage + EIC deploy trigger - interim solution while migrating to GitOps (PLAT-1203)"
push_file "variables.tf"        /tmp/repo-variables.tf        "feat: add infrastructure input variables"
push_file "atlantis.yaml"       /tmp/repo-atlantis.yaml       "chore: configure Atlantis autoplan - enable auto-plan on MR for velocity"
push_file "SECURITY_REVIEW.md"  /tmp/repo-security-review.md  "docs: Q1 2024 security review - autoplan code execution risk + SendSSHPublicKey scope (PLAT-1203)"
push_file "docs%2Fadr%2F0003-deploy-pipeline.md"  /tmp/repo-adr-deploy.md  "docs: ADR-0003 EIC deploy mechanism - accepted interim with known tradeoffs (PLAT-1203)"
push_file "docs%2Fslack-2024-03.txt"             /tmp/repo-slack.txt     "chore: archive Q1 2024 platform-infra channel notes"
push_file "README.md"                            /tmp/repo-readme.md     "docs: add infrastructure repository README"
push_file "docs%2Fincident-2024-02.md"           /tmp/repo-incident.md   "docs: add incident report 2024-02 - SSH key leak prompted EIC adoption"
push_file ".env.example"                         /tmp/repo-env-example   "chore: add environment variables example file"

ATLANTIS_TOKEN=$(curl -sf -X POST "http://localhost/api/v4/users/$OPS_USER_ID/personal_access_tokens" \
  -H "PRIVATE-TOKEN: $ROOT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"atlantis-service-token","scopes":["api","read_repository","write_repository"]}' \
  | jq -r '.token')
echo "Created Atlantis service token."

aws ssm put-parameter \
  --region "$REGION" \
  --name "$SSM_TOKEN_PATH" \
  --value "$ATLANTIS_TOKEN" \
  --type "SecureString" \
  --overwrite
echo "Stored Atlantis token in SSM."

curl -sf -X POST "http://localhost/api/v4/projects/$PROJECT_ID/hooks" \
  -H "PRIVATE-TOKEN: $ROOT_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"url\":\"http://$ATLANTIS_PRIVATE_IP:4141/events\",\"token\":\"$WEBHOOK_SECRET\",\"merge_requests_events\":true,\"push_events\":true,\"note_events\":true}" > /dev/null
echo "Registered Atlantis webhook."

curl -sf -X PUT "http://localhost/api/v4/projects/$PROJECT_ID" \
  -H "PRIVATE-TOKEN: $ROOT_TOKEN" \
  -H "SUDO: $OPS_USER_ID" \
  -H "Content-Type: application/json" \
  -d '{"description":"Managed infrastructure for BeaverOps prod. EIC deploy via Atlantis. Migration tracked in PLAT-1203."}' > /dev/null
echo "Set repo description."

curl -sf -X DELETE "http://localhost/api/v4/personal_access_tokens/self" \
  -H "PRIVATE-TOKEN: $ROOT_TOKEN" > /dev/null 2>&1 || true
echo "Root setup token revoked."

chmod 600 /var/log/setup-gitlab.log

echo "GitLab setup complete. URL: http://$PUBLIC_IP | User: platform | Pass: BvrOps@2024"
