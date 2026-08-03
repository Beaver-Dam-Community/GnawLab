#!/bin/bash
set -euo pipefail
exec > /var/log/vulnboard-bootstrap.log 2>&1

echo "[bootstrap] start $(date -Is)"

dnf update -y
dnf install -y docker
systemctl enable --now docker

# Pre-pull the grading sandbox image so the first submission is responsive.
for i in 1 2 3 4 5; do
  if docker pull python:3.11-slim; then
    break
  fi
  echo "[bootstrap] python image pull attempt $i failed, retrying"
  sleep 5
done

mkdir -p /opt/vulnboard

cat > /opt/vulnboard/app.py <<'VULNBOARD_APP_EOF'
${app_py}
VULNBOARD_APP_EOF

cat > /opt/vulnboard/Dockerfile <<'VULNBOARD_DOCKERFILE_EOF'
${dockerfile}
VULNBOARD_DOCKERFILE_EOF

cat > /opt/vulnboard/docker-compose.yml <<'VULNBOARD_COMPOSE_EOF'
${compose}
VULNBOARD_COMPOSE_EOF

cd /opt/vulnboard
docker build -t vulnboard:latest .

docker rm -f vulnboard 2>/dev/null || true
docker run -d \
  --name vulnboard \
  --restart unless-stopped \
  -p 8080:5000 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /opt/vulnboard/docker-compose.yml:/srv/docker-compose.yml:ro \
  vulnboard:latest

echo "[bootstrap] done $(date -Is)"
