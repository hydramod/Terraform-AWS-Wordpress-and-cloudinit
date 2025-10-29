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

## CI pipeline (GitHub Actions)

* **Workflow:** `.github/workflows/terraform-ci.yaml`

* **Triggers:** PRs and pushes to `main` that touch `*.tf`, `*.tfvars`, `.tflint.hcl`, or `.tfsec.yml`

* **Jobs:**

  * **`lint-validate`** (runs for `.` and `bootstrap`)

    * `terraform fmt -check -recursive`
    * `terraform init -backend=false` (no remote state needed for validation)
    * `terraform validate`
    * **TFLint:** sets up TFLint, caches plugins, runs `tflint`
    * **tfsec:** runs the tfsec SARIF action and uploads results to Code Scanning

  * **`plan`** (runs for `.` and `bootstrap`)

    * Configures AWS credentials from repo secrets (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`)
    * **Smart init:** checks if the S3 bucket exists; if yes, initializes the S3 backend; otherwise uses local (`terraform init -backend=false`)
    * Runs `terraform plan`, optionally with `-var-file=terraform.tfvars` if present
    * If you later enable the S3 backend in code, the workflow uses `terraform init -reconfigure` to adopt the remote backend; reconfigure is required whenever backend settings change

* **Required GitHub Actions secrets:**

  * `AWS_ACCESS_KEY_ID`
  * `AWS_SECRET_ACCESS_KEY`

* **Optional (variables via env/secrets):**

  * `TF_VAR_key_name`, `TF_VAR_db_name`, `TF_VAR_db_user`, `TF_VAR_db_password`
    Terraform will use any `TF_VAR_*` environment variables as input variables.

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

Note: Below steps are troubleshooting that occured during implenentation of the CI

### 8) `terraform fmt -check` fails (exit code 3)

This means some files aren’t formatted. Fix locally, commit, and push:

```bash
terraform fmt -recursive
git add -A && git commit -m "fmt: normalize Terraform formatting"
```

In CI we keep `-check` so it fails when files drift from canonical formatting.

### 9) TFLint: `Failed to initialize plugins; Plugin "aws" not found. Did you run "tflint --init"?`

Add a plugin init step and (optionally) cache TFLint plugins:

```yaml
- uses: terraform-linters/setup-tflint@v4
- uses: actions/cache@v4
  with:
    path: ~/.tflint.d/plugins
    key: tflint-plugins-${{ runner.os }}-${{ hashFiles('.tflint.hcl') }}
- run: tflint --init
```

The `--init` step downloads the ruleset declared in `.tflint.hcl` (e.g., the AWS ruleset).

### 10) TFLint v0.54+: `\"module\" attribute was removed… use \"call_module_type\" instead`

Update your `.tflint.hcl` to the new schema (`call_module_type` replaces `module`). Example:

```hcl
config { call_module_type = "all" }  # instead of `module = true`
```

See the breaking-change note in the TFLint project.

### 11) tfsec action cannot be resolved / version not found

Use the maintained SARIF action and pin a valid version:

```yaml
- uses: aquasecurity/tfsec-sarif-action@v0.1.4
  with:
    working_directory: ${{ matrix.workdir }}
    sarif_file: tfsec.sarif
```

This action runs tfsec and produces a SARIF file for upload.

### 12) SARIF upload: `Resource not accessible by integration` or “missing token/permission”

Ensure job/workflow permissions include:

```yaml
permissions:
  actions: read
  contents: read
  security-events: write
```

Then upload with:

```yaml
- uses: github/codeql-action/upload-sarif@v3
  with:
    sarif_file: tfsec.sarif
    category: tfsec-${{ matrix.workdir }}
```

GitHub requires proper permissions to accept SARIF uploads; missing `security-events: write` (and sometimes `actions: read`) will cause failures.

### 13) SARIF path mismatch: `Path does not exist: bootstrap/tfsec.sarif`

Set `sarif_file` relative to the repo root (or provide a full path) and be consistent with `working_directory`. For matrix builds:

```yaml
- uses: aquasecurity/tfsec-sarif-action@v0.1.4
  with:
    working_directory: ${{ matrix.workdir }}
    sarif_file: ${{ matrix.workdir }}/tfsec.sarif

- uses: github/codeql-action/upload-sarif@v3
  with:
    sarif_file: ${{ matrix.workdir }}/tfsec.sarif
```

### 14) Backend S3 bucket missing (CI): fall back to local

If the S3 bucket isn’t available, re-init with local backend; when you later enable S3, reconfigure the backend:

```bash
terraform init -reconfigure \
  -backend-config="bucket=..." \
  -backend-config="key=..." \
  -backend-config="region=..."
```

Reconfiguration is required whenever backend settings change.

### 15) `No value for required variable` (plan stage)

Provide required input variables either via a checked-in `terraform.tfvars` (for non-secrets) or via environment variables (`TF_VAR_*`) in CI secrets:

```yaml
env:
  TF_VAR_key_name: ${{ secrets.TF_VAR_key_name }}
  TF_VAR_db_name: ${{ secrets.TF_VAR_db_name }}
  TF_VAR_db_user: ${{ secrets.TF_VAR_db_user }}
  TF_VAR_db_password: ${{ secrets.TF_VAR_db_password }}
```

Terraform automatically reads `TF_VAR_*` env vars and auto-loads any `*.auto.tfvars` files.

### 16) Switching from S3 → local (or vice versa) mid-run

If you toggled the backend (e.g., deleted the bucket or commented the block), run a fresh init with `-reconfigure` and clear the `.terraform/` dir to avoid stale state metadata:

```bash
rm -rf .terraform
terraform init -reconfigure
```

Backend changes always require reinitialization.

---

## Costs & cleanup

This spins up a single **t3.micro** EC2 and storage. Costs are usually cents per hour, but **destroy** when done:
```
terraform destroy -auto-approve
```
