# {{Scenario Name}} - Setup Guide

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.5.0
- [AWS CLI](https://aws.amazon.com/cli/) v2
- AWS Account with admin access (for resource creation)
- AWS CLI profile `GnawLab` configured with admin credentials

## Step 1: Configure AWS CLI Profile

If you haven't already, configure the `GnawLab` profile with your admin credentials:

```bash
aws configure --profile GnawLab
```

Enter your admin credentials:
- AWS Access Key ID: `<your-admin-access-key>`
- AWS Secret Access Key: `<your-admin-secret-key>`
- Default region name: `us-east-1`
- Default output format: `json`

Verify the profile works:

```bash
aws sts get-caller-identity --profile GnawLab
```

## Step 2: Navigate to Terraform Directory

```bash
cd terraform
```

## Step 3: (Optional) Check Your Public IP

The scenario will auto-detect your IP for whitelisting. You can verify:

```bash
curl -s https://ifconfig.co/ip
```

## Step 4: Initialize Terraform

```bash
terraform init
```

## Step 5: Review the Plan

```bash
terraform plan
```

Review the resources that will be created:
<!-- List the main resources created by this scenario -->
- Resource 1
- Resource 2
- ...

## Step 6: Deploy the Scenario

```bash
terraform apply
```

Type `yes` when prompted.

> **Note:** Deployment takes X-Y minutes. <!-- Adjust based on scenario -->

## Step 7: Get the Starting Point

<!-- Scenario-specific: credentials, URL, etc. -->

```bash
terraform output <output_name>
```

Example output:
```
<!-- Example output -->
```

## Step 8: Verify the Deployment

<!-- Scenario-specific verification steps -->

## Step 9: Start the Challenge!

<!-- Brief description of what to do -->

Now find the flag! See [walkthrough.md](./walkthrough.md) if you need hints.

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

### Common Issue 1

<!-- Scenario-specific troubleshooting -->

### "Access Denied" or connection timeout

Your IP may have changed since deployment. Re-run:

```bash
terraform apply
```

This will update the IP whitelist.

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
<!-- List resources and their approximate costs -->
- Resource 1: ~$X.XX/hour
- Resource 2: ~$X.XX/month

**Estimated cost: ~$X.XX/day**

Always run `terraform destroy` when finished to avoid charges.
