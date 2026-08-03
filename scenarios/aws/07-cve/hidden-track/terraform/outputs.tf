output "portal_url" {
  description = "BeaverSound artist portal URL"
  value       = "http://${aws_instance.portal.public_ip}"
}
