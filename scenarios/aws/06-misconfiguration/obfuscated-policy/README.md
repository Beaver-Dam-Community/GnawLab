# Obfuscated Policy

**Difficulty:** Easy
**Estimated Time:** 30 min
**Type:** single-hop

## Overview

**Beaver Defense Inc.** operates an automated IAM policy detection system. Whenever any IAM user creates or attaches a customer-managed policy, an EventBridge rule invokes a Lambda function that scans the policy document and **deletes** it if it contains dangerous patterns.

You have obtained the credentials of an IAM user with `iam:CreatePolicy` and `iam:AttachUserPolicy` (self) permissions. The user cannot directly access the company's flag bucket.

The detection Lambda matches blocked patterns as **literal strings** (case-insensitive). However, AWS IAM evaluates `?` and `*` characters inside the **action name portion** of an Action value as wildcards (the service vendor portion before the colon must be a literal name like `s3`). By writing actions such as `s3:Get?bject`, the attacker can grant themselves `s3:GetObject` semantically while the detector sees a string that does not match any blocked literal.

### References

- **AWS IAM Policy Element: Action** - Wildcard support (`?`, `*`) in Action values
  - [AWS Docs: IAM JSON policy elements - Action](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_elements_action.html)
- **Hacking the Cloud: Obfuscated Admin IAM Policy** - Bypassing IAM policy detection via wildcard obfuscation
  - [Hacking the Cloud: Obfuscated Admin Policy](https://hackingthe.cloud/aws/exploitation/obfuscated_admin_policy/)

## Learning Objectives

- Understand how AWS IAM evaluates wildcard characters (`?`, `*`) inside Action values
- Identify the gap between syntactic (string match) and semantic (IAM-engine) policy evaluation
- Practice the full attacker workflow: identity confirmation → permission enumeration → exploit → flag capture
- Recognize why literal pattern detectors are insufficient and when ValidatePolicy / Access Analyzer should be used

## Scenario Resources

- 1 IAM User with leaked Access Key (limited permissions)
- 1 IAM Permission Boundary on the attacker user (single-account SCP equivalent)
- 1 S3 Bucket containing the flag
- 1 S3 Bucket for CloudTrail log delivery
- 1 CloudTrail trail (management events)
- 1 EventBridge Rule (matches `CreatePolicy`, `AttachUserPolicy`)
- 1 Lambda function performing literal-pattern policy detection
- 1 IAM Role for the detection Lambda

> **Defense layers in this scenario:**
> - **Permission Boundary** caps the attacker's effective permissions, blocking unrelated escalation paths (`iam:CreateUser`, `sts:AssumeRole`, `lambda:UpdateFunctionCode`, `cloudtrail:StopLogging`, etc.). In a real environment this would be enforced by an SCP at the AWS Organizations level; we use a Permission Boundary to simulate the same defense in a single account.
> - **Detection Lambda** focuses only on policies that resolve to S3 read actions (the scenario goal).
> - **S3 bucket policy** with IP whitelist restricts who can talk to the flag bucket from the network side.

## Setup

See [setup.md](./setup.md) for deployment instructions.

> **Note:** This scenario creates real AWS resources that may incur costs.

## Starting Point

A leaked AWS Access Key (Access Key ID + Secret Access Key) is provided via Terraform output.

## Goal

Read the flag stored at `s3://<flag_bucket>/flag.txt` despite the active policy detection system.

## Infrastructure Architecture

```
                                +-----------------+
                                |  Attacker (you) |
                                +--------+--------+
                                         |
                                         | iam:CreatePolicy
                                         | iam:AttachUserPolicy
                                         v
+-----------+        CloudTrail        +-----+-----+
| EventBus  | <----------------------- |    IAM    |
+-----+-----+                          +-----------+
      |
      | CreatePolicy / AttachUserPolicy
      v
+-----+-----------+      reads policy doc       +-----------+
| Detector Lambda | --------------------------> |    IAM    |
+-----------------+      deletes if literal     +-----------+
                          pattern matches
                                                  ^
                                                  | s3:GetObject (after attach)
                                                  |
                                              +---+----+
                                              |   S3   |
                                              | (flag) |
                                              +--------+
```

## Real-world Reference

> Source - "Cloud Detection Engineering: The Limits of Pattern Matching" — Many cloud detection systems rely on string or regex matching against IAM policy JSON. Attackers exploit IAM's own wildcard semantics to grant themselves dangerous permissions while remaining textually distinct from any blocked literal.

## Cleanup

When finished, see [cleanup.md](./cleanup.md) to remove all resources.

> **Warning:** Always verify cleanup to avoid unexpected AWS costs.

---

For detailed walkthrough, see [walkthrough.md](./walkthrough.md)
