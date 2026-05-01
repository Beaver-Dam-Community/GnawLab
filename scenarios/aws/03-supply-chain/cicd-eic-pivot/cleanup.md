# CI/CD EIC Pivot - Cleanup Guide

## Automated Cleanup (Recommended)

### Step 1: Navigate to Terraform Directory

```bash
cd terraform
```

### Step 2: Destroy All Resources

```bash
terraform destroy
```

Type `yes` when prompted.

### Step 3: Verify Cleanup

```bash
terraform show
```

Should output: `No state.` or empty state.

## Manual Cleanup Checklist

Before running `terraform destroy`, remove any resources you created manually during the scenario:

- [ ] Temporary SSH key pair: `/tmp/eic-key`, `/tmp/eic-key.pub`
- [ ] AWS environment variables configured with the stolen Atlantis credentials
- [ ] Local `infra-repo` clone if created during the scenario (`terraform/infra-repo/`)

If Terraform destroy fails, manually delete these resources:

### AWS Console

1. **EC2 Instances**
   - Go to [EC2 Console → Instances](https://console.aws.amazon.com/ec2/home#Instances)
   - Search for instances tagged with `cicd-eic-pivot`
   - Terminate the GitLab server, Atlantis server, Bastion Host, and Target Server

2. **Security Groups**
   - Go to [EC2 Console → Security Groups](https://console.aws.amazon.com/ec2/home#SecurityGroups)
   - Search for groups containing `gnawlab-cicd-eic`
   - Delete all associated security groups (terminate instances first to release dependencies)

3. **VPC**
   - Go to [VPC Console](https://console.aws.amazon.com/vpc/)
   - Search for VPC containing `gnawlab-cicd-eic`
   - Delete subnets, route tables, and internet gateway
   - Delete the VPC

4. **IAM Roles**
   - Go to [IAM Console → Roles](https://console.aws.amazon.com/iam/home#/roles)
   - Search for roles containing `gnawlab-cicd-eic`
   - Detach and delete inline policies first
   - Delete the roles and instance profiles

5. **SSM Parameter**
   - Go to [Systems Manager → Parameter Store](https://console.aws.amazon.com/systems-manager/parameters)
   - Search for parameters containing `atlantis-gitlab-token`
   - Delete the parameter

### AWS CLI

```bash
# Set profile
export AWS_PROFILE=GnawLab
export AWS_REGION=us-east-1

# Terminate all EC2 instances tagged with this scenario
INSTANCE_IDS=$(aws ec2 describe-instances \
  --filters "Name=tag:Scenario,Values=cicd-eic-pivot" \
            "Name=instance-state-name,Values=running,stopped" \
  --query 'Reservations[].Instances[].InstanceId' \
  --output text)

aws ec2 terminate-instances --instance-ids $INSTANCE_IDS

# Delete SSM parameter
aws ssm delete-parameter --name "/gnawlab-cicd-eic-<scenario_id>/atlantis-gitlab-token"
```

## Remove Local Files

```bash
rm -f /tmp/eic-key /tmp/eic-key.pub
rm -rf terraform/infra-repo/
rm -f terraform/terraform.tfstate*
rm -f terraform/terraform.tfvars
```

## Verify No Resources Remain

Check for remaining resources by tag:

```bash
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Scenario,Values=cicd-eic-pivot \
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
3. Verify EC2 charges show only the expected usage during the scenario

> **Warning:** The GitLab server uses a `t3.large` instance (~$0.08/hour). Always verify cleanup to avoid unexpected charges.
