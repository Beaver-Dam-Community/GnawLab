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

Every scenario must include IP whitelist for network-accessible resources:

**Required files:**
- `variables.tf`: `whitelist_ip` variable with auto-detect default
- `data.tf`: `data "http" "my_ip"` block for auto-detection
- `locals.tf`: `whitelist_cidr` computed from variable or auto-detect

**Example pattern** (see `s3-data-heist/terraform/` for reference):

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

### Prohibited
- Real AWS Account ID (12-digit numbers)
- Real credentials (Access Key, Secret Key, Password)

## Walkthrough Writing Guidelines

Walkthroughs must follow the **real attacker workflow**. Include every command an attacker would actually execute, not just the exploit commands.

### Required Steps (Access Key Based Scenarios)

1. **Identity Confirmation** - Verify who you are with the compromised credentials
2. **Permission Enumeration** - Enumerate ALL permissions (user inline, user attached, group membership, group inline, group attached policies)
3. **Exploit** - Execute the attack based on discovered permissions
4. **Capture the Flag** - Verify goal achieved and retrieve the flag

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
