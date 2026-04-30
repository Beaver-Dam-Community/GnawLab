# Watchdog Trap - Auto Setup Guide

Automated deployment using `deploy.sh`. The script runs terraform apply, seeds the CodeCommit repository, triggers the initial pipeline, and prints the participant URL.

For manual step-by-step deployment, see [manualsetup.md](./manualsetup.md).

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.5.0
- [AWS CLI](https://aws.amazon.com/cli/) v2
- [Git](https://git-scm.com/)
- [Python 3](https://www.python.org/)
- AWS credentials configured (default profile or environment variables)

## Step 1: Configure AWS Credentials

```bash
aws configure
```

Verify:

```bash
aws sts get-caller-identity
```

## Step 2: Run the Deploy Script

```bash
cd scenarios/aws/05-zero-trust/watchdog_trap
chmod +x deploy.sh
./deploy.sh
```

Deployment takes approximately **15–20 minutes** total:
- `terraform apply`: ~10–15 min
- CodePipeline build + ECS deploy: ~5–10 min

## Step 3: Start the Challenge

When the script completes, it prints:

```
======================================================
 Deployment complete
======================================================

  Provide participants with:
  BeaverDam Incident Report Generator: http://<WEBAPP_IP>

  To destroy: cd terraform && terraform destroy -auto-approve
======================================================
```

Provide participants with only the **web application URL**.

## Teardown

```bash
cd terraform
terraform destroy -auto-approve
```

See [cleanup.md](./cleanup.md) for pre-cleanup steps if the pipeline was triggered multiple times.
