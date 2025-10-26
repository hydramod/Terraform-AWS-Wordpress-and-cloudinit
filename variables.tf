variable "ami_id" {
  description = "Default image to use"
  default     = "ami-0360c520857e3138f"
}

variable "instance_type" {
  description = "Default EC2 instance type"
  default     = "t3.micro"
}

variable "subnet_id" {
  description = "Subnet id"
  default     = "subnet-05925340419cda411"
}

variable "key_name" {
  description = "Name of the SSH key pair"
}

variable "db_name" {
  description = "db name"
}

variable "db_user" {
  description = "db user name"
}

variable "db_password" {
  description = "db user password"
}
