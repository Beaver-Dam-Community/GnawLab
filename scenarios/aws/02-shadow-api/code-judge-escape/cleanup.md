# Code Judge Escape - Cleanup

## Auto Cleanup

```bash
cd terraform
terraform destroy
```

Destroy takes roughly 3-4 minutes. The NAT Gateway and EIP are the slowest items.

## Manual Cleanup

If you ran ECS Exec sessions during the scenario, AWS may have created
CloudWatch Logs streams under the `/gnawlab/codejudge/<scenario_id>` log group.
Terraform destroys the log group itself, but if you re-deployed without first
destroying, leftover streams from a previous `scenario_id` may remain. Remove
them manually:

- [ ] **CloudWatch Logs:** delete any log group matching `/gnawlab/codejudge/*` that does not match the current `scenario_id`.
- [ ] **CloudWatch Logs:** delete any leftover `aws/ecs/...` log streams created by ECS Exec activity.
- [ ] **ECS:** confirm no `gnawlab-codejudge-cluster-*` cluster remains: `aws ecs list-clusters`.
- [ ] **EC2:** confirm no `gnawlab-codejudge-vulnboard-*` instances remain: `aws ec2 describe-instances --filters "Name=tag:Project,Values=GnawLab"`.

## Verify Cleanup

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Scenario,Values=code-judge-escape" \
            "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[].Instances[].InstanceId'

aws ecs list-clusters --query "clusterArns[?contains(@, 'gnawlab-codejudge')]"

aws iam list-roles \
  --query "Roles[?starts_with(RoleName, 'gnawlab-codejudge-')].RoleName"
```

All three queries should return an empty array.

> **Warning:** A leftover NAT Gateway alone costs ~$1/day. Always verify cleanup before walking away.
