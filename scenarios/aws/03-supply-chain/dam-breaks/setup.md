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

## Step 3: Initialize Terraform

```bash
terraform init
```

## Step 4: Review the Plan

```bash
terraform plan
```

Resources that will be created:

- 1 VPC with public subnet, IGW, route tables
- 2 Security Groups (portal, ECS task)
- 1 EC2 instance (BeaverPay developer portal)
- 1 Cognito User Pool + Identity Pool
- 2 CodeBuild projects (prod, qa)
- 1 ECR repository
- 1 ECS Fargate cluster, task definition, service
- 5 IAM Roles (CollaboratorDeveloperRole, ECS Task Role, ECS Execution Role, CodeBuild Service Role, portal EC2 role)
- 3 Secrets Manager secrets (db credentials, payment gateway key, flag)

## Step 5: Deploy the Scenario

```bash
terraform apply
```

Type `yes` when prompted.

> **Note:** Deployment takes 3-5 minutes. A lightweight dummy image is automatically pushed to ECR during `terraform apply`. Allow ~2 minutes after apply for the portal user_data to complete.

## Step 6: Get the Web Application URL

```bash
terraform output scenario_entrypoint_url
```

Example output:

```
"http://1.2.3.4/"
```

## Step 7: Verify the Portal

Access the URL in your browser. You should see the **BeaverPay Developer Portal**.

## Step 8: Hand Off to Participant

Provide only the following to the participant:

```
Portal   : http://<portal-ip>/
Email    : j.park@ottercode.kr
Password : Otter2022!
```

Now find the flag! See [walkthrough.md](./walkthrough.md) if you need hints.

## Configuration Options

Customize via `terraform.tfvars`:

```hcl
# Optional: Restrict portal access to specific IPs (default: open to all)
whitelist_cidr = ["YOUR.PUBLIC.IP/32"]

# Optional: Custom flag value
flag_value = "FLAG{custom_flag_here}"
```

## Troubleshooting

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

### Terraform state issues

```bash
terraform refresh
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