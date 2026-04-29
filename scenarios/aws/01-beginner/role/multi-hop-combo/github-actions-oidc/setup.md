# Scenario Name - Setup

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.5.0 installed

## Deploy the Scenario

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

## Starting Credentials

After deployment, you will receive:

- Access Key ID: `AKIA...`
- Secret Access Key: `...`

Configure your AWS CLI profile:

```bash
aws configure --profile scenario-name
```

## Verify Access

```bash
aws sts get-caller-identity --profile scenario-name
```

---

You are now ready to begin. See [README.md](./README.md) for scenario details.
