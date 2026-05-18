# CVE

Scenarios focused on exploiting known CVEs within cloud-hosted applications, chaining vulnerability exploitation with AWS-specific techniques to reach the objective.

## Scenarios

| Scenario | Description | Difficulty |
|----------|-------------|------------|
| [hidden-track](./hidden-track/) | Exploit CVE-2021-22204 in an unpatched ExifTool upload pipeline to achieve RCE inside a Lambda function, steal execution role credentials, and recover a confidential file the platform believed was permanently deleted via S3 versioning | Medium |
