# Code Judge Escape

**Difficulty:** Hard  
**Estimated Time:** 60-90 min  
**Type:** multi-hop-chain

## Overview

**Beaver Recruit Inc.** built **VulnBoard**, an internal Python coding-evaluation platform used for engineering interviews and quarterly internal evaluations. It originally lived behind the corporate VPN. When the recruitment team expanded the program to external applicants, the platform team opened ingress to `0.0.0.0/0` "just for the recruiting window," and the change was never rolled back.

VulnBoard grades each submission by spawning an ephemeral `python:3.11-slim` container per request. To make that work, the app container reaches the host Docker daemon through a bind-mounted `/var/run/docker.sock`. An early developer also pickled the custom `GradeResult` class into a `result_cache` cookie to skip a JSON migration; the `SECURITY-142` ticket to move to signed JSON is still open. Both shortcuts shipped to production.

Starting from nothing but the public IP in `target_info.txt`, players exploit the pickled cookie to land RCE inside the VulnBoard container, pivot through the Docker socket to reach IMDSv2 and steal the EC2 role's credentials, then use the role's left-over `ecs:ExecuteCommand` permission to drop a shell into the private Fargate task that holds the flag.

### References

- **T1611 - Escape to Host**
  - [MITRE ATT&CK: T1611](https://attack.mitre.org/techniques/T1611/)
- **T1552.005 - Unsecured Credentials: Cloud Instance Metadata API**
  - [MITRE ATT&CK: T1552.005](https://attack.mitre.org/techniques/T1552/005/)
- **T1021.008 - Remote Services: Direct Cloud VM Connections**
  - [MITRE ATT&CK: T1021.008](https://attack.mitre.org/techniques/T1021/008/)
- **Judge0 Sandbox Escape Series** (Tanto Security, 2024) — CVE-2024-28185 / 28189 / 29021. A Python coding-evaluation system broken out of its sandbox via privileged Docker access; the closest real-world analogue to this scenario.
  - [Tanto Security technical writeup](https://tantosec.com/blog/judge0/)
- **CVE-2021-33026** — Flask-Caching pickle deserialization RCE (canonical Flask + pickle anti-pattern).
  - [GHSA-656c-6cxf-hvcv](https://github.com/advisories/GHSA-656c-6cxf-hvcv)
- **Trail of Bits: Understanding Docker Container Escapes** (2019) — the reference write-up for "docker.sock = root."
  - [blog.trailofbits.com/2019/07/19](https://blog.trailofbits.com/2019/07/19/understanding-docker-container-escapes/)
- **Aqua AVD-KSV-0006: No Docker Sock Mount** — HIGH-severity misconfig encoded in Trivy policy.
- **Datadog Security Labs: IMDSv2 hop_limit in containers** (Frichette, 2023) — documents why `hop_limit = 1` matters and how Docker bridges interact with the metadata service.
  - [securitylabs.datadoghq.com/articles/misconfiguration-spotlight-imds](https://securitylabs.datadoghq.com/articles/misconfiguration-spotlight-imds/)
- **Wiz Research: The Many Ways to Obtain Credentials in AWS** (Piper, 2024) — canonical reference for ECS task metadata at `169.254.170.2` and EC2 IMDS pivots.
  - [wiz.io/blog/the-many-ways-to-obtain-credentials-in-aws](https://www.wiz.io/blog/the-many-ways-to-obtain-credentials-in-aws)
- **AWS Documentation: Using Amazon ECS Exec for debugging** — canonical reference for the `ecs:ExecuteCommand` + `ssmmessages:*` channel mechanism that the final step exercises.
  - [docs.aws.amazon.com/AmazonECS/.../ecs-exec.html](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-exec.html)
- **Wiz Research: Tracking TeamPCP** (2026) — in-the-wild threat-actor abuse of ECS Exec (SSM Agent-backed) for post-compromise command execution inside running containers.
  - [wiz.io/blog/tracking-teampcp-investigating-post-compromise-attacks-seen-in-the-wild](https://www.wiz.io/blog/tracking-teampcp-investigating-post-compromise-attacks-seen-in-the-wild)
- **ECScape** (Naor Haziz, Sweet Security; Black Hat USA 2025) — cross-task ECS credential theft on the EC2 launch type. Explains why this lab uses Fargate (per-task microVM isolation) so the blast radius is bounded to the compromised task.
  - [Black Hat USA 2025: ECS-cape – Hijacking IAM Privileges in Amazon ECS](https://www.youtube.com/watch?v=UV-hS-DTeik)

## Learning Objectives

- Recognise Python `pickle` framing inside an HTTP cookie (the `\x80\x04` magic that follows base64 `gASV...`) and build a `__reduce__` gadget that triggers code execution the moment `pickle.loads` is called
- Identify a bind-mounted `/var/run/docker.sock` from inside a workload container and use the host Docker daemon as a privilege primitive — without breaking the sandbox itself
- Bypass IMDSv2 `hop_limit = 1` by spawning a `--network host` container through the Docker socket; understand why AWS-recommended hardening defaults are necessary but not by themselves sufficient
- Enumerate an EC2 instance role's IAM policy, identify left-over `ecs:ExecuteCommand` and `ssmmessages:*` permissions, and use them to land an interactive shell inside a private Fargate task

## Scenario Resources

- 1 VPC with one public subnet and two private subnets
- 1 EC2 instance running an internally-built coding-evaluation web application (VulnBoard) exposed via HTTP
- 1 ECS Fargate task in the private subnet that holds the flag
- 3 IAM Roles + 1 EC2 Instance Profile
- 2 Security Groups (one for the public web app, one for the private Fargate task)

## Starting Point

After `terraform apply`, the learner is given **only** the EC2 public IP, materialized into `assets/target_info.txt`:

```text
Target IP : <EC2 public IP>
Web URL   : http://<EC2 public IP>:8080
Region    : us-east-1
```

No AWS credentials. No SSH key. No other endpoint.

## Goal

Read the contents of `/app/data/flag.txt` inside the private Fargate `flag-vault` container.

## Setup & Cleanup

- [setup.md](./setup.md) - Deploy scenario infrastructure
- [cleanup.md](./cleanup.md) - Remove all resources

> **Warning:** This scenario creates real AWS resources that may incur costs. The VulnBoard host takes approximately 5–8 minutes to fully initialize after `terraform apply`: roughly 4–6 minutes for VPC, NAT Gateway, IAM, and EC2 provisioning, then another 2–3 minutes while the EC2 user-data script installs Docker, builds the VulnBoard image, and starts the container. Poll `http://<target_ip>:8080/health` until it returns `OK` before starting the attack chain, and always run `terraform destroy` when finished.

## Infrastructure Architecture

![Architecture](./images/architecture.png)

## Real-world Reference

> **Coding-evaluation sandbox escape via privileged Docker access:** A pattern where a self-hosted code-grading service mounts the host Docker daemon into its application container so it can launch user-code sandboxes, accidentally turning any RCE inside the application into host-equivalent privilege and reach to the cloud instance metadata service. Judge0, the most widely-deployed open-source code-evaluation system, shipped three Critical CVEs in 2024 (CVE-2024-28185 / 28189 / 29021) under exactly this shape: an attacker-submitted program escaped the evaluation container via symlink primitives and a privileged Docker container, then read host credentials from IMDS. This lab reproduces the same end-to-end primitive of *user code execution + privileged Docker daemon + reachable IMDS*, but switches the entry trigger to a Flask `pickle.loads` cookie (the canonical CVE-2021-33026 pattern), so the initial-access step is itself a recognisable industry anti-pattern rather than a Judge0-specific CVE replay.

## Walkthrough

```mermaid
flowchart TB
    A["Recon: nmap target IP"] --> B["VulnBoard /submit + /result"]
    B --> C["Pickle deserialization in result_cache cookie"]
    C --> D["RCE inside VulnBoard container"]
    D --> E["/var/run/docker.sock bind-mounted"]
    E --> F["Spawn --network host container via socket"]
    F --> G["IMDSv2 PUT token + GET credentials"]
    G --> H["aws sts get-caller-identity"]
    H --> I["Enumerate ECS clusters and tasks"]
    I --> J["ecs:ExecuteCommand into flag-vault"]
    J --> K["FLAG"]
```

See [walkthrough.md](./walkthrough.md) for detailed exploitation steps.
