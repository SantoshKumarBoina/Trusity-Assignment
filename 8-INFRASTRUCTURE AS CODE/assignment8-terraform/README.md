# XYZZ Orders — AWS EC2 Terraform Assessment

This repository defines an assessment environment for an order-management service. It uses an internet-facing Application Load Balancer, EC2 Auto Scaling across two Availability Zones, private RDS for PostgreSQL, private S3 storage, IAM instance roles, Secrets Manager-managed RDS credentials, and CloudWatch alarms with optional SNS email notifications.

> **Scope:** The EC2 user data currently launches a placeholder Nginx container for infrastructure smoke testing. It is not the FastAPI order application and does not connect to RDS. Replace it with the assessment's actual, versioned application image and validate the database connection before claiming end-to-end functionality.

## Architecture and modules

- `terraform/modules/networking`: VPC, public/app/database subnets, route tables, IGW, per-AZ NAT Gateways.
- `terraform/modules/security`: ALB, EC2 and database security groups.
- `terraform/modules/alb`: ALB, target group, HTTP listener and optional HTTPS listener/HTTP redirect when an ACM certificate ARN is supplied.
- `terraform/modules/compute`: EC2 launch template, SSM/IAM instance profile, ASG and CPU target-tracking policy.
- `terraform/modules/database`: private PostgreSQL RDS, encryption, automated backups, optional Multi-AZ, CloudWatch log exports and RDS-managed master credentials in Secrets Manager.
- `terraform/modules/storage`: private encrypted S3 bucket, versioning and lifecycle for noncurrent versions.
- `terraform/modules/monitoring`: CloudWatch alarms and an SNS topic; an email subscription is created only when `alarm_notification_email` is set.
- `architecture/ARCHITECTURE.md`: architecture rationale and design decisions.
- `terraform-state-bootstrap/`: separate starter to create an encrypted/versioned S3 state bucket and DynamoDB locking table.

## Configuration

Copy `terraform/terraform.tfvars.example` to `terraform/terraform.tfvars` and edit values for your account. Never commit the real `.tfvars` file.

The defaults reflect the assessment setup: region `ap-south-1`, VPC `10.20.0.0/16`, two AZs, `t3.micro`, ASG desired/min/max `2/2/4`, RDS `db.t3.micro`, Multi-AZ enabled, and 7-day backup retention. Costs vary by region, instance, Multi-AZ and NAT usage. Two NAT Gateways, ALB and Multi-AZ RDS can cost money even at low traffic.

### HTTPS

For assessment smoke testing, the ALB uses HTTP. For HTTPS, request/validate an ACM certificate in the same AWS Region as the ALB, set `certificate_arn` in your tfvars, and configure DNS for your domain. When the ARN is set, port 80 redirects to HTTPS and the ALB listens on 443. Do not put a made-up certificate ARN in configuration.

### Alarm email

Set `alarm_notification_email` to an operational mailbox if you want email alerts. AWS sends a confirmation email; the recipient must confirm the subscription. Leave blank to create the SNS topic without an email subscription.

## Terraform state and locking

1. Use `terraform-state-bootstrap/` to create a dedicated S3 state bucket with public access blocked, encryption, versioning, and a DynamoDB lock table.
2. Keep the bootstrap's initial local state securely outside Git. For a team environment, use a separately managed bootstrap state/account.
3. Copy `terraform/backend.tf.example` to `terraform/backend.tf`; replace the bucket placeholder with your actual bucket name.
4. Back up the current local state securely, then run `terraform init -migrate-state` from `terraform/` to migrate it into S3. Do not delete the local backup until the remote state is confirmed.
5. Restrict bucket and lock-table access to the deployment roles. State may contain sensitive infrastructure data even when passwords are managed by AWS.

DynamoDB locking is included for compatibility with Terraform 1.5.x. Follow Terraform's version-specific guidance before switching to native S3 lockfiles or removing the lock table.

## Environments

Example overrides are under `terraform/environments/`:

```powershell
terraform plan -var-file="environments/dev.tfvars.example"
```

Copy the examples to environment-specific local `.tfvars` files (or CI-provided files) before using them. The same root configuration can be used with separate state keys per environment, such as `xyzz-orders/dev/terraform.tfstate`, `xyzz-orders/staging/terraform.tfstate`, and `xyzz-orders/prod/terraform.tfstate`. For stronger isolation, use separate AWS accounts and separate state buckets for production. Never point development commands at production state.

Production example settings enable deletion protection, retain final snapshots with an explicitly configured unique snapshot identifier, and extend backup retention. Update the final snapshot identifier before each planned final snapshot to avoid name collisions. Assess these settings before using a destroy operation; deleting a protected RDS instance requires a deliberate change to disable protection first.

## Recommended workflow

Run from the `terraform/` directory:

```powershell
terraform fmt -recursive
terraform init
terraform validate
terraform plan -out=tfplan
terraform show tfplan
# Apply only after reviewing the plan and confirming the target AWS account/region:
terraform apply tfplan
```

For a fresh environment, `terraform init` needs AWS access and provider download access. For an existing deployment, do not blindly apply changes: review replacement/destroy actions, particularly RDS, subnet, security group, and ALB changes. Use a pull request, peer review, plan artifact, approval gate, and a controlled deployment role for production. Keep Terraform and provider versions pinned/consistent in CI.

## Secrets and access

- Use AWS profiles or workload identity/role assumption; do not put access keys in `.tf` or `.tfvars` files.
- RDS manages its master password in Secrets Manager using `manage_master_user_password = true`, so Terraform does not receive the password as an input.
- The EC2 role is granted `secretsmanager:GetSecretValue` only for the RDS-managed secret ARN. The actual app still needs to fetch the secret at runtime and use a least-privilege application database user where practical.
- Terraform state and plan files can still contain sensitive infrastructure information. Restrict access, encrypt state, and never commit them.
- S3 blocks public access, enforces TLS-only requests, enables encryption and versioning, and expires noncurrent versions based on the configured lifecycle policy.
- IMDSv2 is required for EC2 metadata access. Systems Manager access is attached through the instance role.

## Production hardening and limitations

- Configure a real domain and ACM certificate for HTTPS. AWS WAF, CloudTrail organization trails, VPC Flow Logs, CI/CD deployment, container scanning, and an application-specific health endpoint are useful additional production controls; they are documented considerations rather than all being enabled by this starter.
- The target group health check currently uses `/` to work with the placeholder Nginx container. Change it to `/health` when the FastAPI application is deployed and verified.
- CloudWatch alarm thresholds are starting points; tune them using load tests and workload baselines. SNS email is optional and requires confirmation.
- NAT Gateways, ALB, RDS Multi-AZ, log exports and EC2 incur costs. Review the plan and current AWS pricing before apply.
- This code has not been applied or validated against your AWS account as part of this package preparation. Run formatting, init, validation and plan in your environment, then inspect the plan carefully.

## Cleanup

For a disposable assessment environment, confirm `enable_deletion_protection = false` and `skip_final_snapshot = true` before destroying. For staging/production, do not skip final snapshots; follow the approved backup and decommission process. Destroy the application stack before considering removal of the separate state backend, and retain state backups according to policy.
