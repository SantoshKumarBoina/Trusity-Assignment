# Terraform state backend bootstrap

This folder creates a dedicated, encrypted, versioned S3 bucket for Terraform state and a DynamoDB table for state locking. Keep this bootstrap state local only temporarily and store it securely; do not commit it. For a real team, use a separately managed bootstrap state or an approved platform account.

1. Configure AWS credentials/profile and select the correct account.
2. Create `terraform.tfvars` with a globally unique bucket name, e.g. `state_bucket_name = "xyzz-terraform-state-<account-id>-<unique-suffix>"`.
3. Run `terraform init`, `terraform validate`, `terraform plan`, and review the plan.
4. Run `terraform apply` only after reviewing cost/security.
5. Copy `terraform/backend.tf.example` to `terraform/backend.tf`, replace the bucket placeholder, then from the main `terraform` folder run `terraform init -migrate-state` to migrate the existing local state. Back up the local state securely before migration and never upload it to Git.

DynamoDB-based locking is used for compatibility with Terraform versions in the 1.5.x family. If upgrading to a newer Terraform version and migrating to native S3 lockfiles, follow the version-specific Terraform documentation and remove DynamoDB locking only after migration.
