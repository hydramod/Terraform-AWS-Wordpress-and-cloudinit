output "public_ip" {
  value       = module.wordpress.public_ip
  description = "Public IP of the WordPress instance"
}

output "instance_id" {
  value       = module.wordpress.instance_id
  description = "Instance ID of the WordPress instance"
}

output "site_url" {
  value       = module.wordpress.url
  description = "Open this in your browser"
}
