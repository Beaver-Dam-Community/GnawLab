# Code Judge Escape

> **Security Note**: Use placeholders for all AWS Account IDs, Access Keys, and Secret Keys.
> - Account ID: `123456789012`
> - Access Key: `AKIAIOSFODNN7EXAMPLE` or `ASIAXXXXXXXXXXX`
> - Secret Key: `xxxxxxxx` or mask actual values

**Difficulty:** Hard
**Estimated Time:** 60-90 min
**Category:** shadow-api / multi-hop-chain

## Overview

**Beaver Recruit Inc.** built **VulnBoard**, an internal Python coding-evaluation
platform, to assess engineering candidates and quarterly internal performance.
The platform was originally locked behind VPN; when the recruitment team
expanded the program to external applicants, the platform team opened
ingress to `0.0.0.0/0` "just for the recruiting window." The change was
never rolled back.

VulnBoard grades each submission by spawning an ephemeral
`python:3.11-slim` container per request. To do that, the app container
needs to talk to the host Docker daemon, so `/var/run/docker.sock` is
bind-mounted into it - a pattern documented as a HIGH-severity misconfig
by Aqua AVD-KSV-0006 and the Trail of Bits container-escape post.

To avoid the JSON-serializability problem of returning a custom
`GradeResult` class to the browser, an early developer pickled the
result into a `result_cache` cookie. The `SECURITY-142` ticket to migrate
to signed JSON is still open.

## Scenario Resources

- 1 VPC (10.42.0.0/16) with one public subnet and two private subnets across AZ a/b
- 1 NAT Gateway (egress for Fargate pulls and ECS Exec SSM channels)
- 1 EC2 instance hosting VulnBoard (Amazon Linux 2023, IMDSv2 required, hop_limit = 1, `/var/run/docker.sock` mounted into the app container)
- 1 ECS Fargate cluster + 1 task definition + 1 service running the `flag-vault` container in the private subnets
- 2 IAM Roles + 1 EC2 Instance Profile (overprivileged EC2 role; minimal task role)
- 2 Security Groups (VulnBoard ingress whitelisted to the learner IP; Fargate egress-only)

## Setup

See [setup.md](./setup.md) for deployment instructions.

> **Note:** This scenario creates real AWS resources that may incur costs (EC2, NAT Gateway, Fargate, CloudWatch Logs - roughly $0.20-0.40/hour while running).

## Starting Point

The learner is given only the target EC2 public IP, materialized into
`assets/target_info.txt` at apply time. No AWS credentials, no SSH key.

## Goal

Retrieve the flag at `/app/data/flag.txt` inside the private Fargate
`flag-vault` container.

## Infrastructure Architecture

![Architecture](./images/architecture.png)

## Real-world Reference

The scenario is anchored in published research and CVE disclosures; nothing in
the attack chain depends on private intelligence.

- **Judge0 Sandbox Escape Series** (Tanto Security, 2024) - CVE-2024-28185, CVE-2024-28189, CVE-2024-29021. The closest real-world analogue: a Python coding-evaluation system breaking out of its sandbox via privileged Docker access.
  - [Tanto Security technical writeup](https://tantosec.com/blog/judge0/)
- **CVE-2021-33026** - Flask-Caching pickle deserialization RCE (canonical Flask + pickle anti-pattern).
  - [GHSA-656c-6cxf-hvcv](https://github.com/advisories/GHSA-656c-6cxf-hvcv)
- **Trail of Bits: Understanding Docker Container Escapes** (2019) - the reference write-up for `docker.sock = root`.
  - [blog.trailofbits.com/2019/07/19](https://blog.trailofbits.com/2019/07/19/understanding-docker-container-escapes/)
- **Aqua AVD-KSV-0006: No Docker Sock Mount** - machine-readable HIGH-severity misconfig encoded in Trivy.
- **Datadog Security Labs: IMDSv2 hop_limit in containers** (Frichette, 2023) - documents why `hop_limit = 1` matters and how Docker bridges interact with the metadata service.
  - [securitylabs.datadoghq.com/articles/misconfiguration-spotlight-imds](https://securitylabs.datadoghq.com/articles/misconfiguration-spotlight-imds/)
- **Wiz Research: The Many Ways to Obtain Credentials in AWS** (Piper, 2024) - canonical reference for ECS task metadata at `169.254.170.2` and EC2 IMDS pivots.
  - [wiz.io/blog/the-many-ways-to-obtain-credentials-in-aws](https://www.wiz.io/blog/the-many-ways-to-obtain-credentials-in-aws)
- **ECScape** (Sweet Security / Naor Haziz, Black Hat USA 2025) - cross-task ECS credential theft. Relevant to the "Lessons Learned" section: explains why the lab uses Fargate (per-task microVM isolation) instead of ECS on EC2.
  - [GitHub PoC: naorhaziz/ecscape](https://github.com/naorhaziz/ecscape)
- MITRE ATT&CK: [T1611 - Escape to Host](https://attack.mitre.org/techniques/T1611/), [T1552.005 - Cloud Instance Metadata API](https://attack.mitre.org/techniques/T1552/005/), [T1021.008 - Direct Cloud VM Connections](https://attack.mitre.org/techniques/T1021/008/)

## Cleanup

When finished, see [cleanup.md](./cleanup.md) to remove all resources.

> **Warning:** Always verify cleanup to avoid unexpected AWS costs - the NAT Gateway alone runs ~$1/day idle.

## Walkthrough

```mermaid
flowchart TB
    A[Recon: nmap target IP] --> B[VulnBoard /submit + /result]
    B --> C[Pickle deserialization in result_cache cookie]
    C --> D[RCE inside VulnBoard container]
    D --> E[/var/run/docker.sock discovered]
    E --> F[Spawn host-network container via socket]
    F --> G[IMDSv2 PUT token + GET credentials]
    G --> H[aws sts get-caller-identity]
    H --> I[Enumerate ECS clusters and tasks]
    I --> J[ecs:ExecuteCommand into flag-vault]
    J --> K[FLAG]
```

See [walkthrough.md](./walkthrough.md) for the detailed exploitation steps.
