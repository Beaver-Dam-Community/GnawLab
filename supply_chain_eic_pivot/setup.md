# supply_chain_eic_pivot — Setup

## Prerequisites

- AWS CLI configured with credentials that have sufficient permissions to create EC2, VPC, IAM, and SSM resources
- Terraform >= 1.5.0 installed
- Your public IP address (for `cg_whitelist`)

## Deploy the Scenario

```bash
cd terraform
terraform init
terraform plan -var='cg_whitelist=["<YOUR_PUBLIC_IP>/32"]'
terraform apply -var='cg_whitelist=["<YOUR_PUBLIC_IP>/32"]'
```

To find your public IP:

```bash
curl -s https://checkip.amazonaws.com
```

## Deployment Timeline

| Time | Event |
|---|---|
| 0 min | Terraform finishes — all EC2 instances are running |
| ~1 min | Bastion and Target Server are fully configured |
| ~5 min | Atlantis service starts polling SSM for GitLab token |
| ~10–15 min | GitLab CE finishes initializing |
| ~15–20 min | Atlantis connects to GitLab — scenario is fully ready |

> **Note:** GitLab CE installation is the bottleneck. Wait until you can access the GitLab UI in your browser before starting.

## Starting Credentials

After deployment, your starting credentials are automatically written to:

```
assets/gitlab_credentials.txt
```

You can also retrieve the GitLab URL from Terraform outputs:

```bash
terraform output gitlab_server_url
terraform output instructions
```

## Verify the Scenario is Ready

1. Open the GitLab URL in your browser — the login page should appear
2. Log in as `000_ops` with password `BeaverPassword123!`
3. Confirm `infra-repo` exists and contains `main.tf`, `variables.tf`, and `atlantis.yaml`
4. Confirm Atlantis webhook is registered: `infra-repo → Settings → Webhooks`

---

You are now ready to begin. See [README.md](./README.md) for scenario details.
