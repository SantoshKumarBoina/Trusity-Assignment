output "db_address" { value = aws_db_instance.this.address }
output "db_identifier" { value = aws_db_instance.this.identifier }
output "secret_arn" {
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
  description = "RDS-managed Secrets Manager secret ARN; the password is not stored as a Terraform input."
}
