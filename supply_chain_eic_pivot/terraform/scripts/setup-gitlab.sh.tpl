#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/setup-gitlab.log) 2>&1

REGION="${region}"
ATLANTIS_PRIVATE_IP="${atlantis_private_ip}"
WEBHOOK_SECRET="${webhook_secret}"
SSM_TOKEN_PATH="${ssm_token_path}"

# Decode infra-repo files
echo "${main_tf_b64}" | base64 -d > /tmp/repo-main.tf
echo "${variables_tf_b64}" | base64 -d > /tmp/repo-variables.tf
echo "${atlantis_yaml_b64}" | base64 -d > /tmp/repo-atlantis.yaml

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y curl openssh-server ca-certificates tzdata perl jq awscli

curl -fsSL https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh | bash

PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
EXTERNAL_URL="http://$PUBLIC_IP" apt-get install -y gitlab-ce

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

ROOT_TOKEN=$(gitlab-rails runner "
  root = User.find_by(username: 'root')
  root.password = 'RootAdmin123!'
  root.password_confirmation = 'RootAdmin123!'
  root.save!
  token = PersonalAccessToken.create!(
    user: root,
    name: 'setup-token',
    scopes: ['api', 'sudo'],
    expires_at: 1.day.from_now
  )
  puts token.token
" 2>/dev/null | tail -1)

if [ -z "$ROOT_TOKEN" ] || [ "$ROOT_TOKEN" = "nil" ]; then
  echo "ERROR: Failed to obtain root API token."
  exit 1
fi

OPS_USER_ID=$(curl -sf -X POST "http://localhost/api/v4/users" \
  -H "PRIVATE-TOKEN: $ROOT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"username":"000_ops","name":"000_ops","email":"ops@beavercorp.internal","password":"BeaverPassword123!","skip_confirmation":true}' \
  | jq -r '.id')

PROJECT_ID=$(curl -sf -X POST "http://localhost/api/v4/projects" \
  -H "PRIVATE-TOKEN: $ROOT_TOKEN" \
  -H "SUDO: $OPS_USER_ID" \
  -H "Content-Type: application/json" \
  -d '{"name":"infra-repo","visibility":"private","initialize_with_readme":false}' \
  | jq -r '.id')

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
    -d "{\"branch\":\"main\",\"encoding\":\"base64\",\"content\":\"$content\",\"commit_message\":\"$message\"}"
}

push_file "main.tf"      /tmp/repo-main.tf      "Initial infrastructure setup"
push_file "variables.tf" /tmp/repo-variables.tf "Add variables"
push_file "atlantis.yaml" /tmp/repo-atlantis.yaml "Add Atlantis configuration"

ATLANTIS_TOKEN=$(curl -sf -X POST "http://localhost/api/v4/users/$OPS_USER_ID/personal_access_tokens" \
  -H "PRIVATE-TOKEN: $ROOT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"atlantis-service-token","scopes":["api","read_repository","write_repository"]}' \
  | jq -r '.token')

aws ssm put-parameter \
  --region "$REGION" \
  --name "$SSM_TOKEN_PATH" \
  --value "$ATLANTIS_TOKEN" \
  --type "SecureString" \
  --overwrite

curl -sf -X POST "http://localhost/api/v4/projects/$PROJECT_ID/hooks" \
  -H "PRIVATE-TOKEN: $ROOT_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"url\":\"http://$ATLANTIS_PRIVATE_IP:4141/events\",\"token\":\"$WEBHOOK_SECRET\",\"merge_requests_events\":true,\"push_events\":true,\"note_events\":true}"

echo "GitLab setup complete. URL: http://$PUBLIC_IP | User: 000_ops | Pass: BeaverPassword123!"
