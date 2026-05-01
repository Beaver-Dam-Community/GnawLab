output "scenario_entrypoint_url" {
  description = "Hand this URL to the participant. Nothing else."
  value       = "http://${aws_instance.public_gateway_ec2.public_ip}/"
}