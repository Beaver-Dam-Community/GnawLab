# legacy-bridge

**Difficulty:** Easy  
**Estimated Time:** 30 min  
**Category:** SSRF/credential-theft

## Overview

Prime Financial, a US credit card issuer, consolidated multiple systems through rapid acquisitions and merged them into a centralized cloud environment. A modern v5 customer portal serves as the public entry point, but to maintain compatibility with legacy services, undocumented v1 systems (IVR, older mobile app, batch jobs) continue operating on the internal network.

The security team believed these legacy systems were isolated, but a misconfiguration in the v5 portal's URL forwarding exposed an internal "Shadow API" connection, allowing attackers from the public internet to reach the v1 backend.

## Learning Objectives

- Understand the security risks created by integrating legacy systems
- Identify access control flaws (IDOR) in APIs
- Access internal services through SSRF vulnerabilities
- Steal AWS credentials from the IMDSv1 metadata service
- Use stolen credentials to access data in S3

## Scenario Resources

AWS resources deployed by Terraform:

- **EC2 2 instances**
  - `Public-Gateway-Server` — Public v5 portal with forwarding vulnerability
  - `Shadow-API-Server` — Internal unprotected v1 node

- **S3 Bucket 1** — `prime-pii-vault-<random_suffix>` — Stores customer credit card application data

- **IAM Roles 2**
  - `Gateway-App-Role` — SSM access only
  - `Shadow-API-Role` — S3 bucket read access

## Setup

See [[setup.md](./setup.md)] for deployment instructions.

> **Note:** This scenario creates real AWS resources that may incur costs.

## Starting Point

Learners are given a public gateway URL without authentication.

## Goal

Download the flag file from S3.

## Infrastructure Architecture

![Architecture](./assets/legacy-bridge-architecture.png)

## Real-world Reference

> **Source - Capital One 2019 Breach** (Attackers used SSRF to access EC2 metadata, stole temporary credentials, and exploited over-privileged IAM roles to access large-scale customer data. Related: Optus 2018 exposed undocumented API, Stripe deprecated endpoint abuse)

- [Capital One 2019 Breach](https://www.capitalone.com/digital/facts2019/)
- [AWS EC2 Metadata Service](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instancedata-data-retrieval.html)
- [OWASP API Security Top 10](https://owasp.org/www-project-api-security/)
- [Real-World API Security Breaches](https://www.apisec.ai/blog/real-world-api-security-breaches-lessons-from-major-attacks)

## Cleanup

When finished, see [[cleanup.md](./cleanup.md)] to remove all resources.

> **Warning:** Always verify cleanup to avoid unexpected AWS costs.

---

For detailed walkthrough, see [[walkthrough.md](./walkthrough.md)].