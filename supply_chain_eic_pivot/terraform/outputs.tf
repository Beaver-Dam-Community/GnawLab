output "atlantis_runner_public_ip" {
  value       = aws_instance.atlantis_server.public_ip
  description = "Public IP of Atlantis Runner (Initial Foothold)"
}

output "bastion_host_id" {
  value       = aws_instance.bastion_host.id
  description = "EC2 Instance ID of Bastion Host (Target for EIC)"
}

output "target_server_private_ip" {
  value       = aws_instance.target_server.private_ip
  description = "Private IP of the Target Server (Final Goal)"
}

output "instructions" {
  value = <<EOF
1. GitLab 서버에 접속하여 'infra-repo'를 확인하세요.
2. 'atlantis.yaml' 설정을 분석하여 파이프라인 취약점을 찾아내세요.
3. Atlantis 권한을 탈취하여 Bastion Host(${aws_instance.bastion_host.id})에 접속을 시도하세요.
4. 최종 목표는 Private Subnet에 숨겨진 Target Server(${aws_instance.target_server.private_ip})의 플래그를 획득하는 것입니다.
EOF
}
