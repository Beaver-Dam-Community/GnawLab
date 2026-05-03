# Secrets Extraction - Setup Guide

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
- 1 VPC with 2 public subnets
- 1 Internet Gateway and Route Tables
- 2 Security Groups (ALB, ECS)
- 1 Application Load Balancer with Target Group
- 1 ECS Cluster, Task Definition, and Service
- 2 IAM Roles (Execution Role, Task Role)
- 1 Secrets Manager Secret with KMS encryption
- 1 CloudWatch Log Group

## Step 6: Deploy the Scenario

```bash
terraform apply
```

Type `yes` when prompted.

> **Note:** Deployment takes 3-5 minutes. The ECS service needs time to pull the image, install dependencies, and pass health checks.

## Step 7: Get the Web Application URL

```bash
terraform output webapp_url
```

Example output:
```
"http://gnawlab-secrets-alb-a1b2c3d4-123456789.us-east-1.elb.amazonaws.com"
```

## Step 8: Verify the Application

Wait 2-3 minutes after deployment, then access the URL in your browser. You should see the **ResizeCloud** image resizing service.

## Step 9: Start the Challenge!

Explore the web application and find the vulnerability. Your goal is to extract the flag from AWS Secrets Manager.

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

The ECS service takes 2-3 minutes to start. Check service status:

```bash
aws ecs describe-services \
  --cluster $(terraform output -raw scenario_info | jq -r '.scenario_id' | xargs -I {} echo "gnawlab-secrets-cluster-{}") \
  --services $(terraform output -raw scenario_info | jq -r '.scenario_id' | xargs -I {} echo "gnawlab-secrets-service-{}") \
  --profile GnawLab --region us-east-1
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
- ECS Fargate (0.25 vCPU, 0.5GB): ~$0.01/hour
- Application Load Balancer: ~$0.02/hour
- Secrets Manager: ~$0.40/month
- KMS Key: ~$1.00/month

**Estimated cost: ~$0.50/hour**

Always run `terraform destroy` when finished to avoid charges.
