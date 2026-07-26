# Incident Report: 2024-02

Date: 2024-02-07
Severity: Medium
Status: Closed

## Summary

A deployment SSH private key was accidentally committed to a feature branch
and pushed to GitLab. The key had direct SSH access to the production app
server. The branch was deleted within six minutes of the commit and the key
was rotated within the hour.

## Timeline

2024-02-07 14:32  Key committed in branch feat/update-deploy-script
2024-02-07 14:38  Noticed during self-review before opening MR, branch deleted
2024-02-07 15:10  Key rotated, authorized_keys updated on all instances
2024-02-07 16:00  Incident closed

## Root Cause

The deploy key was stored as a plain file in the working directory. A broad
`git add .` included it. No pre-commit hook was in place to catch secrets.

## Resolution

Immediate: key rotated, branch deleted, git history scrubbed locally.
Short-term: .gitignore updated, pre-commit hook added (detect-secrets).

Long-term: remove SSH key-based deployment entirely. The team evaluated
CodeDeploy and Ansible. CodeDeploy requires per-instance agent setup and
per-application buildspec files -- estimated one full sprint to do properly.
Given the launch timeline we adopted EC2 Instance Connect as an interim
solution. EIC injects a 60-second TTL key via the AWS API and requires no
static key on disk.

Migration to a proper deploy pipeline is tracked in PLAT-1203.

## Lessons Learned

Static deploy keys are a liability regardless of .gitignore coverage.
The only real fix is eliminating the key from the pipeline entirely.
EIC is the right interim step. PLAT-1203 needs to actually ship.
