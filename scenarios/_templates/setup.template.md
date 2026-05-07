# Scenario Name - Setup Guide

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.5.0
- [AWS CLI](https://aws.amazon.com/cli/) v2
- AWS Account with admin access (for resource creation)
- AWS CLI profile `GnawLab` configured with admin credentials
- [Any additional tools required by this scenario]

## Deploy

> Add as many steps as the scenario requires. The steps below are a starting point — remove, rename, or add steps freely.
> Common patterns:
> - Simple IAM/S3 scenarios: configure profile → terraform apply → get credentials → configure attacker profile
> - Web/network scenarios: configure profile → terraform apply → get URL → verify app loads
> - Complex scenarios (CI/CD, AI, etc.): may require post-apply seeding, waiting for services, or running helper scripts

### Step 1: Configure AWS CLI Profile

```bash
aws configure --profile GnawLab
```

Verify:

```bash
aws sts get-caller-identity --profile GnawLab
```

### Step 2: Navigate to Terraform Directory

```bash
cd terraform
```

### Step 3: (Optional) Check Your Public IP

```bash
# ifconfig.co is used consistently across all GnawLab scenarios.
# Do not substitute with other services to keep setup instructions uniform.
curl -s https://ifconfig.co/ip
```

### Step 4: Initialize Terraform

```bash
terraform init
```

### Step 5: Review the Plan

```bash
terraform plan
```

Resources that will be created:
- Resource 1
- Resource 2

### Step 6: Deploy the Scenario

```bash
terraform apply
```

Type `yes` when prompted.

### Step 7: Get the Starting Point

**Credentials-based scenarios:**

```bash
terraform output -json <output_name>
```

Example output:
```json
{
  "aws_access_key_id": "AKIAIOSFODNN7EXAMPLE",
  "aws_secret_access_key": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
}
```

Configure attacker profile:

```bash
aws configure --profile attacker
```

**Web/network-based scenarios:**

```bash
terraform output <url_output_name>
```

Access the URL in your browser and verify the application loads.

### Step N: Start the Challenge

Now find the flag! See [walkthrough.md](./walkthrough.md) if you need hints.

---

## Configuration Options

Create `terraform.tfvars` for custom settings:

```hcl
# Optional: Specify IP manually (auto-detected by default)
whitelist_ip = "YOUR.PUBLIC.IP/32"

# Optional: Use different AWS profile for deployment
profile = "my-admin-profile"

# Optional: Custom flag value
flag_value = "FLAG{custom_flag_here}"
```

## Troubleshooting

### "Access Denied" errors during challenge

Your IP may have changed since deployment. Re-run:

```bash
terraform apply
```

### Terraform state issues

```bash
terraform refresh
```

### Profile not found

Ensure the `GnawLab` profile exists in `~/.aws/credentials`:

```ini
[GnawLab]
aws_access_key_id = YOUR_ADMIN_KEY
aws_secret_access_key = YOUR_ADMIN_SECRET
```

## Cost Estimate

This scenario uses:
- Resource 1: Free / ~$X.XX/month
- Resource 2: Free / ~$X.XX/month

**Estimated cost: < $X.XX total**

Always run `terraform destroy` when finished to avoid any charges.
