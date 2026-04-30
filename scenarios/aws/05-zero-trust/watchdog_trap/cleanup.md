# Cleanup

## Auto Cleanup

```bash
cd terraform
terraform destroy -auto-approve
```

## Manual Cleanup

Some resources must be cleaned up manually before `terraform destroy` can succeed, as Terraform cannot delete non-empty S3 buckets or ECR repositories.

Perform the following steps **before** running `terraform destroy`:

- [ ] Stop any running CodePipeline executions
  ```bash
  aws codepipeline stop-pipeline-execution \
    --pipeline-name jsn-pipeline \
    --pipeline-execution-id <execution-id> \
    --abandon \
    --reason "cleanup"
  ```

- [ ] Delete all ECR images
  ```bash
  aws ecr list-images --repository-name jsn-app \
    --query 'imageIds[*]' --output json | \
  xargs -I{} aws ecr batch-delete-image \
    --repository-name jsn-app \
    --image-ids '{}'
  ```

- [ ] Empty S3 artifact bucket (including versioned objects)
  ```bash
  BUCKET=$(cd terraform && terraform output -raw artifact_bucket_name)
  aws s3 rm "s3://${BUCKET}" --recursive
  aws s3api list-object-versions --bucket "${BUCKET}" \
    --query 'Versions[*].{Key:Key,VersionId:VersionId}' --output json | \
  jq -r '.[] | "--key \(.Key) --version-id \(.VersionId)"' | \
  xargs -I{} sh -c "aws s3api delete-object --bucket ${BUCKET} {}"
  ```

- [ ] Set ECS service desired count to 0
  ```bash
  aws ecs update-service \
    --cluster jsn-cluster \
    --service jsn-app \
    --desired-count 0
  ```

After completing the above steps, run:

```bash
cd terraform
terraform destroy -auto-approve
```

> **Warning:** Always verify cleanup to avoid unexpected AWS costs.
