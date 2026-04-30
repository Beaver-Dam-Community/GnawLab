resource "local_file" "gitlab_credentials" {
  content         = "URL: http://${aws_instance.gitlab_server.public_ip}\nUsername: 000_ops\nPassword: BeaverPassword123!\n"
  filename        = "${path.module}/../assets/gitlab_credentials.txt"
  file_permission = "0644"
}

output "gitlab_server_url" {
  value       = "http://${aws_instance.gitlab_server.public_ip}"
  description = "URL of the GitLab server (starting point — may take 10-15 min to fully initialize)"
}

output "atlantis_runner_public_ip" {
  value       = aws_instance.atlantis_server.public_ip
  description = "Public IP of the Atlantis Runner"
}

output "bastion_host_id" {
  value       = aws_instance.bastion_host.id
  description = "EC2 Instance ID of the Bastion Host (EIC target)"
}

output "bastion_host_public_ip" {
  value       = aws_instance.bastion_host.public_ip
  description = "Public IP of the Bastion Host"
}

output "target_server_private_ip" {
  value       = aws_instance.target_server.private_ip
  description = "Private IP of the Target Server (final goal)"
}

output "instructions" {
  value = <<EOF
=== supply_chain_eic_pivot ===
NOTE: GitLab takes 10-15 minutes to fully initialize after terraform apply.

1. Log in to GitLab at http://${aws_instance.gitlab_server.public_ip}
   Credentials are saved to assets/gitlab_credentials.txt (Username: 000_ops / Password: BeaverPassword123!)

2. Explore infra-repo and analyze atlantis.yaml for the pipeline vulnerability.

3. Poison the pipeline to steal the Atlantis IAM credentials via IMDS.

4. Use the stolen credentials to inject your SSH key into the Bastion Host (${aws_instance.bastion_host.id}) via EC2 Instance Connect.

5. SSH into the Bastion Host and find the key to pivot into the Target Server (${aws_instance.target_server.private_ip}).

6. Capture the flag: cat /home/ubuntu/flag.txt
EOF
}
