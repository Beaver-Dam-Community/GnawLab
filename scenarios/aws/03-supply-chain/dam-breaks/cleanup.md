# Dam Breaks - Cleanup Guide

## Automated Cleanup (Recommended)

### Step 1: Navigate to Terraform Directory
```bash
cd terraform
```

### Step 2: Destroy All Resources

> **Important:** If you exported Collaborator credentials during the exercise, unset them before running destroy. The Collaborator role lacks the permissions terraform needs to read VPC, IAM, and Secrets Manager resources — destroy will fail if those credentials are active.

```bash
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_DEFAULT_REGION
terraform destroy
```

> **Tip:** Alternatively, open a new terminal session — environment variables set with `export` do not persist across sessions.

Type `yes` when prompted.

### Step 3: Verify Cleanup
```bash
terraform show
```
Should output: `No state.` or empty state.

## Manual Cleanup Checklist

If `terraform destroy` fails, manually delete these resources in order:

### AWS Console

1. **ECS Service & Cluster**
   - Go to [ECS Console](https://console.aws.amazon.com/ecs/)
   - Find cluster containing `dam-breaks`
   - Set desired count to 0, then delete the service
   - Delete the cluster

2. **CodeBuild Projects**
   - Go to [CodeBuild Console](https://console.aws.amazon.com/codesuite/codebuild/projects)
   - Search for projects containing `dam-breaks`
   - Delete `webapp-prod-build` and `webapp-qa-build`

3. **ECR Repository**
   - Go to [ECR Console](https://console.aws.amazon.com/ecr/)
   - Search for repository containing `dam-breaks`
   - Delete all images first, then delete the repository

4. **Secrets Manager**
   - Go to [Secrets Manager Console](https://console.aws.amazon.com/secretsmanager/)
   - Search for secrets containing `beaverpay/prod`
   - Delete each secret with **force delete** (no recovery window)

5. **Cognito**
   - Go to [Cognito Console](https://console.aws.amazon.com/cognito/)
   - Delete the Identity Pool containing `dam-breaks`
   - Delete the User Pool containing `dam-breaks`

6. **EC2 Instance (Portal)**
   - Go to [EC2 Console](https://console.aws.amazon.com/ec2/)
   - Search for instance containing `dam-breaks`
   - Terminate the instance

7. **IAM Roles**
   - Go to [IAM Console → Roles](https://console.aws.amazon.com/iam/home#/roles)
   - Search for roles containing `dam-breaks`
   - Delete inline policies first, then delete the roles
   - Roles to delete:
     - `CollaboratorDeveloperRole`
     - `beaverpay-ecs-task-role`
     - `beaverpay-ecs-execution-role`
     - `CodeBuildProdServiceRole`
     - `portal-ec2-role`

8. **VPC & Networking**
   - Go to [VPC Console](https://console.aws.amazon.com/vpc/)
   - Search for VPC containing `dam-breaks`
   - Delete in order: Security Groups → Subnet → Route Table → IGW → VPC

### AWS CLI

```bash
# Set profile
export AWS_PROFILE=GnawLab
export AWS_REGION=us-east-1

# Find scenario ID from resource names
SCENARIO_ID="<your-8-char-scenario-id>"

# Delete ECS service and cluster
aws ecs update-service \
  --cluster dam-breaks-prod-cluster-${SCENARIO_ID} \
  --service dam-breaks-webapp-service-${SCENARIO_ID} \
  --desired-count 0
aws ecs delete-service \
  --cluster dam-breaks-prod-cluster-${SCENARIO_ID} \
  --service dam-breaks-webapp-service-${SCENARIO_ID} \
  --force
aws ecs delete-cluster \
  --cluster dam-breaks-prod-cluster-${SCENARIO_ID}

# Delete CodeBuild projects
aws codebuild delete-project \
  --name dam-breaks-webapp-prod-build-${SCENARIO_ID}
aws codebuild delete-project \
  --name dam-breaks-webapp-qa-build-${SCENARIO_ID}

# Delete ECR repository
aws ecr delete-repository \
  --repository-name dam-breaks-beaverpay-webapp-${SCENARIO_ID} \
  --force

# Delete Secrets Manager secrets (force delete)
aws secretsmanager delete-secret \
  --secret-id beaverpay/prod/flag-${SCENARIO_ID} \
  --force-delete-without-recovery
aws secretsmanager delete-secret \
  --secret-id beaverpay/prod/db-master-credentials-${SCENARIO_ID} \
  --force-delete-without-recovery
aws secretsmanager delete-secret \
  --secret-id beaverpay/prod/payment-gateway-api-key-${SCENARIO_ID} \
  --force-delete-without-recovery

# Delete Cognito Identity Pool
IDENTITY_POOL_ID=$(aws cognito-identity list-identity-pools \
  --max-results 10 \
  --query "IdentityPools[?contains(IdentityPoolName, 'dam-breaks')].IdentityPoolId" \
  --output text)
aws cognito-identity delete-identity-pool \
  --identity-pool-id ${IDENTITY_POOL_ID}

# Delete Cognito User Pool
USER_POOL_ID=$(aws cognito-idp list-user-pools \
  --max-results 10 \
  --query "UserPools[?contains(Name, 'dam-breaks')].Id" \
  --output text)
aws cognito-idp delete-user-pool \
  --user-pool-id ${USER_POOL_ID}
```

## Remove Local Files

```bash
# Remove Terraform state and cache
rm -rf terraform/.terraform
rm -f terraform/.terraform.lock.hcl
rm -f terraform/terraform.tfstate*

# Remove tfvars if created
rm -f terraform/terraform.tfvars
```

## Verify No Resources Remain

Check for remaining resources by tag:

```bash
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Scenario,Values=dam-breaks \
  --region us-east-1 \
  --profile GnawLab
```

Should return empty `ResourceTagMappingList`:

```json
{
    "ResourceTagMappingList": []
}
```

## Cost Verification

Check your AWS billing to ensure no unexpected charges:

1. Go to [AWS Billing Console](https://console.aws.amazon.com/billing/)
2. Check "Bills" for current month
3. Verify ECS Fargate, CodeBuild, ECR, Cognito, Secrets Manager show no charges
