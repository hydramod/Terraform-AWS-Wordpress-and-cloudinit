variable "ami_id" {
  description = "Default image to use"
  default     = "ami-0360c520857e3138f"
  type        = string
}

variable "instance_type" {
  description = "Default EC2 instance type"
  default     = "t3.micro"
  type        = string
}

variable "subnet_id" {
  description = "Subnet id"
  default     = "subnet-05925340419cda411"
  type        = string
}

variable "key_name" {
  description = "Name of the SSH key pair"
  type        = string
}

variable "db_name" {
  default = "wordpress"
  type    = string
}

variable "db_user" {
  description = "db user name"
  type        = string
}

variable "db_password" {
  description = "db user password"
  type        = string
}
