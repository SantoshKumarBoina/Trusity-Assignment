environment = "prod"
desired_capacity = 2
min_size = 2
max_size = 8
multi_az = true
enable_deletion_protection = true
skip_final_snapshot = false
final_snapshot_identifier = "xyzz-orders-prod-final-20261013"
db_backup_retention_days = 14
# Set certificate_arn to an ACM certificate ARN for your production domain.
# Set alarm_notification_email to an operational distribution list.
