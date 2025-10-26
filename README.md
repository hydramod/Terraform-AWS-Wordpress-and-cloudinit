# Terraform: WordPress on AWS with Cloud‑Init and optional S3 backend bootstrap

Provision a single EC2 instance running **WordPress** on **Ubuntu** using **Terraform** and **cloud‑init**.  
State is stored remotely in **S3** (optional bootstrap included).

---

## What you’ll build

- **EC2** (t3.micro by default) in your default VPC/subnet
- **Security Group** allowing **HTTP (80)** and **SSH (22)**
- **cloud‑init** installs Apache, PHP, MySQL, downloads WordPress, creates DB/user, and configures `wp-config.php`
- Terraform **module** `modules/wordpress` encapsulates the instance & SG
- Root module wires variables and prints handy outputs (IP + URL)

> For simplicity this uses a single instance with a local MySQL server. For production, use **RDS/MySQL**, an **ALB**, and Auto Scaling.

---

## Repo layout

```
Terraform-AWS-Wordpress-and-cloudinit/
├─ main.tf                   # Calls module.wordpress
├─ variables.tf              # Root variables (region, ami_id, instance_type, key_name, db_*)
├─ outputs.tf                # Root outputs: public_ip, instance_id, site_url
├─ provider.tf               # Provider + (optional) S3 backend
├─ terraform.tfvars          # Your values (key_name, db_user, db_password, etc.)
├─ cloud-init.yaml           # The cloud-init used by the instance (templated by Terraform)
├─ modules/
│  └─ wordpress/
│     ├─ main.tf            # EC2 + Security Group
│     ├─ variables.tf       # Module variables
│     └─ outputs.tf         # Module outputs (public_ip, instance_id, url)
└─ bootstrap/                # Optional: tiny project to create the S3 bucket for backend
   ├─ main.tf
   └─ variables.tf
```

> If you don’t see some of these files yet, add them as shown here. The project works even without `bootstrap/` (you can start with local state).

---

## Prerequisites

- **Terraform v1.6+**
- **AWS credentials** on your machine (`aws configure`, SSO, or env vars)
- An existing **EC2 key pair** in the target region 
- (Optional) **S3 bucket** for backend state (you can bootstrap it below)

---

## Backend (S3 only, minimal)

If your backend block looks like this:

```hcl
terraform {
  backend "s3" {
    bucket = "terraform-wp-ec2"
    key    = "terraform.tfstate"
    region = "us-east-1"
  }
}
```

### Option A — Create the bucket once via **bootstrap/**
```
cd bootstrap
terraform init
terraform apply -auto-approve -var="bucket_name=terraform-wp-ec2" -var="region=us-east-1"
```

Back in the root:
```
cd ..
terraform init -reconfigure
```

### Option B — Start with local state
Comment out the backend block, run with local state, then migrate later:
```
terraform init
# later:
terraform init -reconfigure   -backend-config="bucket=terraform-wp-ec2"   -backend-config="key=terraform.tfstate"   -backend-config="region=us-east-1"
```

---

## Configure variables

Root **`variables.tf`** declares inputs; **`terraform.tfvars`** supplies your values (kept out of Git). Example:

```hcl
# terraform.tfvars
key_name    = "your key name"
db_user     = "admin"
db_password = "test@123"

# Optional overrides (defaults exist for these)
# region        = "us-east-1"
# ami_id        = "ami-0360c520857e3138f"
# instance_type = "t3.micro"
# db_name       = "wordpress"
```

The root calls the module like this:
```hcl
module "wordpress" {
  source        = "./modules/wordpress"
  ami_id        = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name
  db_name       = var.db_name
  db_user       = var.db_user
  db_password   = var.db_password
}
```

---

## Cloud‑init (user‑data)

`cloud-init.yaml` is rendered with your DB variables using `templatefile(...)`. The EC2 resource sets:

```hcl
user_data = templatefile("${path.module}/cloud-init.yaml", {
  db_name     = var.db_name
  db_user     = var.db_user
  db_password = var.db_password
})
user_data_replace_on_change = true
```

**Key packages**: `apache2`, `libapache2-mod-php`, `mysql-server`, `php-*`, `wget`, `unzip`  
**Note**: We intentionally **omit** the deprecated `php-xmlrpc` package (causes `apt` error 100).

---

## Deploy

```bash
terraform fmt -recursive
terraform validate
terraform plan
terraform apply -auto-approve
```

**Outputs you’ll see:**
- `public_ip` – the instance public IP
- `instance_id` – the instance ID
- `site_url` – convenience URL: `http://<public_ip>`

Browse to **`site_url`** and complete the WordPress setup wizard.

---

## Verify on the instance (optional)

```bash
ssh -i <your-key>.pem ubuntu@<public_ip>

# cloud-init finished?
cloud-init status --long
sudo tail -n 200 /var/log/cloud-init-output.log

# Apache healthy?
sudo systemctl status apache2 --no-pager
curl -I http://127.0.0.1

# WordPress files present and configured?
ls -la /var/www/html | head -20
sudo grep -n "DB_NAME\|DB_USER\|DB_PASSWORD" /var/www/html/wp-config.php
```

---

## Destroy

```bash
terraform destroy -auto-approve
```

If you used resource targeting during debugging, run a normal plan/apply/destroy afterward to ensure no drift remains.

---

## Troubleshooting

### 1) Public IP but no site
- **Security Group** must allow inbound **TCP 80** from `0.0.0.0/0`.
- **Associate public IP** must be true, and subnet must route to an Internet Gateway.
- On the instance, `curl -I http://127.0.0.1` should return `200 OK`. If it does but your browser doesn’t, it’s a networking/SG route issue.

### 2) `cloud-init` shows **exit code 100** on package install
`php-xmlrpc` is removed in recent repos. Use this packages list (already in this repo):
```
apache2, libapache2-mod-php, mysql-server, php, php-mysql, php-curl,
php-gd, php-mbstring, php-xml, php-soap, php-intl, php-zip, unzip, wget
```
Check logs:
```
cloud-init status --long
sudo tail -n 200 /var/log/cloud-init-output.log
```

### 3) Variables not templated in `cloud-init.yaml`
If `/var/lib/cloud/instance/user-data.txt` shows literal `${db_name}`, you used `file(...)` instead of `templatefile(...)`.
Fix the EC2 resource:
```hcl
user_data = templatefile("${path.module}/cloud-init.yaml", {
  db_name     = var.db_name
  db_user     = var.db_user
  db_password = var.db_password
})
user_data_replace_on_change = true
```

### 4) Need to re-run `cloud-init` (force new instance)
Any of these works:
```bash
terraform apply -replace="module.wordpress.aws_instance.wordpress"
# OR
terraform taint module.wordpress.aws_instance.wordpress && terraform apply
# OR
terraform destroy -target="module.wordpress" -auto-approve && terraform apply -auto-approve
```

### 5) Backend error: “S3 bucket … does not exist”
Create the bucket once (via `bootstrap/` or CLI), then:
```
terraform init -reconfigure
```
Bucket names are **global**; choose a unique one.

### 6) Outputs show unknowns or errors
- Root cannot reference `aws_instance.wordpress.*` directly because that resource is **inside the module**.  
  Use module outputs:
  ```hcl
  # modules/wordpress/outputs.tf
  output "public_ip"   { value = aws_instance.wordpress.public_ip }
  output "instance_id" { value = aws_instance.wordpress.id }
  output "url"         { value = "http://${aws_instance.wordpress.public_ip}" }

  # root/outputs.tf
  output "public_ip"   { value = module.wordpress.public_ip }
  output "instance_id" { value = module.wordpress.instance_id }
  output "site_url"    { value = module.wordpress.url }
  ```

### 7) MySQL/WordPress login fails
- Confirm DB exists and user has privileges:
  ```bash
  sudo mysql -e "SHOW DATABASES LIKE 'wordpress';"
  sudo mysql -e "SELECT User, Host FROM mysql.user;"
  ```
- Recreate `wp-config.php` or update credentials as needed.

---

## Costs & cleanup

This spins up a single **t3.micro** EC2 and storage. Costs are usually cents per hour, but **destroy** when done:
```
terraform destroy -auto-approve
```
