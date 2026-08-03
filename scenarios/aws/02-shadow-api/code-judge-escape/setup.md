# Code Judge Escape - Setup Guide

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.5.0
- [AWS CLI](https://aws.amazon.com/cli/) v2
- AWS Account with admin access (for resource creation)
- AWS CLI profile `GnawLab` configured with admin credentials
- `session-manager-plugin` (required by the final ECS Exec step; install via the official AWS docs)
- `nmap`, `curl`, and `python3` on the attacking machine

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
- 1 VPC with one public subnet and two private subnets
- 1 Internet Gateway, 1 NAT Gateway, and Route Tables
- 1 EC2 instance (Amazon Linux 2023) hosting VulnBoard, in the public subnet
- 1 ECS Fargate cluster, task definition, and service running the `flag-vault` container in the private subnet
- 3 IAM Roles and 1 EC2 Instance Profile
- 2 Security Groups
- 1 SSM Parameter (SecureString) holding the flag value
- 1 CloudWatch Log Group for Fargate task logs

## Step 5: Deploy the Scenario

Your public IP is auto-detected at deploy time. Simply run:

```bash
terraform apply
```

Type `yes` when prompted.

> **Manual IP override:** If you need to specify your IP explicitly, run:
> ```bash
> terraform apply -var="whitelist_ip=YOUR.IP/32"
> ```

> **Note:** Deployment takes approximately 5–8 minutes end-to-end. Terraform provisioning takes 4–6 minutes; the EC2 user-data script then spends another 2–3 minutes installing Docker, building the VulnBoard image, and starting the container. Do not attempt the attack chain until VulnBoard responds with `OK` on its health endpoint.

## Step 6: Wait for VulnBoard to Initialize

VulnBoard is the bottleneck. The EC2 instance runs a user-data script on first boot that installs Docker, builds the VulnBoard container image, and starts the service. Poll the health endpoint until it responds:

```bash
TARGET_IP=$(terraform output -raw target_ip)
until curl -fsS "http://${TARGET_IP}:8080/health"; do
  echo "waiting for VulnBoard to come up..."
  sleep 15
done
echo "VulnBoard is ready."
```

## Step 7: Get the Starting Point

```bash
terraform output target_ip
cat ../assets/target_info.txt
```

Example output:

```text
Target IP : 3.X.XXX.XXX
Web URL   : http://3.X.XXX.XXX:8080
Region    : us-east-1
```

## Step 8: Verify the Scenario is Ready

Once VulnBoard is accessible, confirm the following before starting:

1. Open `http://<TARGET_IP>:8080` in your browser — the VulnBoard ("Beaver Recruit Inc.") coding-evaluation page should appear
2. Submit the default solution — the result page should display `100 / 100  PASS`
3. Inspect the response of `POST /submit` — confirm a `Set-Cookie: result_cache=...` header is present

The scenario is ready when all three checks pass.

## Step 9: Start the Challenge!

You are an anonymous external attacker holding only the target IP. Your goal is to read `/app/data/flag.txt` inside the private Fargate `flag-vault` task.

Now find the flag! See [walkthrough.md](./walkthrough.md) if you need hints.

## Configuration Options

Create `terraform.tfvars` for custom settings:

```hcl
# Optional: Specify your IP manually instead of auto-detecting
whitelist_ip = "YOUR.PUBLIC.IP/32"

# Optional: Use a different AWS CLI profile
profile = "GnawLab"

# Optional: Override the flag base value (a random hex suffix is always appended)
flag_value = "FLAG{your_custom_base}"

# Optional: Larger instance for the VulnBoard host if Docker build is slow
instance_type = "t3.small"
```

## Troubleshooting

### VulnBoard not responding after 8 minutes

Inspect the EC2 console output for the bootstrap log:

```bash
INSTANCE_ID=$(aws ec2 describe-instances --profile GnawLab \
  --filters "Name=tag:Scenario,Values=code-judge-escape" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)

aws ec2 get-console-output --instance-id "$INSTANCE_ID" --profile GnawLab | tail -80
```

Look for errors in `/var/log/vulnboard-bootstrap.log` references. Common causes are Docker Hub rate limits during the image pull (retry `terraform apply -replace=aws_instance.vulnboard`) and missing outbound egress on the EC2 security group.

### Fargate task stuck in PENDING

The flag-vault task pulls `public.ecr.aws/docker/library/alpine:3.19` through the NAT Gateway. If the task does not reach RUNNING within ~2 minutes after `terraform apply` finishes, verify the NAT Gateway is healthy and the private route table points `0.0.0.0/0` at it:

```bash
CLUSTER=$(terraform output -raw ecs_cluster_arn | rev | cut -d/ -f1 | rev)
aws ecs describe-services --profile GnawLab --region us-east-1 \
  --cluster "$CLUSTER" \
  --services "$(aws ecs list-services --cluster "$CLUSTER" --profile GnawLab --query 'serviceArns[0]' --output text | rev | cut -d/ -f1 | rev)" \
  --query 'services[0].events[:5]'
```

### IP address changed since deployment

Re-apply to update the security group whitelist (IP is auto-detected):

```bash
terraform apply
```

To specify your IP manually:

```bash
terraform apply -var="whitelist_ip=YOUR.IP/32"
```

Always run `terraform destroy` when finished. See [cleanup.md](./cleanup.md) for details.
