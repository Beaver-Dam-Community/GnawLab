# Contributing to GnawLab

Thank you for your interest in contributing to GnawLab!

## How to Contribute

- **Report bugs / Request features**: Open an issue
- **Add new scenarios**: Submit a Pull Request

## Adding a New Scenario

### 1. Use Templates

Copy templates from `scenarios/_templates/`:

```bash
cp scenarios/_templates/README.template.md scenarios/aws/01-beginner/access-key/single-hop/your-scenario/README.md
cp scenarios/_templates/walkthrough.template.md scenarios/aws/01-beginner/access-key/single-hop/your-scenario/walkthrough.md
cp scenarios/_templates/setup.template.md scenarios/aws/01-beginner/access-key/single-hop/your-scenario/setup.md
cp scenarios/_templates/cleanup.template.md scenarios/aws/01-beginner/access-key/single-hop/your-scenario/cleanup.md
```

### 2. Follow Directory Structure

```
your-scenario/
├── README.md
├── walkthrough.md
├── manifest.yaml
└── terraform/
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    └── provider.tf
```

### 3. Test Your Scenario

```bash
cd your-scenario/terraform
terraform init
terraform plan
terraform apply
# verify scenario works
terraform destroy
```

### 4. Terraform Requirements

#### IP Whitelist (for network-accessible scenarios only)

**When is IP whitelist required?**

Ask: "Can an attacker on the internet directly reach any resource in this scenario?"

- **YES** (EC2 with public IP, ALB, API Gateway, etc.) → IP whitelist REQUIRED
- **NO** (IAM-only, Secrets Manager, EBS snapshots, etc.) → IP whitelist NOT required

**If required, include these files** (see `s3-data-heist/terraform/` for reference):

```hcl
# variables.tf
variable "whitelist_ip" {
  description = "IP address to whitelist (CIDR). Leave empty to auto-detect."
  type        = string
  default     = ""
}

# data.tf
data "http" "my_ip" {
  url = "https://ifconfig.co/ip"
}

# locals.tf
locals {
  whitelist_cidr = var.whitelist_ip != "" ? var.whitelist_ip : "${chomp(data.http.my_ip.response_body)}/32"
}
```

Use `local.whitelist_cidr` in security groups and bucket policies for access control.

## Scenario Guidelines

- All content must be in **English**
- Difficulty levels: `Easy`, `Medium`, `Hard`, `Expert`
- Include real-world reference with source
- `Learning Objectives` section: only for `01-beginner` category

## Security Guidelines

### Placeholder Rules
- AWS Account ID: `123456789012` (AWS official example)
- Access Key ID: `AKIAIOSFODNN7EXAMPLE` or `AKIAXXXXXXXXXXXXXXXX`
- Secret Access Key: `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` or `xxxxxxxx`
- Session Token: `xxxxxxxx...` or mask actual values

### Generic Content Rule
- All documentation must be generic and reusable
- Do NOT include user-specific data (e.g., other buckets in your account, unrelated resources, personal resource names)
- Command outputs should only show scenario-created resources
- If other resources may appear, add a note like: "Your output may include other resources. Look for the pattern `gnawlab-*`."

### Prohibited
- Real AWS Account ID (12-digit numbers)
- Real credentials (Access Key, Secret Key, Password)
- Real public IP addresses (use `<EC2_PUBLIC_IP>` or `x.x.x.x` placeholders)
- User-specific resource names or data
- Terraform state files (*.tfstate, *.tfstate.backup) - must be in .gitignore

## Walkthrough Writing Guidelines

Walkthroughs must follow the **real attacker workflow**. Include every command an attacker would actually execute, not just the exploit commands.

### Attacker Mindset

Write from the perspective of an attacker who knows **nothing** about the environment at the start.

- Every step must be justified by what was discovered in the previous step
- Even empty results must be documented — they confirm a path is closed
- The number of steps varies by scenario: a single-hop may need 3 steps, a multi-hop may need 8+

### IAM Enumeration (Access Key Based Scenarios)

Always start with identity confirmation, then enumerate exhaustively based on the identity type:

**IAM User** (ARN contains `:user/`)
→ inline policies → managed policies → group memberships → each group's inline and managed policies

**IAM Role** (ARN contains `:assumed-role/`)
→ inline role policies → managed role policies

### Why This Matters

- Learners should understand the **complete attack chain**, not just the final exploit
- Real attackers always enumerate permissions before acting
- Skipping enumeration steps creates unrealistic expectations

## Pull Request Process

1. Fork the repository
2. Create a feature branch
3. Add/modify scenario
4. Test locally with `terraform apply/destroy`
5. Submit PR with description

## Questions?

Open an issue if you have any questions.
