# ADR-0003: Deploy Trigger -- EC2 Instance Connect as Interim Mechanism

**Date:** 2023-10-12
**Status:** Accepted (interim -- superseded pending PLAT-1203)
**Deciders:** platform-infra
**Superseded by:** ADR-0004 (CodeDeploy migration -- not yet written)

---

## Context

BeaverOps runs a monolithic application on EC2. Deployments have historically been triggered manually: a senior engineer SSH'd into the production instance and ran `deploy.sh` directly.

In Q3, we adopted Terraform and Atlantis for infrastructure management. IaC coverage is up. MR-based plan/apply is working. But it created an unresolved gap:

**Infrastructure is managed through Atlantis. Application deployment still requires running `deploy.sh` on a live EC2 instance. These are different problems with different solutions.**

We need a way for Atlantis to trigger application deployments after `terraform apply` without a persistent SSH key on disk and without standing up additional infrastructure mid-launch.

### Alternatives Evaluated

| Option | Verdict | Reason |
|--------|---------|--------|
| `user_data` | Rejected | Runs only at first EC2 boot. Cannot re-trigger for day-2 deploys. |
| Ansible | Deferred | Controller node + playbook setup required. No bandwidth this sprint. |
| AWS CodeDeploy | Deferred | Agent on every instance + `appspec.yml` authoring. Right answer long-term; not feasible for current release window. |
| EC2 Instance Connect | **Chosen** | API-based temporary SSH key injection (60s TTL). No persistent key on disk. Works today with one IAM permission. |

### Constraints at Decision Time

- Application is not containerized. Rolling updates via ECS are not an option yet.
- Active launch window. Team had days, not weeks.
- No pre-existing SSH key management infrastructure.

---

## Decision

Use EC2 Instance Connect (EIC) from the Atlantis runner to inject a temporary SSH public key, then execute `deploy.sh` over SSH via `mssh`.

The Atlantis IAM role is granted `ec2-instance-connect:SendSSHPublicKey`. Resource scope is set to `arn:aws:ec2:*:*:instance/*` (wildcard) to avoid maintaining per-instance ARN mappings as instances rotate during blue/green or manual replacement cycles.

This is a **temporary measure**. The risk is acknowledged and tracked under **PLAT-1203**.

---

## Consequences

### Positive

- Deployment works today without additional infrastructure overhead.
- No long-lived SSH keys stored on disk or in Secrets Manager.
- 60-second key TTL limits window for key misuse if the API call is observed.

### Negative / Accepted Risks

- The Atlantis IAM role holds `SendSSHPublicKey` on `Resource: *`. If the Atlantis runner is compromised, an attacker can inject SSH keys onto any EC2 instance in the account -- not just the intended deploy target.
- `autoplan.enabled: true` means any `.tf` change in a Merge Request triggers `terraform plan` without human approval. A compromised GitLab account becomes a direct path to runner code execution.
- The `external` data source in Terraform is an arbitrary shell execution primitive. A malicious `.tf` change in an MR will execute on the Atlantis runner during autoplan.
- The original SSH deploy key (`/home/ubuntu/target-key.pem` on the bastion host) predates this decision and has not been removed. It is no longer used for deployments but remains on disk. Cleanup is included in the PLAT-1203 scope.

The risk was reviewed and accepted before shipping. PLAT-1203 tracks the remediation path. This file is the paper trail.

### Migration Path (PLAT-1203)

1. Install CodeDeploy agent on app instances (next instance replacement cycle)
2. Write `appspec.yml` wrapping `deploy.sh`
3. Replace `null_resource.deploy_trigger` + `local-exec` with CodeDeploy trigger in `main.tf`
4. Remove `ec2-instance-connect:SendSSHPublicKey` from Atlantis IAM role
5. Remove `app_instance_id` variable -- no longer needed
6. Close PLAT-1203
