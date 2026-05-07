# Scenario Name - Cleanup Guide

## Before You Destroy

> Some scenarios require pre-cleanup steps before `terraform destroy` will succeed.
> Common cases:
> - S3 buckets with versioning enabled → must be emptied first
> - ECR repositories → must delete all images first
> - Active pipeline executions → must be stopped first
> - Long-running services (ECS, CodeDeploy) → may need draining
>
> If this scenario has none of the above, delete this section.

### Pre-Cleanup Checklist

- [ ] Pre-cleanup step 1
- [ ] Pre-cleanup step 2

---

## Automated Cleanup (Recommended)

```bash
cd terraform
terraform destroy
```

Type `yes` when prompted.

### Verify Cleanup

```bash
terraform show
# expected: "No state."

aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Scenario,Values=<scenario-name> \
  --region us-east-1 \
  --profile GnawLab
# expected: empty ResourceTagMappingList
```

---

## Manual Cleanup Checklist

If `terraform destroy` fails, manually delete these resources in order:

### AWS Console

1. **Resource 1**
   - Go to [Service Console](https://console.aws.amazon.com/)
   - Search for resources containing `gnawlab-<scenario-name>`
   - Delete dependents first, then the resource

2. **Resource 2**
   - ...

### AWS CLI

```bash
export AWS_PROFILE=GnawLab

# Find and delete resources by name pattern
RESOURCE=$(aws <service> list-... | grep gnawlab-<scenario-name> | ...)
if [ -n "$RESOURCE" ]; then
  aws <service> delete-... --id $RESOURCE
fi
```

---

## Remove Local Files

```bash
rm -rf terraform/.terraform
rm -f terraform/.terraform.lock.hcl
rm -f terraform/terraform.tfstate*
rm -f terraform/terraform.tfvars
```

---

## Cost Verification

1. Go to [AWS Billing Console](https://console.aws.amazon.com/billing/)
2. Check "Bills" for current month
3. Verify relevant services show minimal or no charges
