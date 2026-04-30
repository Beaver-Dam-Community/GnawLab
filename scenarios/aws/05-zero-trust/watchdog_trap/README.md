# Scenario: Watchdog Trap

**Difficulty:** Medium
**Estimated Time:** 90 min
**Category:** zero-trust/multi-hop

## Overview

JSN Corp's DevOps team operates Prowler and Steampipe dashboards for internal cloud security monitoring. These tools are designed to be accessible only from within the internal network, but a publicly exposed incident report web application contains a critical vulnerability. As a security assessor, you must exploit this vulnerability to pivot into the internal network, abuse the security tools themselves to collect sensitive credentials, and ultimately hijack the CI/CD pipeline to obtain the FLAG deployed in an ECS container.

This scenario is based on real-world CI/CD supply chain attack patterns. Hardcoded credentials in CodeBuild buildspec files exposed as plaintext in CloudWatch logs is a repeatedly observed vulnerability in enterprise environments.

## Scenario Resources

- VPC x 1 (6 subnets: public / private / tools)
- EC2 x 3
  - `webapp`: JSN Incident Report Generator (internet-facing, EIP)
  - `prowler`: Security compliance dashboard (internal only, port 9090)
  - `steampipe`: SQL query console (internal only, port 9194)
- ALB x 1 (Blue/Green deployment)
- ECS Fargate x 1 (`jsn-app`, FLAG injected as environment variable)
- CodePipeline x 1 (Source → Build → Deploy)
- CodeBuild x 1 (Docker image build + ECR push)
- CodeDeploy x 1 (ECS Blue/Green)
- CodeCommit x 1 (`jsn-config` repository)
- ECR x 1 (`jsn-app` image)
- S3 x 1 (pipeline artifact bucket)
- CloudWatch Log Group x 1 (`/corp/deploy-pipeline`)
- Secrets Manager x 1 (FLAG storage)

## Setup

See [setup.md](./setup.md) for deployment instructions.

> **Note:** This scenario creates real AWS resources that may incur costs.

## Starting Point

You will receive only one piece of information:

- **Web Application URL**: `http://<webapp_ip>` (JSN Incident Report Generator)

## Goal

Obtain the FLAG value from inside the ECS container.

```
FLAG{...}
```

## Infrastructure Architecture

![Architecture](assets/watchdog_trap_architecture.drawio)

## Real-world Reference

> CircleCI breach (2022) & SolarWinds supply chain attack (2020) — hardcoded credentials in CI/CD pipelines exposed via log leakage, enabling pipeline hijacking and downstream compromise.

## Cleanup

When finished, see [cleanup.md](./cleanup.md) to remove all resources.

> **Warning:** Always verify cleanup to avoid unexpected AWS costs.

---

For detailed walkthrough, see [walkthrough.md](./walkthrough.md)
