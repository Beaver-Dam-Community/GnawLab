# Cleanup

> **Security Note**: Use placeholders for all AWS Account IDs, Access Keys, and Secret Keys.
> - Account ID: `123456789012`
> - Access Key: `AKIAIOSFODNN7EXAMPLE` or `ASIAXXXXXXXXXXX`
> - Secret Key: `xxxxxxxx` or mask actual values

## Auto Cleanup

```bash
cd terraform
terraform destroy
```

## Manual Cleanup

If you created any resources manually during the scenario, remove them before running `terraform destroy`:

- [ ] Resource 1
- [ ] Resource 2
