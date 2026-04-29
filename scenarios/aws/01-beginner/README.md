# Beginner

Foundational cloud attack scenarios for learning privilege escalation and lateral movement in AWS environments. These scenarios focus on understanding attack "hops" and permission "combos" without complex initial access vectors.

## Sector 1: Access Key Based Attacks

Starting with long-term credentials (AKIA...), learn to exploit IAM misconfigurations.

### Single Hop

| Scenario | Description | Difficulty |
|----------|-------------|------------|
| [s3-enum-exfil](./access-key/single-hop/s3-enum-exfil/) | Enumerate and exfiltrate data from misconfigured S3 buckets | Easy |
| [policy-version-rollback](./access-key/single-hop/policy-version-rollback/) | Rollback to a vulnerable IAM policy version for privilege escalation | Easy |
| [self-attachment](./access-key/single-hop/self-attachment/) | Attach admin policy to your own user | Easy |

### Single Hop Combo

| Scenario | Description | Difficulty |
|----------|-------------|------------|
| [ebs-volume-theft](./access-key/single-hop-combo/ebs-volume-theft/) | Create EC2 and attach target EBS volume to exfiltrate data | Medium |
| [backdoor-iam-user](./access-key/single-hop-combo/backdoor-iam-user/) | Create backdoor IAM user with admin privileges | Medium |
| [rds-snapshot-restore](./access-key/single-hop-combo/rds-snapshot-restore/) | Restore RDS snapshot and reset master password | Medium |

### Multi Hop

| Scenario | Description | Difficulty |
|----------|-------------|------------|
| [overprivileged-assume-role](./access-key/multi-hop/overprivileged-assume-role/) | Assume an overprivileged role via misconfigured trust policy | Medium |
| [terraform-state-exposure](./access-key/multi-hop/terraform-state-exposure/) | Extract SSH keys from exposed terraform.tfstate in S3 | Medium |
| [ssm-session-manager](./access-key/multi-hop/ssm-session-manager/) | Gain EC2 shell access via SSM Session Manager | Medium |

### Multi Hop Combo

| Scenario | Description | Difficulty |
|----------|-------------|------------|
| [ec2-passrole-userdata](./access-key/multi-hop-combo/ec2-passrole-userdata/) | Launch EC2 with admin role and reverse shell via UserData | Hard |
| [lambda-passrole](./access-key/multi-hop-combo/lambda-passrole/) | Modify Lambda function code and attach high-privilege role | Hard |
| [cicd-pipeline-poisoning](./access-key/multi-hop-combo/cicd-pipeline-poisoning/) | Poison CI/CD pipeline to deploy malicious container | Hard |

## Sector 2: Role Based Attacks

Exploiting temporary credentials (ASIA...) and IAM trust policy misconfigurations.

### Single Hop

| Scenario | Description | Difficulty |
|----------|-------------|------------|
| [public-role-takeover](./role/single-hop/public-role-takeover/) | Assume a publicly accessible role with "AWS": "*" principal | Easy |
| [confused-deputy](./role/single-hop/confused-deputy/) | Exploit missing ExternalId validation in cross-account role | Medium |

### Single Hop Combo

| Scenario | Description | Difficulty |
|----------|-------------|------------|
| [cognito-unauth-role](./role/single-hop-combo/cognito-unauth-role/) | Obtain AWS credentials via misconfigured Cognito Identity Pool | Medium |
| [imdsv2-ssrf](./role/single-hop-combo/imdsv2-ssrf/) | Bypass IMDSv2 protection via SSRF to steal role credentials | Hard |

### Multi Hop

| Scenario | Description | Difficulty |
|----------|-------------|------------|
| [eks-irsa-theft](./role/multi-hop/eks-irsa-theft/) | Steal IRSA credentials from compromised EKS pod | Hard |

### Multi Hop Combo

| Scenario | Description | Difficulty |
|----------|-------------|------------|
| [github-actions-oidc](./role/multi-hop-combo/github-actions-oidc/) | Exploit misconfigured GitHub Actions OIDC trust policy | Expert |
