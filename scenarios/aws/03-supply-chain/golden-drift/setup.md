# Golden Drift - Setup Guide

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.5.0
- [AWS CLI](https://aws.amazon.com/cli/) v2
- AWS Account with admin access — for deploying the target scenario infrastructure
- AWS CLI profile `GnawLab` configured with admin credentials
- **A separate personal AWS account** — for registering the malicious public AMI during the attack. The scenario does not provide this; participants must supply their own.

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

The scenario auto-detects your public IP and applies it as an ALB security group whitelist. You can verify:

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
- 1 IAM User with leaked Access Key (read-only permissions)
- 1 VPC with 2 public subnets across different Availability Zones
- 1 Application Load Balancer (IP-whitelisted)
- 1 Auto Scaling Group with Launch Template (`resolve:ssm:` image reference)
- 1 SSM Parameter storing the current golden AMI ID
- 1 Legitimate golden AMI (baked from Amazon Linux 2023 + Flask ticketing app)
- 1 Lambda function updating the golden AMI pointer every minute
- 1 EC2 IAM Instance Profile with Secrets Manager read access
- 1 Secrets Manager secret containing the flag
- 1 CloudWatch Log Group for the Lambda

## Step 6: Deploy the Scenario

```bash
terraform apply
```

Type `yes` when prompted.

> **Note:** Deployment takes **8–12 minutes**. The AMI baking process requires launching a temporary EC2 instance, installing the Flask application, waiting for user_data to complete, and snapshotting the instance into an AMI.

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

## Step 8: Configure Attacker Profile

Configure a separate AWS CLI profile for the challenge:

```bash
aws configure --profile attacker
```

Enter the leaked credentials from Step 7:
- AWS Access Key ID: `<leaked-access-key>`
- AWS Secret Access Key: `<leaked-secret-key>`
- Default region name: `us-east-1`
- Default output format: `json`

## Step 9: Get the Ticketing Site URL

```bash
terraform output ticketing_url
```

Example output:
```
"http://gnawlab-golden-alb-a1b2c3d4-123456789.us-east-1.elb.amazonaws.com"
```

## Step 10: Start the Challenge!

Verify the credentials work:

```bash
aws sts get-caller-identity --profile attacker
```

You now have read-only AWS credentials and the ticketing site URL. Find a way to get the flag from Secrets Manager.

See [walkthrough.md](./walkthrough.md) if you need hints.

---

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

### Deployment takes longer than expected

AMI baking is the longest step. The `time_sleep` resource waits 180 seconds for `user_data` to complete before snapshotting. This is normal.

### `AccessDenied` when accessing the ticketing site

Your public IP may have changed since deployment. Re-run:

```bash
terraform apply
```

This refreshes the ALB security group whitelist.

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
- EC2 (t2.micro): ~$0.0116/hour per running instance (ASG min=1, max=2)
- ALB: ~$0.02/hour
- Lambda: free tier (< 1,440 invocations/day)
- Secrets Manager: ~$0.40/month
- S3 (AMI snapshot storage): minimal

**Estimated cost: ~$0.05–0.10/hour**

Always run `terraform destroy` when finished to avoid lingering charges.
