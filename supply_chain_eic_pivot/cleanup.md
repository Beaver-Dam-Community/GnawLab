# supply_chain_eic_pivot — Cleanup

## Auto Cleanup

```bash
cd terraform
terraform destroy -var='cg_whitelist=["<YOUR_PUBLIC_IP>/32"]'
```

## Manual Cleanup

If you created any resources manually during the scenario, remove them before running `terraform destroy`:

- [ ] Temporary SSH key pair generated during the exploit (`/tmp/eic-key`, `/tmp/eic-key.pub`)
- [ ] AWS CLI profile or environment variables configured with the stolen Atlantis credentials
- [ ] Any Merge Requests or branches created in the GitLab instance (destroyed with the EC2 instance)
- [ ] The SSM parameter `/<scenario_name>-<beaver_id>/atlantis-gitlab-token` (removed by `terraform destroy`)

> **Warning:** Always verify cleanup to avoid unexpected AWS costs. The GitLab server uses a `t3.large` instance which will continue to incur charges if not destroyed.
