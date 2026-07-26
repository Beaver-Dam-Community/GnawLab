# Security Review -- Atlantis Pipeline Configuration
**Classification:** INTERNAL -- Platform Security
**Reviewer:** sec-eng-02 (Platform Security)
**Date:** 2024-03-15
**Status:** FINDING -- Pending Remediation
**Tracking:** JIRA PLAT-1203

---

## Finding: Unauthenticated Code Execution via Autoplan

The current `atlantis.yaml` has `autoplan.enabled: true` with no `plan_requirements` gate.

This means any user with write access to `infra-repo` -- including service accounts and
contractor accounts -- can trigger arbitrary code execution on the Atlantis runner by
opening a Merge Request that modifies any `.tf` file.

`terraform plan` executes programs directly on the runner via:
- `data "external"` data sources (shell program, arbitrary binary)
- `local-exec` provisioners
- Provider initialization hooks

The Atlantis runner's IAM role currently holds:
- `ec2-instance-connect:SendSSHPublicKey` on `Resource: "*"` (all instances in account)
- `ec2:DescribeInstances` on `Resource: "*"`

A compromised developer account could use a malicious MR to exfiltrate runner credentials
via IMDS, then use those credentials to inject SSH access onto any EC2 instance in the
account via the overprivileged `SendSSHPublicKey` permission. This includes production hosts.

**Severity:** HIGH
**Likelihood:** MEDIUM (requires write access to infra-repo)
**Impact:** Full EC2 lateral movement across account

## Recommended Fix

```yaml
# atlantis.yaml -- safe configuration
version: 3
projects:
- name: infra-production
  dir: .
  autoplan:
    enabled: false                    # disable autoplan -- require explicit `atlantis plan` comment
  plan_requirements: [approved]       # gate plan as well as apply
  apply_requirements: [approved]
```

Also: scope `SendSSHPublicKey` to specific instance ARNs. See PLAT-1203.

## Remediation History

| Date | Update |
|------|--------|
| 2024-03-15 | Finding raised. Shared with platform-infra team lead. |
| 2024-03-22 | Acknowledged. "Will fix in Q2 during Atlantis upgrade window." |
| 2024-06-30 | Q2 passed. Deferred: "Atlantis upgrade blocked on GitLab version pin." |
| 2024-09-15 | Q3 re-prioritization. Deferred to Q4 due to SOC 2 audit prep taking priority. |
| 2025-01-10 | Carrying into 2025 roadmap. Priority: Medium. Owner: platform-infra. |
| 2025-04-02 | No update. JIRA ticket still open. |

## Accepted Risk

Platform team accepts the operational risk of the current EIC-based deployment mechanism
until migration to a dedicated deployment pipeline (PLAT-1203) is complete.
This document serves as formal acknowledgement of accepted risk.

**Risk Owner:** platform-infra
**Next Review:** Q3 2025
**Escalation Path:** Engineering Director → CISO

*Acknowledged: platform-infra lead, 2024-03-15*
