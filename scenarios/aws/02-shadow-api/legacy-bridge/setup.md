# legacy-bridge - Setup

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

After deployment, you will receive the gateway URL:

```bash
terraform output scenario_entrypoint_url
```

Set the gateway URL as an environment variable:

```bash
GW=http://<gateway-ip>
```

Example:
```bash
GW=http://34.237.143.19
```

## Verify Access

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

---

You are now ready to begin. See [README.md](./README.md) for scenario details.