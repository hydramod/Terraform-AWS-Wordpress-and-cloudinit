output "public_ip" {
  description = "Public IP of the WordPress EC2 instance"
  value       = aws_instance.wordpress.public_ip
}

output "instance_id" {
  description = "ID of the WordPress EC2 instance"
  value       = aws_instance.wordpress.id
}

output "url" {
  description = "URL for WordPress"
  value       = "http://${aws_instance.wordpress.public_ip}"
}
