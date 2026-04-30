# Watchdog Trap — Defender Detection Notes

> Detection methods and remediation measures corresponding to each stage of the exploitation chain.

---

## Stage 1 — SSTI RCE (Flask render_template_string)

**Root Cause:**
`render_template_string()` is called with raw user input (the Summary field) directly concatenated into the Jinja2 template source string.

**Detection:**
- **SAST tools**: Use Bandit or Semgrep to detect `render_template_string(user_input)` patterns.
  - Semgrep rule: `flask-render-template-string-injection`
- **WAF**: Enable AWS WAF with the OWASP Core Rule Set. Block Jinja2 template payload patterns such as `{{`, `}}`, `__class__`, `__mro__`.
- **Runtime detection**: Monitor application logs for anomalous URL-encoded patterns or unusually long Summary field values.

**Remediation:**
```python
# Vulnerable code
result = render_template_string("[...] Summary: " + summary)

# Safe code: always pass user input as a template variable, never in the template string itself
TEMPLATE = "[...] Summary: {{ summary }}"
result = render_template_string(TEMPLATE, summary=summary)
```

---

## Stage 2 — Internal Network Port Scan (via SSTI/SSRF)

**Root Cause:**
The web application server can make direct HTTP requests to hosts in the internal tools subnet due to overly permissive network design.

**Detection:**
- **VPC Flow Logs**: Detect anomalous port scan patterns from the webapp instance ENI toward the 10.0.6.0/24 range (many connection attempts to multiple IPs/ports in a short time window).
- **GuardDuty**: Findings such as `UnauthorizedAccess:EC2/TorIPCaller` and `Recon:EC2/PortProbeUnprotectedPort` indicate active reconnaissance.
- **Application level**: If the web app has no legitimate reason to make outbound HTTP requests, block outbound HTTP at the security group level.

**Remediation:**
- Restrict outbound rules on `webapp-sg` to only required external endpoints.
- Enforce IMDSv2 (`HttpTokens: required`) to protect the instance metadata service from SSRF.

---

## Stage 3 — Unauthenticated Access to Prowler / Steampipe

**Root Cause:**
The Prowler (port 9090) and Steampipe (port 9194) dashboards have no authentication mechanism and rely solely on network-level isolation (internal subnet trust model).

**Detection:**
- **Nginx / Flask access logs**: Monitor for connection sources from the internal webapp IP accessing dashboard services.
- **VPC Flow Logs**: Confirm that inbound connections to `dashboard-sg` originate from `webapp-sg` rather than from operator IP ranges.

**Remediation:**
- Apply HTTP Basic Auth or mTLS to Prowler and Steampipe dashboards.
- Ship access logs to CloudWatch Logs and configure anomaly alerts.
- Restrict `dashboard-sg` ingress to authorized operator IP ranges only.

---

## Stage 4 — Plaintext Credentials in CloudWatch Logs

**Root Cause:**
IAM CodeCommit HTTPS Git credentials for `dev-user` are hardcoded in the CodeBuild buildspec. The `git clone` command runs with the credentials embedded in the URL (`https://username:password@...`), which is logged verbatim to CloudWatch Logs (`/corp/deploy-pipeline`).

**Detection:**
- **Amazon Macie**: Automatically detect credential patterns (URL-embedded credentials) within CloudWatch log data.
- **CloudWatch Logs Metric Filter**: Create a filter for `https://.*:.*@git-codecommit` and publish an SNS alert:
  ```
  filter pattern: "Cloning https://"
  ```
- **Periodic log audit**: Use `aws logs filter-log-events` to regularly scan for credential patterns.

**Remediation:**
- Store Git credentials in AWS Secrets Manager and reference them at runtime in the buildspec:
  ```yaml
  env:
    secrets-manager:
      GIT_USER: "arn:aws:secretsmanager:...:secret:git-credentials:username"
      GIT_PASS: "arn:aws:secretsmanager:...:secret:git-credentials:password"
  ```
- Use CodeBuild's native CodeCommit source integration (eliminates the need for explicit `git clone` in buildspec).
- Remove any `echo` or `git clone` lines in buildspec that print credentials to stdout.

---

## Stage 5 — Unauthorized CodeCommit Push

**Root Cause:**
After the `dev-user` credentials are stolen, an unauthorized party can push arbitrary commits — including malicious modifications to `task-definition.json` — to the `jsn-config` repository.

**Detection:**
- **CloudTrail**: Monitor `codecommit:GitPush` events for:
  - Pushes from unexpected source IP addresses
  - Pushes outside of business hours
  - Changes to `task-definition.json`
- **SNS notification**: Configure a CodeCommit repository trigger on `updateReference` for the `main` branch → SNS → Lambda (diff analysis + alert):
  ```
  EventType: updateReference
  Branch: main
  ```
- **Git commit signing**: Enforce a policy that only accepts GPG-signed commits.

**Remediation:**
- Replace hardcoded `dev-user` credentials in the buildspec with IAM Role-based authentication (instance profile / service role).
- Apply CodeCommit Approval Rules requiring a PR with at least 2 reviewer approvals before merging to `main`.
- Enable branch protection policies to prevent direct pushes to `main`.

---

## Stage 6 — ECS Task Definition `command` Field Tampering

**Root Cause:**
CodePipeline deploys the `task-definition.json` `command` field to ECS without any schema validation, allowing an injected reverse shell command to run inside the container.

**Detection:**
- **Pipeline integrity validation**: Add a `task-definition.json` schema check in the CodeBuild build phase:
  ```bash
  # Add to buildspec.yml
  - jq -e '.containerDefinitions[].command | not' task-definition.json || (echo "ERROR: command field detected"; exit 1)
  ```
- **OPA (Open Policy Agent)**: Validate ECS task definitions against policy before deployment:
  ```rego
  deny[msg] {
    input.containerDefinitions[_].command
    msg := "Container command field must not be present in task definition"
  }
  ```
- **ECS CloudTrail**: Detect `ecs:RegisterTaskDefinition` events that include a `command` field in the container definition.
- **GuardDuty ECS Runtime Monitoring**: Detect reverse TCP connections initiated from inside the container (e.g., `/dev/tcp`).

**Remediation:**
- Add a Manual Approval stage to CodePipeline — require operator sign-off before any deployment proceeds.
- Restrict ECS service outbound security group rules to the minimum required (blocks reverse shell callbacks).
- Disable ECS Exec, enforce a read-only root filesystem on the container.
- Apply a resource-based policy on the Secrets Manager FLAG secret to further limit access to only the authorized ECS task execution role.
