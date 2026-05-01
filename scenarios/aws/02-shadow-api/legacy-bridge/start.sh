set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$HERE/terraform"

cd "$TF_DIR"

if [[ ! -f terraform.tfvars ]]; then
  echo "[legacy-bridge] terraform.tfvars not found - copying example..."
  cp terraform.tfvars.example terraform.tfvars
fi

echo "[legacy-bridge] terraform init..."
terraform init -input=false

echo "[legacy-bridge] terraform apply..."
terraform apply -input=false -auto-approve

echo
echo "[legacy-bridge] Scenario ready. Hand the participant:"
terraform output -raw scenario_entrypoint_url
echo