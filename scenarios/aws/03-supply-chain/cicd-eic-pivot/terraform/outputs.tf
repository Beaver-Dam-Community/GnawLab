resource "local_file" "gitlab_credentials" {
  content         = "URL: http://${aws_instance.gitlab_server.public_ip}\nUsername: platform\nPassword: BvrOps@2024\n"
  filename        = "${path.module}/../assets/gitlab_credentials.txt"
  file_permission = "0644"
}

output "gitlab_server_url" {
  value       = "http://${aws_instance.gitlab_server.public_ip}"
  description = "GitLab URL -- allow 15-20 min to fully initialize after apply"
}

output "instructions" {
  value = <<EOF

=== cicd-eic-pivot ===

GitLab takes 15-20 min to initialize. Check /-/health before starting.

  URL       http://${aws_instance.gitlab_server.public_ip}
  Username  platform
  Password  BvrOps@2024

  (saved to assets/gitlab_credentials.txt)

Objective: read /home/ubuntu/flag.txt from the production instance.

EOF
}
