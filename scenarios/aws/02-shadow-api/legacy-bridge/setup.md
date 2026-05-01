# legacy-bridge - Setup Guide

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

## Step 3: Initialize Terraform

```bash
terraform init
```

## Step 4: Review the Plan

```bash
terraform plan
```

Review the resources that will be created:
- 1 VPC with public and private subnets
- 1 Internet Gateway, NAT Gateway, and Route Tables
- 2 EC2 instances (Public-Gateway-Server, Shadow-API-Server)
- 2 Security Groups (Public, Private)
- 1 S3 bucket (`legacy-bridge-pii-vault-<suffix>`) with encryption and PII seed data
- 2 IAM Roles (Gateway-App-Role with SSM access, Shadow-API-Role with S3 read access)

## Step 5: Deploy the Scenario

```bash
terraform apply
```

Type `yes` when prompted.

> **Note:** Deployment takes 2-3 minutes. The EC2 instances need time to boot, install dependencies, and start services.

## Step 6: Get the Gateway URL

```bash
terraform output scenario_entrypoint_url
```

Example output:

```
"http://34.237.143.19"
```

Save the URL as an environment variable:

```bash
GW=http://<gateway-ip>
```

## Step 7: Verify the Application

Wait 2-3 minutes after deployment, then check the gateway status:

```bash
curl -s $GW/api/v5/status
```

Expected response:

```json
{
  "hostname": "ip-10-10-1-222.ec2.internal",
  "service": "Prime Financial Customer Portal",
  "status": "healthy",
  "version": "5.0.0"
}
```

## Step 8: Start the Challenge!

Explore the web application and find the vulnerabilities. Your goal is to extract PII data from the S3 bucket using IDOR and SSRF attacks to steal AWS credentials.

Now find the flag! See [walkthrough.md](./walkthrough.md) if you need hints.

## Configuration Options

Create `terraform.tfvars` for custom settings:

```hcl
# Optional: Custom flag value
flag_value = "FLAG{custom_flag_here}"
```

## Troubleshooting

### Web application not loading

The EC2 instances take 2-3 minutes to start. Check instance status:

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Scenario,Values=legacy-bridge" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name]' \
  --profile GnawLab --region us-east-1
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

### Gateway service not responding

Check EC2 instance system logs:

```bash
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=Public-Gateway-Server-*" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text --profile GnawLab)

aws ec2 get-console-output --instance-id $INSTANCE_ID --profile GnawLab
```

## Cost Estimate

This scenario uses:
- EC2 instances (t3.micro x2): ~$0.021/hour
- NAT Gateway: ~$0.045/hour
- S3 storage (`legacy-bridge-pii-vault-<suffix>`): ~$0.023/month

**Estimated cost: ~$0.07/hour**

Always run `terraform destroy` when finished to avoid charges.