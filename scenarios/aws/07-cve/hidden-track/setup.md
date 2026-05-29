# Hidden Track - Setup Guide

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.5.0
- [AWS CLI](https://aws.amazon.com/cli/) v2
- AWS account with admin access (for resource creation)
- AWS CLI profile `GnawLab` configured with admin credentials
- Python 3.9+ (for payload generation)
- `curl` or `wget` + `zip` (for building the ExifTool layer)

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

## Step 2: Build the ExifTool Lambda Layer

`terraform/exiftool-layer.zip` is included in the repository — you only need to rebuild it
if you deleted it (e.g., after running the cleanup guide) or want a fresh build:

```bash
cd scripts
bash build_exiftool_layer.sh
cd ..
```

Expected output:

```
[+] Done: .../terraform/exiftool-layer.zip
[+] Layer size: ~2.5M
```

> **Note:** The layer contains ExifTool 12.23, which is intentionally vulnerable to
> CVE-2021-22204. Do not deploy in production environments.

## Step 3: Navigate to Terraform Directory

```bash
cd terraform
```

## Step 4: (Optional) Check Your Public IP

The scenario auto-detects your IP for HTTP whitelisting. Verify:

```bash
curl -s https://ifconfig.co/ip
```

## Step 5: Initialize Terraform

```bash
terraform init
```

## Step 6: Review the Plan

```bash
terraform plan
```

Resources created:
- 1 VPC with public subnet, IGW, and route table
- 1 Security Group (HTTP access whitelisted to your IP)
- 1 EC2 instance (BeaverSound artist portal)
- 3 IAM roles (Lambda exec, portal EC2, GuardDuty Malware Protection)
- 1 Lambda function (`process-upload`) with ExifTool 12.23 layer
- 1 Lambda layer (ExifTool 12.23)
- 2 S3 buckets (uploads, vault)
- S3 versioning on vault bucket
- tracklist.txt created then deleted (Delete Marker created via null_resource)
- 1 GuardDuty detector + Malware Protection plan for uploads bucket

## Step 7: Deploy the Scenario

```bash
terraform apply
```

Type `yes` when prompted.

> **Deployment time:** 3–5 minutes. The EC2 instance needs ~2 minutes to install
> dependencies and start the Flask portal after the instance is running.

### GuardDuty Note

If GuardDuty is already enabled in your account/region, Terraform may fail with:

```
Error: creating GuardDuty Detector: already exists
```

Import the existing detector:

```bash
DETECTOR_ID=$(aws guardduty list-detectors --profile GnawLab --query 'DetectorIds[0]' --output text)
terraform import aws_guardduty_detector.main $DETECTOR_ID
terraform apply
```

## Step 8: Get the Portal URL

```bash
terraform output portal_url
```

Example output: `"http://<portal-ip>"`

## Step 9: Verify the Portal

Wait 2–3 minutes after deploy, then open the portal URL in your browser.

You should see the **BeaverSound Artist Portal** login/register page.

1. Click **Sign up** to create a free artist account
2. Log in with your new credentials
3. You're ready to start the challenge

## Step 10: Start the Challenge

See [README.md](./README.md) for the scenario overview and starting point.  
See [walkthrough.md](./walkthrough.md) for step-by-step hints.

## Configuration Options

Create `terraform/terraform.tfvars` to override defaults:

```hcl
# Optional: Specify IP manually (auto-detected by default)
whitelist_ip = "YOUR.PUBLIC.IP/32"

# Optional: Use different AWS profile for deployment
profile = "my-admin-profile"

# Optional: Custom flag value
flag_value = "flag{custom_flag_here}"
```

## Troubleshooting

### Portal not loading after 5 minutes

Check EC2 user_data execution status:

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Scenario,Values=hidden-track" \
            "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].InstanceId" \
  --output text \
  --profile GnawLab
```

Then check user_data log via EC2 Instance Connect (no key pair required):

1. Open the [EC2 Console → Instances](https://console.aws.amazon.com/ec2/home#Instances)
2. Select the instance tagged `Scenario=hidden-track`
3. Click **Connect → EC2 Instance Connect → Connect**
4. On the instance:

```bash
cat /var/log/cloud-init-output.log | tail -50
systemctl status beaversound
```

### Portal loads but Flask returns 500 / cloud-init failed

The EC2 bootstrap script (`user_data.sh.tpl`) uses `templatefile()` in `ec2.tf`
to avoid the Terraform `<<-EOF` heredoc indentation problem.

**Why this matters:** Terraform's `<<-EOF` strips leading whitespace based on the
*minimum* indent across all lines in the heredoc. If any line is at column 0 (e.g.,
Python code inside a Flask app), the minimum indent is 0 — nothing is stripped.
A `#!/bin/bash` shebang with 4 leading spaces is not a valid shebang, so
cloud-init silently fails to execute the script.

The fix: bootstrap script lives in `terraform/user_data.sh.tpl` and is loaded
via `base64encode(templatefile(...))`. The `.tpl` file uses `${variable}` syntax
for Terraform interpolation but its indentation is independent of the `.tf` file.

If you need to modify the bootstrap script, edit `terraform/user_data.sh.tpl`
directly and re-run `terraform apply` (the EC2 instance will be recreated because
`user_data_replace_on_change = true`).

### "Access Denied" on portal

Your IP changed since deployment. Re-run `terraform apply` to update the security group.

### Profile not found

Ensure the `GnawLab` profile exists in `~/.aws/credentials`:

```ini
[GnawLab]
aws_access_key_id = YOUR_ADMIN_KEY
aws_secret_access_key = YOUR_ADMIN_SECRET
```

### ExifTool layer not found

Ensure you ran `bash scripts/build_exiftool_layer.sh` before `terraform apply`.
The zip must exist at `terraform/exiftool-layer.zip`.

### Lambda fails — ExifTool returns no output

The ExifTool layer provides the Perl script and library modules at `/opt/`.
The Python 3.9 runtime (Amazon Linux 2) includes system Perl at `/usr/bin/perl`,
so `handler.py` normally invokes real ExifTool:

```
perl /opt/bin/exiftool <file>
```

Under normal deployment, real ExifTool runs — the baseline upload (Step 1.5 of the
walkthrough) shows `File Type: TXT`, not `File Type: Binary`.

If ExifTool execution fails (e.g., corrupted layer zip, missing `/opt/bin/exiftool`),
`handler.py` falls back to a Python-native CVE-2021-22204 simulation (`_python_exiftool()`):

1. Checks for `AT&TFORM` DjVu magic bytes.
2. Parses `ANTa` chunks and extracts the `system(q(CMD))` pattern via regex.
3. Executes the command via `subprocess.run(cmd, shell=True)`.
4. Returns fake ExifTool 12.23 metadata (`File Type: Binary` for non-DjVu files).

If you consistently see `File Type: Binary` for plain text uploads, real ExifTool is
not running — rebuild the layer with `bash scripts/build_exiftool_layer.sh` and
re-apply Terraform.

## Cost Estimate

This scenario uses:
- EC2 t3.micro: ~$0.01/hour
- Lambda: ~$0.00 (free tier)
- S3: ~$0.01/month
- GuardDuty: ~$0.50/month (minimum)

**Estimated cost: ~$0.30/day**

Always run `terraform destroy` when finished to avoid charges.
