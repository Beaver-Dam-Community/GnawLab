resource "local_file" "gitlab_credentials" {
  content         = "URL: http://${aws_instance.gitlab_server.public_ip}\nUsername: 000_ops\nPassword: BeaverPassword123!\n"
  filename        = "${path.module}/../assets/gitlab_credentials.txt"
  file_permission = "0644"
}

output "gitlab_server_url" {
  value       = "http://${aws_instance.gitlab_server.public_ip}"
  description = "URL of the GitLab server (starting point — may take 15-20 min to fully initialize)"
}

output "instructions" {
  value = <<EOF
=== gnawlab-cicd-eic ===
NOTE: GitLab takes 15-20 minutes to fully initialize after terraform apply.
Wait until http://${aws_instance.gitlab_server.public_ip} is accessible before starting.

Starting point:
  URL:      http://${aws_instance.gitlab_server.public_ip}
  Username: 000_ops
  Password: BeaverPassword123!
  (also saved to assets/gitlab_credentials.txt)

Goal: retrieve /home/ubuntu/flag.txt from the target server.
EOF
}
