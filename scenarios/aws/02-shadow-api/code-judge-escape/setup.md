# Code Judge Escape - Setup

## Prerequisites

- AWS CLI configured with a profile named `GnawLab` (or pass `-var="profile=..."`)
- Terraform >= 1.5.0
- Outbound HTTPS to `ifconfig.co` (only for IP auto-detection; pass `-var="whitelist_ip=..."` to skip)
- `nmap`, `curl`, and `python3` on the attacking machine
- `session-manager-plugin` (required by the final ECS Exec step; install via the official AWS docs)

The scenario must be deployed in `us-east-1` (enforced by `variables.tf`).

## Deploy the Scenario

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

The bootstrap takes roughly 5–8 minutes end-to-end:

1. VPC, NAT Gateway, IAM roles, and EC2 / Fargate provisioning: ~4–6 minutes
2. EC2 `user_data` installs Docker, builds the VulnBoard image, and starts the container: ~2–3 minutes

You can tail the EC2 bootstrap log if VulnBoard is not yet responding:

```bash
# Optional: requires opening port 22 in security_groups.tf — not enabled by default
# Easier: use SSM Session Manager if you attach the SSM managed policy temporarily
```

In practice just curl `http://<target_ip>:8080/health` until it returns `OK`.

## Starting Materials

After apply completes, the only thing the learner is given is the contents of
`assets/target_info.txt`, which terraform writes automatically:

```text
Target IP : <EC2 public IP>
Web URL   : http://<EC2 public IP>:8080
Region    : us-east-1
```

You can also inspect the non-sensitive deployment summary:

```bash
terraform output scenario_info
terraform output start_message
```

## Verify the Scenario is Up

```bash
TARGET_IP=$(terraform output -raw target_ip)
curl -s "http://${TARGET_IP}:8080/health"   # -> OK
curl -sI "http://${TARGET_IP}:8080/"        # -> 200, Server: gunicorn
```

If you get a connection refused or timeout for more than ~6 minutes after apply,
something failed during user_data. Re-running `terraform apply` will trigger
`user_data_replace_on_change` and rebuild the instance.

---

You are now ready to begin. See [README.md](./README.md) for the scenario brief
and [walkthrough.md](./walkthrough.md) for the intended solution.
