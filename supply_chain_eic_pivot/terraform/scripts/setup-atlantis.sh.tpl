#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/setup-atlantis.log) 2>&1

REGION="${region}"
GITLAB_PRIVATE_IP="${gitlab_private_ip}"
WEBHOOK_SECRET="${webhook_secret}"
SSM_TOKEN_PATH="${ssm_token_path}"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y curl unzip jq

ATLANTIS_VERSION=$(curl -sf https://api.github.com/repos/runatlantis/atlantis/releases/latest 2>/dev/null \
  | jq -r '.tag_name // "v0.28.3"' || echo "v0.28.3")

cd /tmp
curl -fsSL "https://github.com/runatlantis/atlantis/releases/download/$ATLANTIS_VERSION/atlantis_linux_amd64.zip" \
  -o atlantis.zip
unzip -q atlantis.zip
mv atlantis /usr/local/bin/atlantis
chmod +x /usr/local/bin/atlantis
rm atlantis.zip

useradd -m -s /bin/bash atlantis

# Install AWS CLI for SSM access
apt-get install -y awscli

echo "Waiting for GitLab service token to appear in SSM..."
MAX_ATTEMPTS=60
ATTEMPT=0
until aws ssm get-parameter --region "$REGION" --name "$SSM_TOKEN_PATH" --with-decryption > /dev/null 2>&1; do
  ATTEMPT=$((ATTEMPT + 1))
  if [ $ATTEMPT -ge $MAX_ATTEMPTS ]; then
    echo "ERROR: GitLab token not available in SSM after 30 minutes."
    exit 1
  fi
  echo "Waiting... ($ATTEMPT/$MAX_ATTEMPTS)"
  sleep 30
done

GITLAB_TOKEN=$(aws ssm get-parameter \
  --region "$REGION" \
  --name "$SSM_TOKEN_PATH" \
  --with-decryption \
  --query "Parameter.Value" \
  --output text)

cat > /etc/systemd/system/atlantis.service << UNIT
[Unit]
Description=Atlantis Terraform Pull Request Automation
After=network.target

[Service]
User=atlantis
ExecStart=/usr/local/bin/atlantis server \
  --gitlab-hostname=$GITLAB_PRIVATE_IP \
  --gitlab-token=$GITLAB_TOKEN \
  --gitlab-webhook-secret=$WEBHOOK_SECRET \
  --repo-allowlist=* \
  --port=4141
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable atlantis
systemctl start atlantis

echo "Atlantis setup complete. Listening on :4141"
