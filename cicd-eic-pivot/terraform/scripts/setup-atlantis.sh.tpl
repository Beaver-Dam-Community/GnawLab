#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/setup-atlantis.log) 2>&1

REGION="${region}"
GITLAB_PRIVATE_IP="${gitlab_private_ip}"
WEBHOOK_SECRET="${webhook_secret}"
SSM_TOKEN_PATH="${ssm_token_path}"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y curl unzip jq awscli

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

echo "Waiting for GitLab service token in SSM (skipping placeholder value)..."
MAX_ATTEMPTS=60
ATTEMPT=0
GITLAB_TOKEN=""
until [ -n "$GITLAB_TOKEN" ] && [ "$GITLAB_TOKEN" != "placeholder" ]; do
  GITLAB_TOKEN=$(aws ssm get-parameter \
    --region "$REGION" \
    --name "$SSM_TOKEN_PATH" \
    --with-decryption \
    --query "Parameter.Value" \
    --output text 2>/dev/null || echo "")
  if [ -z "$GITLAB_TOKEN" ] || [ "$GITLAB_TOKEN" = "placeholder" ]; then
    ATTEMPT=$((ATTEMPT + 1))
    if [ $ATTEMPT -ge $MAX_ATTEMPTS ]; then
      echo "ERROR: GitLab token not available in SSM after 30 minutes."
      exit 1
    fi
    echo "Waiting for real token... ($ATTEMPT/$MAX_ATTEMPTS)"
    GITLAB_TOKEN=""
    sleep 30
  fi
done
echo "Got GitLab token from SSM."

# Resolve GitLab public IP and add /etc/hosts entry to avoid hairpin NAT.
# Atlantis clones repos using the public IP returned by the GitLab API, but
# AWS instances cannot reach their own public IPs internally.
GITLAB_PUBLIC_IP=$(aws ec2 describe-instances \
  --region "$REGION" \
  --filters "Name=private-ip-address,Values=$GITLAB_PRIVATE_IP" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text 2>/dev/null || echo "")

if [ -n "$GITLAB_PUBLIC_IP" ] && [ "$GITLAB_PUBLIC_IP" != "None" ]; then
  # git insteadOf does not match credential-embedded URLs (http://user:token@host/).
  # Use iptables DNAT to redirect at the network level instead.
  iptables -t nat -A OUTPUT -d $GITLAB_PUBLIC_IP -p tcp --dport 80 -j DNAT --to-destination $GITLAB_PRIVATE_IP:80
  echo "Hairpin NAT iptables redirect applied: $GITLAB_PUBLIC_IP:80 -> $GITLAB_PRIVATE_IP:80"
fi

cat > /etc/atlantis-repos.yaml << 'REPOCONF'
repos:
- id: /.*/
  allowed_overrides: [apply_requirements, workflow]
  allow_custom_workflows: true
REPOCONF

cat > /etc/systemd/system/atlantis.service << UNIT
[Unit]
Description=Atlantis Terraform Pull Request Automation
After=network.target

[Service]
User=atlantis
ExecStart=/usr/local/bin/atlantis server \
  --gitlab-hostname=http://$GITLAB_PRIVATE_IP \
  --gitlab-user=000_ops \
  --gitlab-token=$GITLAB_TOKEN \
  --gitlab-webhook-secret=$WEBHOOK_SECRET \
  --repo-allowlist=* \
  --repo-config=/etc/atlantis-repos.yaml \
  --default-tf-version=1.5.7 \
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
