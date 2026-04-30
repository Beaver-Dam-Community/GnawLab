# GnawLab

A community-driven offensive cloud security training ground by Beaver Dam Community. Master cloud exploitation and analysis through high-fidelity, real-world vulnerability scenarios.

## Quick Start

### Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.5.0
- [AWS CLI](https://aws.amazon.com/cli/) v2
- AWS Account with admin access (for resource creation)

### AWS CLI Profile Setup

All GnawLab scenarios use the `GnawLab` AWS CLI profile. Configure it with your admin credentials:

```bash
aws configure --profile GnawLab
# AWS Access Key ID: <your-admin-access-key>
# AWS Secret Access Key: <your-admin-secret-key>
# Default region name: us-east-1
# Default output format: json
```

### Deploy a Scenario

```bash
cd scenarios/aws/01-beginner/01-single-hop/s3-data-heist/terraform
terraform init
terraform apply
```

### Get Scenario Credentials

After deployment, get the "leaked" credentials for the challenge:

```bash
terraform output -json leaked_credentials
```

Configure a separate profile for the challenge:

```bash
aws configure --profile victim
# Use the leaked credentials from terraform output
```

### Cleanup

```bash
terraform destroy
```

## Scenarios

See [scenarios/aws/01-beginner/README.md](./scenarios/aws/01-beginner/README.md) for available scenarios.

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for guidelines on adding new scenarios.
