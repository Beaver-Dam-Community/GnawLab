# Code Judge Escape - Cleanup Guide

## Automated Cleanup (Recommended)

### Step 1: Navigate to Terraform Directory

```bash
cd terraform
```

### Step 2: Destroy All Resources

```bash
terraform destroy
```

Type `yes` when prompted. Destroy typically takes 3–4 minutes; the NAT Gateway and Elastic IP are the slowest items.

### Step 3: Verify Cleanup

```bash
terraform show
```

Should output: `No state.` or empty state.

## Manual Cleanup Checklist

Before running `terraform destroy`, remove any resources you created manually during the scenario:

- [ ] Temporary AWS environment variables that hold stolen STS credentials (`unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_DEFAULT_REGION`)
- [ ] Open ECS Exec sessions still attached to the `flag-vault` task (close with `exit`)
- [ ] Local pickle payload scripts or verifier helpers (`rm -f /tmp/code-judge-*.py /tmp/code-judge-*.log`)
- [ ] `nc` reverse-shell listeners on the attacking machine, if used during the walkthrough

If Terraform destroy fails, manually delete these resources:

### AWS Console

1. **EC2 Instances**
   - Go to [EC2 Console → Instances](https://console.aws.amazon.com/ec2/home#Instances)
   - Search for instances tagged with `Scenario=code-judge-escape`
   - Terminate the VulnBoard host

2. **ECS Cluster, Service, and Task**
   - Go to [ECS Console](https://console.aws.amazon.com/ecs/)
   - Find clusters whose name starts with `gnawlab-codejudge-cluster-`
   - Stop the running tasks, delete the service, then delete the cluster

3. **NAT Gateway and Elastic IP**
   - Go to [VPC Console → NAT Gateways](https://console.aws.amazon.com/vpc/home#NatGateways)
   - Delete the NAT Gateway tagged with this scenario
   - Then release the associated Elastic IP from [EC2 Console → Elastic IPs](https://console.aws.amazon.com/ec2/home#Addresses)

4. **Security Groups**
   - Go to [EC2 Console → Security Groups](https://console.aws.amazon.com/ec2/home#SecurityGroups)
   - Search for groups containing `gnawlab-codejudge`
   - Delete after terminating instances and stopping ECS tasks (to release dependencies)

5. **VPC**
   - Go to [VPC Console](https://console.aws.amazon.com/vpc/)
   - Search for the VPC tagged with `Scenario=code-judge-escape`
   - Delete subnets, route tables, and the internet gateway, then the VPC itself

6. **IAM Roles and Instance Profile**
   - Go to [IAM Console → Roles](https://console.aws.amazon.com/iam/home#/roles)
   - Search for roles containing `gnawlab-codejudge`
   - Detach inline policies first, then delete the roles and the EC2 instance profile

7. **SSM Parameter**
   - Go to [Systems Manager → Parameter Store](https://console.aws.amazon.com/systems-manager/parameters)
   - Search for parameters starting with `/gnawlab/codejudge/`
   - Delete each parameter

8. **CloudWatch Log Groups**
   - Go to [CloudWatch Console → Log Groups](https://console.aws.amazon.com/cloudwatch/home#logsV2:log-groups)
   - Search for log groups starting with `/gnawlab/codejudge/`
   - Delete each log group (and any orphaned streams from prior runs)

### AWS CLI

```bash
export AWS_PROFILE=GnawLab
export AWS_REGION=us-east-1

# Terminate EC2 instances tagged with this scenario
INSTANCE_IDS=$(aws ec2 describe-instances \
  --filters "Name=tag:Scenario,Values=code-judge-escape" \
            "Name=instance-state-name,Values=running,stopped" \
  --query 'Reservations[].Instances[].InstanceId' --output text)
if [ -n "$INSTANCE_IDS" ]; then
  aws ec2 terminate-instances --instance-ids $INSTANCE_IDS
fi

# Delete any leftover SSM parameters
aws ssm describe-parameters \
  --query "Parameters[?starts_with(Name, '/gnawlab/codejudge/')].Name" \
  --output text | tr '\t' '\n' | while read -r p; do
    [ -n "$p" ] && aws ssm delete-parameter --name "$p"
  done

# Delete any leftover CloudWatch log groups
aws logs describe-log-groups \
  --log-group-name-prefix "/gnawlab/codejudge/" \
  --query "logGroups[].logGroupName" --output text | tr '\t' '\n' | while read -r g; do
    [ -n "$g" ] && aws logs delete-log-group --log-group-name "$g"
  done
```

## Remove Local Files

```bash
rm -f /tmp/code-judge-*.py /tmp/code-judge-*.log
rm -f ../assets/target_info.txt
rm -f terraform/terraform.tfstate*
rm -f terraform/terraform.tfvars
rm -rf terraform/.terraform/ terraform/.terraform.lock.hcl
```

## Verify No Resources Remain

Check for remaining resources by tag:

```bash
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Scenario,Values=code-judge-escape \
  --region us-east-1 \
  --profile GnawLab
```

Should return an empty `ResourceTagMappingList`:

```json
{
    "ResourceTagMappingList": []
}
```

## Cost Verification

Check your AWS billing to ensure no unexpected charges:

1. Go to [AWS Billing Console](https://console.aws.amazon.com/billing/)
2. Check **Bills** for the current month
3. Verify EC2, NAT Gateway, and Fargate charges show only the expected usage during the scenario

> **Warning:** The NAT Gateway keeps billing until it is destroyed. Always verify cleanup before walking away.
