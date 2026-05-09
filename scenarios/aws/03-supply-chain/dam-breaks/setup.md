# Dam Breaks - Setup Guide

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.5.0
- [AWS CLI](https://aws.amazon.com/cli/) v2
- [Docker](https://docs.docker.com/get-docker/) (required for initial ECR image push)
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
- 1 VPC with public subnet, IGW, route tables
- 2 Security Groups (portal, ECS task)
- 1 EC2 instance (BeaverPay developer portal)
- 1 Cognito User Pool + Identity Pool
- 2 CodeBuild projects (prod, qa)
- 1 ECR repository
- 1 ECS Fargate cluster, task definition, service
- 5 IAM Roles (CollaboratorDeveloperRole, ECS Task Role, ECS Execution Role, CodeBuild Service Role, portal EC2 role)
- 3 Secrets Manager secrets (db credentials, payment gateway key, flag)

## Step 6: Deploy the Scenario

```bash
terraform apply
```

Type `yes` when prompted.

> **Note:** Deployment takes 3-5 minutes. A lightweight dummy image is automatically pushed to ECR during `terraform apply`. Allow ~2 minutes after apply for the portal user_data to complete.

## Step 7: Get the Web Application URL

```bash
terraform output scenario_entrypoint_url
```

Example output:
```
"http://<portal-ip>/"
```

## Step 8: Verify the Portal

Wait 2-3 minutes after deployment, then access the URL in your browser. You should see the **BeaverPay Developer Portal**.

## Step 9: Start the Challenge!

Access the portal and find the vulnerability. Your goal is to extract the flag from AWS Secrets Manager.

Now find the flag! See [walkthrough.md](./walkthrough.md) if you need hints.

## Configuration Options

Create `terraform.tfvars` for custom settings:

```hcl
# Optional: Specify IP manually (auto-detected by default)
whitelist_cidr = "YOUR.PUBLIC.IP/32"

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

### Portal not loading

Allow ~2 minutes after `terraform apply` for user_data to finish. Check instance status:

```bash
aws ec2 describe-instance-status \
  --instance-ids <instance-id> \
  --profile GnawLab \
  --region us-east-1
```

### ECS service shows PENDING or FAILED

Docker may not be installed or running on your local machine. The initial ECR image push requires Docker. Install Docker and re-run:

```bash
terraform apply
```

## Cost Estimate

This scenario uses:
- EC2 t3.micro (portal): ~$0.01/hour
- ECS Fargate (0.25 vCPU, 0.5GB): ~$0.01/hour
- CodeBuild (on demand): minimal
- Secrets Manager: ~$0.01/hour
- ECR: ~$0.01/hour

**Estimated cost: ~$0.05/hour**

Always run `terraform destroy` when finished to avoid charges.