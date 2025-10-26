resource "aws_instance" "wordpress" {
  ami                     = var.ami_id
  instance_type           = var.instance_type
  key_name                = var.key_name
  vpc_security_group_ids  = [aws_security_group.wp_sg.id]
  subnet_id               = var.subnet_id
  user_data               = templatefile("${path.module}/cloud-init.yaml", {
    db_name               = var.db_name
    db_user               = var.db_user
    db_password           = var.db_password
  })

  user_data_replace_on_change = true

  tags = {
    Name = "WordPress-Server"
  }
}

resource "aws_security_group" "wp_sg" {
  name        = "wordpress-sg"
  description = "Security group for WordPress"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
