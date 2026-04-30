# Metadata Pivot - Setup Guide

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
- 1 VPC with public subnet
- 1 Internet Gateway and Route Table
- 1 Security Group (HTTP access)
- 1 EC2 Instance with vulnerable web application
- 1 IAM Role and Instance Profile
- 1 S3 Bucket with objects

## Step 6: Deploy the Scenario

```bash
terraform apply
```

Type `yes` when prompted.

> **Note:** Deployment takes 1-2 minutes. The EC2 instance needs time to initialize and start the web application.

## Step 7: Get the Web Application URL

```bash
terraform output web_app_url
```

Example output:
```
"http://54.87.28.210"
```

## Step 8: Verify the Application

Wait 1-2 minutes after deployment, then access the URL in your browser. You should see the **Beaver Dam Bank - Custom Card Designer** with a card preview feature.

## Step 9: Start the Challenge!

Explore the web application and find the vulnerability. The card designer allows customers to personalize their credit cards with custom images by providing an image URL. Your goal is to extract the flag from S3 storage.

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

### Web application not loading

The EC2 user_data script takes 1-2 minutes to complete. Check instance status:

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Scenario,Values=metadata-pivot" \
  --query "Reservations[].Instances[].State.Name" \
  --profile GnawLab
```

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
- EC2 t3.micro: ~$0.01/hour
- S3 Bucket: ~$0.01/month (minimal storage)
- VPC/IGW: Free

**Estimated cost: ~$0.25/day**

Always run `terraform destroy` when finished to avoid charges.
