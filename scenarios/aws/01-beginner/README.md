# Beginner

Foundational cloud attack scenarios for learning privilege escalation and lateral movement in AWS environments. Each scenario is based on real-world incidents or documented security research.

## Classification

| Category | Definition | Example |
|----------|------------|---------|
| **Single Hop** | One entry point → direct path to target (no pivot) | Leaked creds → S3 |
| **Single Hop Combo** | One entry point → traverse multiple services → target | SSRF → IMDS → IAM → S3 |
| **Multi Hop** | Exploit A grants access to discover/exploit B | SQLi → creds → SSRF → ... |
| **Multi Hop Combo** | Multi Hop + multiple permissions at each stage | Complex privilege escalation chains |

## Single Hop

One entry point, direct path to target without pivoting through other services.

| Scenario | Description | Difficulty | Reference |
|----------|-------------|------------|-----------|
| [s3-data-heist](./01-single-hop/s3-data-heist/) | Enumerate and exfiltrate data from S3 | Easy | Uber 2016 |

## Single Hop Combo

One entry point, but traverse multiple AWS services to reach the target.

| Scenario | Description | Difficulty | Reference |
|----------|-------------|------------|-----------|
| [ebs-snapshot-theft](./02-single-hop-combo/ebs-snapshot-theft/) | Create EC2 and attach snapshot to exfiltrate data | Medium | Datadog Labs |
| [policy-rollback](./02-single-hop-combo/policy-rollback/) | Rollback to a vulnerable IAM policy version | Medium | CloudGoat |
| [metadata-pivot](./02-single-hop-combo/metadata-pivot/) | SSRF → IMDS → S3 data exfiltration | Medium | Capital One 2019 |
| [secrets-extraction](./02-single-hop-combo/secrets-extraction/) | Command injection → ECS metadata → Secrets Manager | Medium | LexisNexis 2025 |

## Multi Hop

Chain of exploits where each vulnerability grants access to discover or exploit the next.

| Scenario | Description | Difficulty | Reference |
|----------|-------------|------------|-----------|
| [credential-chain](./03-multi-hop/credential-chain/) | Chain credentials across services to escalate | Hard | Sysdig TRT 2025 |

## Multi Hop Combo

Complex attack chains with multiple permissions leveraged at each hop.

| Scenario | Description | Difficulty | Reference |
|----------|-------------|------------|-----------|
| [lambda-backdoor](./04-multi-hop-combo/lambda-backdoor/) | PassRole + Lambda to execute privileged code | Hard | CloudGoat |
| [ec2-role-hijack](./04-multi-hop-combo/ec2-role-hijack/) | Launch EC2 with admin role via PassRole | Hard | Rhino Security |
