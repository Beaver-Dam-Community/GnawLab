# Shadow API

Scenarios focused on exploiting undocumented or deprecated API endpoints and legacy system integrations.

## Scenarios

| Scenario | Description | Difficulty |
|----------|-------------|------------|
| [code-judge-escape](./code-judge-escape/) | Internal Python coding-evaluation platform exposed externally; chain pickle deserialization, docker.sock abuse, IMDSv2 credential theft, and ECS Exec into a private Fargate task. | Hard |
| [legacy-bridge](./legacy-bridge/) | Customer data enumeration via IDOR → v1 backend access through SSRF → AWS credential theft from IMDSv1 → S3 data exfiltration | Easy |
