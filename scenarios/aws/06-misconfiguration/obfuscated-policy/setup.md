# Obfuscated Policy - Setup Guide

> **Security Note**: Use placeholders for all AWS Account IDs, Access Keys, and Secret Keys.
> - Account ID: `123456789012`
> - Access Key: `AKIAIOSFODNN7EXAMPLE` or `ASIAXXXXXXXXXXX`
> - Secret Key: `xxxxxxxx` or mask actual values

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.5.0
- [AWS CLI](https://aws.amazon.com/cli/) v2
- AWS Account with admin access (for resource creation)
- AWS CLI profile `GnawLab` configured with admin credentials

## Step 1: Configure AWS CLI Profile

If you have not already, configure the `GnawLab` profile:

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

The scenario auto-detects your public IP and applies it as an S3 bucket-policy whitelist. You can verify:

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

Resources that will be created:
- 1 IAM User with Access Key (the leaked credentials)
- 1 IAM inline policy on the attacker user
- 2 S3 Buckets (flag bucket + CloudTrail log bucket)
- 1 S3 Object (the flag)
- 1 CloudTrail trail (management events)
- 1 EventBridge Rule (CreatePolicy / AttachUserPolicy)
- 1 Lambda function (policy detection)
- 1 IAM Role for the Lambda (with inline policy)
- 1 CloudWatch Log Group for the Lambda

## Step 6: Deploy the Scenario

```bash
terraform apply
```

Type `yes` when prompted.

> **Note:** Deployment typically takes 1-3 minutes. CloudTrail can take 5-10 minutes before the first IAM event is delivered to EventBridge.

## Step 7: Retrieve the Leaked Credentials

```bash
terraform output -json leaked_credentials
```

Example output:

```json
{
  "aws_access_key_id": "AKIAIOSFODNN7EXAMPLE",
  "aws_secret_access_key": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
}
```

## Step 8: Configure the Attacker Profile

```bash
aws configure --profile attacker
# AWS Access Key ID: <leaked access key>
# AWS Secret Access Key: <leaked secret>
# Default region name: us-east-1
# Default output format: json
```

## Step 9: Verify Access

```bash
aws sts get-caller-identity --profile attacker
```

Expected output:

```json
{
  "UserId": "AIDAXXXXXXXXXXXXXXXXX",
  "Account": "123456789012",
  "Arn": "arn:aws:iam::123456789012:user/gnawlab/gnawlab-iampoly-attacker-xxxxxxxx"
}
```

## Step 10: Start the Challenge

The compromised user has limited permissions. Find a way to bypass the policy detection system and read the flag.

See [walkthrough.md](./walkthrough.md) if you need hints.

## Configuration Options

Create `terraform.tfvars` for custom settings:

```hcl
# Optional: Specify IP manually (auto-detected by default)
whitelist_ip = "YOUR.PUBLIC.IP/32"

# Optional: Use a different AWS profile for deployment
profile = "my-admin-profile"

# Optional: Custom flag value
flag_value = "FLAG{custom_flag_here}"
```

## Troubleshooting

### Policy keeps surviving even with literal `s3:GetObject`

Wait a few minutes. CloudTrail-to-EventBridge delivery can take up to 5-10 minutes after the trail is first created. After that initial warmup, deletion typically happens within 30-60 seconds.

### `AccessDenied` when reading from S3

Your public IP may have changed since deployment. Re-run:

```bash
terraform apply
```

This refreshes the bucket policy with your current IP.

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
- Lambda: free tier in nearly all cases
- CloudTrail: first management trail is free, S3 storage minimal
- S3: pennies per month for the buckets
- EventBridge: free tier

**Estimated cost: < $0.10/day**

Always run `terraform destroy` when finished to avoid lingering charges.
