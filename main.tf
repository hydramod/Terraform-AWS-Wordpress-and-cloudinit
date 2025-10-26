module "wordpress" {
  source                  = "./modules/wordpress"
  ami_id                  = var.ami_id
  instance_type           = var.instance_type
  subnet_id               = var.subnet_id
  key_name                = var.key_name
  db_name                 = var.db_name
  db_user                 = var.db_user
  db_password             = var.db_password
}