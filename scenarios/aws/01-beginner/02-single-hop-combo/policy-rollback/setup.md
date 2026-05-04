# Policy Rollback - Setup Guide

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
- 1 IAM User with Access Key
- 1 Customer Managed Policy with 3 versions
- 1 Secrets Manager Secret containing the flag

## Step 6: Deploy the Scenario

```bash
terraform apply
```

Type `yes` when prompted.

> **Note:** Deployment takes about 1 minute. The null_resource provisioners create additional policy versions via AWS CLI.

## Step 7: Get the Leaked Credentials

```bash
terraform output -json leaked_credentials
```

Example output:
```json
{
  "aws_access_key_id": "AKIAXXXXXXXXXXXXXXXX",
  "aws_secret_access_key": "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
}
```

## Step 8: Configure Victim Profile

Configure a new AWS CLI profile with the leaked credentials:

```bash
aws configure --profile victim
```

Enter the leaked credentials:
- AWS Access Key ID: `<from output>`
- AWS Secret Access Key: `<from output>`
- Default region name: `us-east-1`
- Default output format: `json`

## Step 9: Start the Challenge!

Verify your access:

```bash
aws sts get-caller-identity --profile victim
```

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

### Policy version creation failed

The scenario uses AWS CLI to create additional policy versions. Ensure:
- AWS CLI is installed and in PATH
- The `GnawLab` profile has IAM permissions

```bash
aws --version
aws iam list-policies --profile GnawLab --max-items 1
```

### Profile not found

Ensure the `GnawLab` profile exists in `~/.aws/credentials`:

```ini
[GnawLab]
aws_access_key_id = YOUR_ADMIN_KEY
aws_secret_access_key = YOUR_ADMIN_SECRET
```

### Terraform state issues

```bash
terraform refresh
```

## Cost Estimate

This scenario uses:
- IAM User & Policy: Free
- Secrets Manager: ~$0.40/month

**Estimated cost: < $0.50/month**

Always run cleanup when finished to avoid charges.
