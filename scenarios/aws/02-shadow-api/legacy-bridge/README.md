# legacy-bridge

**Difficulty:** Easy  
**Estimated Time:** 30 min  
**Category:** SSRF/credential-theft

## Overview

Prime Financial, a US credit card issuer, underwent rapid M&A consolidation and merged multiple heterogeneous infrastructures into a centralized cloud environment. A modern v5 customer portal was deployed as the main entry point, but for backward compatibility, undocumented v1 legacy nodes (IVR systems, 2018-era mobile apps, and nightly batch jobs) continue to operate within the private network.

The security team assumes these legacy services are isolated, but a URL forwarding misconfiguration in the v5 portal opens a "Shadow API" bridge, allowing attackers from the public internet to control the v1 backend.

### Attack Chain

This scenario models the Capital One 2019 breach pattern:

1. **Reconnaissance & IDOR** — Enumerate other customers' metadata by iterating `/api/v5/legacy/media-info?file_id=<N>`; v1 backend URL leaked in responses

2. **SSRF via v5 Portal** — Inject `source=` query parameter, which the v5 portal forwards as-is to v1; v1 fetch `http://169.254.169.254/...` server-side

3. **Credential Theft** — IMDSv1 returns `Shadow-API-Role` STS credentials

4. **Data Exfiltration** — The role has `s3:GetObject` permissions on the PII vault. Download the flag file using AWS CLI (SigV4)

## Learning Objectives

- Understand how legacy system integration introduces network-level trust boundaries
- Identify Insecure Direct Object Reference (IDOR) vulnerabilities in API design
- Access internal services through Server-Side Request Forgery (SSRF)
- Steal AWS credentials by exploiting the IMDSv1 metadata endpoint
- Exfiltrate sensitive data from S3 using compromised IAM role

## Scenario Resources

AWS resources created by Terraform:

- **EC2 x 2**
  - `Public-Gateway-Server` — Public v5 portal with request forwarding vulnerability at `/api/v5/legacy/media-info`
  - `Shadow-API-Server` — Private legacy v1 node running an unprotected URL fetch endpoint

- **S3 Bucket x 1** — `prime-pii-vault-<random_suffix>` (stores customer credit card application data)

- **IAM Roles**
  - `Gateway-App-Role` — Entry point role with SSM-only permissions, no AWS data access
  - `Shadow-API-Role` — Over-privileged media caching role with read access to production PII vault

## Setup

See [[setup.md](./setup.md)] for deployment instructions.

> **Note:** This scenario creates real AWS resources that may incur costs.

## Starting Point

Learners are provided with a public gateway URL. No authentication required.

## Goal

Steal and retrieve the flag file from S3.

## Infrastructure Architecture

![Architecture](./assets/legacy-bridge-architecture.png)

## Real-world Reference

> **Source** - Capital One 2019 Breach  
> The 2019 Capital One data breach resulted from SSRF-based IMDSv1 metadata access and large-scale PII exfiltration via over-privileged IAM roles.

### References

- [AWS EC2 Instance Metadata Service (IMDSv1)](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instancedata-data-retrieval.html)
- [Capital One 2019 Breach](https://www.us-cert.gov/ncas/alerts/AA19-339A) — US-CERT Advisory
- [OWASP API Security Top 10](https://owasp.org/www-project-api-security/) — API1, API7 (SSRF)

## Cleanup

When finished, see [[cleanup.md](./cleanup.md)] to remove all resources.

> **Warning:** Always verify cleanup to avoid unexpected AWS costs.

---

For detailed walkthrough, see [[walkthrough.md](./walkthrough.md)].