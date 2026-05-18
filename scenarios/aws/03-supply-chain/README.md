# Supply Chain

Scenarios focused on exploiting CI/CD pipeline misconfigurations, container image poisoning, and build system abuse to compromise cloud infrastructure.

## Scenarios

| Scenario | Description | Difficulty |
|----------|-------------|------------|
| [cicd-eic-pivot](./cicd-eic-pivot/) | Exploit a misconfigured Atlantis CI/CD pipeline to steal IAM credentials and pivot to isolated infrastructure via EC2 Instance Connect | Medium |
| [dam-breaks](./dam-breaks/) | Abuse an overly permissive Cognito Identity Pool to hijack a CodeBuild pipeline and exfiltrate secrets from Secrets Manager via ECS Task Role | Medium |
