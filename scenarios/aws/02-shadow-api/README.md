# Shadow API

Scenarios focused on exploiting undocumented or deprecated API endpoints and legacy system integrations.

## Scenarios

| Scenario | Description | Difficulty |
|----------|-------------|------------|
| [Legacy Bridge](./legacy-bridge/) | Abuse a URL forwarding misconfiguration in a modernized v5 portal to pivot into an undocumented internal v1 backend via SSRF, extract IAM credentials from the IMDSv1 metadata endpoint, and exfiltrate customer data from S3 | Easy |