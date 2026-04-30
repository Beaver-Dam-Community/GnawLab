## Summary

Add `cicd-eic-pivot` — a multi-hop scenario exploiting a GitLab + Atlantis CI/CD pipeline misconfiguration to steal IAM credentials via IMDSv1 and pivot into a private subnet via EC2 Instance Connect.

## Type

- [x] New scenario
- [ ] Scenario update
- [ ] Documentation
- [ ] Bug fix
- [ ] Other

## Checklist

- [x] All content in English
- [x] Followed template structure
- [x] Terraform tested (`terraform apply` / `destroy`)
- [x] README, setup.md, cleanup.md, walkthrough.md complete

## Scenario Details

**Category:** `aws/03-supply-chain`  
**Difficulty:** Medium  
**Estimated Time:** 60 min  

**Description:**  
BeaverOps Corp. runs GitLab CE and Atlantis with `autoplan.enabled: true` — any Merge Request touching a `.tf` file triggers a live `terraform plan` on the Atlantis runner with no approval gate. A developer account (`000_ops`) is the starting point. Players inject a malicious Terraform `external` data source to exfiltrate IAM credentials from the runner via IMDSv1, then use `ec2-instance-connect:SendSSHPublicKey` (overprivileged, `Resource: "*"`) to SSH into the Bastion Host, discover `target-key.pem`, and pivot into the private subnet to read the flag.

**Attack path:**  
GitLab (000_ops) → Atlantis autoplan → IMDSv1 credential theft → IAM enumeration → EC2 Instance Connect → Bastion Host → Target Server (private subnet) → flag

## Changes

- Add `scenarios/aws/03-supply-chain/cicd-eic-pivot/` with full scenario:
  - `terraform/` — VPC, 4 EC2 instances (GitLab t3.large, Atlantis, Bastion, Target), IAM roles, SSM parameter, security groups
  - `assets/infra-repo/` — clean `main.tf`, `variables.tf`, `atlantis.yaml` seeded into GitLab on deploy
  - `scripts/setup-gitlab.sh.tpl` — installs GitLab CE, creates `000_ops` user, seeds repo, registers Atlantis webhook
  - `scripts/setup-atlantis.sh.tpl` — installs Atlantis with iptables DNAT hairpin NAT fix, `/etc/atlantis-repos.yaml` with `allowed_overrides`, `--repo-config` flag
  - `README.md`, `setup.md`, `cleanup.md`, `walkthrough.md` — full documentation

## Related Issues

N/A
