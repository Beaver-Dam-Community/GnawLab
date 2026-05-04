# EBS Snapshot Theft - Setup Guide

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

The scenario will auto-detect your IP for SSH whitelisting. You can verify:

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
- 1 VPC with public subnet
- 1 Internet Gateway and Route Tables
- 1 Security Group (SSH access)
- 1 IAM User with access key
- 1 IAM Policy (inline)
- 1 EBS Volume with sensitive data
- 1 EBS Snapshot (target for attacker)
- 1 Temporary EC2 instance (for setup, will be terminated)

## Step 6: Deploy the Scenario

```bash
terraform apply
```

Type `yes` when prompted.

> **Note:** Deployment takes 2-3 minutes. A temporary EC2 instance is created to write data to the volume, then terminated after the snapshot is created.

## Step 7: Get the Leaked Credentials

```bash
terraform output -json leaked_credentials
```

Example output:
```json
{
  "aws_access_key_id": "AKIAIOSFODNN7EXAMPLE",
  "aws_secret_access_key": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
}
```

## Step 8: Configure Victim Profile

Configure a separate AWS CLI profile for the challenge:

```bash
aws configure --profile victim
```

Enter the leaked credentials from Step 7:
- AWS Access Key ID: `<leaked-access-key>`
- AWS Secret Access Key: `<leaked-secret-key>`
- Default region name: `us-east-1`
- Default output format: `json`

## Step 9: Start the Challenge!

Verify the credentials work:

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

### "Access Denied" errors during challenge

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
- EC2 Instance (t3.micro, temporary): ~$0.01 (terminated after setup)
- EBS Volume (1 GB gp3): ~$0.08/month
- EBS Snapshot (1 GB): ~$0.05/month
- VPC/Networking: Free

**Estimated cost: < $0.15/month**

Always run `terraform destroy` when finished to avoid any charges.
