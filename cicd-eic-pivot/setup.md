# CI/CD EIC Pivot - Setup Guide

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
- 1 Internet Gateway and Route Tables
- 4 Security Groups (GitLab, Bastion/Atlantis, Target)
- 1 GitLab CE server (t3.large) with `infra-repo` pre-configured
- 1 Atlantis server (t3.micro) connected to GitLab via webhook
- 1 Bastion Host (t3.micro) in the public subnet
- 1 Target Server (t3.micro) in the private subnet
- 3 IAM Roles and Instance Profiles
- 1 SSM Parameter for the GitLab service token

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

> **Note:** Deployment takes 3–5 minutes for Terraform to complete. GitLab CE requires an additional 15–20 minutes to fully initialize after the EC2 instance starts. Do not attempt to log in until the GitLab UI is accessible in your browser.

## Step 6: Wait for GitLab to Initialize

GitLab CE is the bottleneck. The instance runs a setup script on first boot that installs and configures GitLab, creates the `000_ops` account, seeds `infra-repo`, and registers the Atlantis webhook. This takes approximately 15–20 minutes.

You can monitor progress via SSM Session Manager:

```bash
aws ssm start-session --target <GITLAB_INSTANCE_ID> --profile GnawLab
sudo tail -f /var/log/setup-gitlab.log
```

## Step 7: Get the Starting Point

```bash
terraform output gitlab_server_url
```

Example output:
```
"http://3.92.XXX.XXX"
```

## Step 8: Verify the Scenario is Ready

Once GitLab is accessible, confirm the following before starting:

1. Open `http://<GITLAB_IP>` in your browser — the GitLab login page should appear
2. Log in as `000_ops` with password `BeaverPassword123!`
3. Confirm `infra-repo` exists and contains `main.tf`, `variables.tf`, and `atlantis.yaml`
4. Confirm the Atlantis webhook is registered: navigate to `infra-repo → Settings → Webhooks` and verify a webhook pointing to the Atlantis server is present

The scenario is ready when all four checks pass.

## Step 9: Start the Challenge!

Explore the repository and find the misconfiguration. Your goal is to read `/home/ubuntu/flag.txt` from the Target Server in the private subnet.

Now find the flag! See [walkthrough.md](./walkthrough.md) if you need hints.

## Configuration Options

Create `terraform.tfvars` for custom settings:

```hcl
# Optional: Specify your IP manually instead of auto-detecting
whitelist_ip = "YOUR.PUBLIC.IP/32"

# Optional: Use a different AWS CLI profile
profile = "GnawLab"
```

## Troubleshooting

### GitLab not loading after 20 minutes

Check the setup log via SSM:

```bash
aws ssm start-session --target <GITLAB_INSTANCE_ID> --profile GnawLab
sudo tail -50 /var/log/setup-gitlab.log
```

Look for errors in the GitLab reconfigure step. Common causes are insufficient memory (the instance must be `t3.large` or larger) and DNS resolution failures.

### Atlantis not triggering on Merge Requests

Test the webhook manually from the GitLab UI: navigate to `infra-repo → Settings → Webhooks`, find the Atlantis webhook, and click **Test → Push events**. A `200 OK` response confirms connectivity. If the test fails, verify the Atlantis server security group allows inbound traffic from the GitLab server's private IP.

### IP address changed since deployment

Re-apply to update the security group whitelist (IP is auto-detected):

```bash
terraform apply
```

To specify your IP manually:

```bash
terraform apply -var="whitelist_ip=YOUR.IP/32"
```

## Cost Estimate

| Resource | Instance Type | Estimated Cost |
|---|---|---|
| GitLab server | t3.large | ~$0.08/hour |
| Atlantis server | t3.micro | ~$0.01/hour |
| Bastion Host | t3.micro | ~$0.01/hour |
| Target Server | t3.micro | ~$0.01/hour |

**Estimated total: ~$0.11/hour**

Always run `terraform destroy` when finished to avoid charges.
