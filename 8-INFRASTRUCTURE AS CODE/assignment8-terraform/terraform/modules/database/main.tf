resource "aws_db_subnet_group" "this" {
  name       = "${var.project_name}-db-subnets"
  subnet_ids = var.db_subnet_ids
}
resource "aws_db_instance" "this" {
  lifecycle {
    precondition {
      condition     = var.skip_final_snapshot || length(var.final_snapshot_identifier) > 0
      error_message = "Set final_snapshot_identifier when skip_final_snapshot is false. Use a unique identifier for each final snapshot."
    }
  }
  identifier                  = "${var.project_name}-postgres"
  engine                      = "postgres"
  engine_version              = "16"
  instance_class              = var.db_instance_class
  allocated_storage           = 20
  max_allocated_storage       = 100
  storage_type                = "gp3"
  storage_encrypted           = true
  db_name                     = var.db_name
  username                    = var.db_username
  manage_master_user_password = true
  port                        = 5432
  db_subnet_group_name        = aws_db_subnet_group.this.name
  vpc_security_group_ids      = [var.db_security_group_id]
  publicly_accessible         = false
  multi_az                    = var.multi_az
  backup_retention_period     = var.backup_retention_days
  auto_minor_version_upgrade  = true
  deletion_protection         = var.enable_deletion_protection
  skip_final_snapshot         = var.skip_final_snapshot
  final_snapshot_identifier   = var.skip_final_snapshot ? null : var.final_snapshot_identifier
  copy_tags_to_snapshot       = true
  apply_immediately           = false
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  tags = { Name = "${var.project_name}-postgres" }
}
