variable "aws_region" {
  type        = string
  description = "AWS Region"
  default     = "ap-south-1"
}
variable "project_name" {
  type        = string
  description = "Short name used in resource names"
  default     = "xyzz-orders"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name)) && length(var.project_name) <= 20
    error_message = "project_name must contain lowercase letters, digits, and hyphens and be at most 20 characters."
  }
}
variable "environment" {
  type        = string
  description = "Deployment environment: assessment, dev, staging, or prod"
  default     = "assessment"
  validation {
    condition     = contains(["assessment", "dev", "staging", "prod"], var.environment)
    error_message = "environment must be assessment, dev, staging, or prod."
  }
}
variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}
variable "availability_zones" {
  type        = list(string)
  description = "Two AZs in the selected Region"
  default     = ["ap-south-1a", "ap-south-1b"]
  validation {
    condition     = length(var.availability_zones) == 2
    error_message = "Provide exactly two Availability Zones."
  }
}
variable "instance_type" {
  type    = string
  default = "t3.micro"
}
variable "ami_id" {
  type        = string
  description = "Optional AMI override. Leave blank to use the latest Amazon Linux 2023 x86_64 AMI."
  default     = ""
}
variable "desired_capacity" {
  type    = number
  default = 2
}
variable "min_size" {
  type    = number
  default = 2
}
variable "max_size" {
  type    = number
  default = 4
}
variable "app_port" {
  type    = number
  default = 80
}
variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}
variable "db_name" {
  type    = string
  default = "orders"
}
variable "db_username" {
  type    = string
  default = "orders_app"
}
variable "multi_az" {
  type    = bool
  default = true
}
variable "enable_deletion_protection" {
  type        = bool
  description = "Enable RDS deletion protection. Set true for staging/production."
  default     = false
}
variable "skip_final_snapshot" {
  type        = bool
  description = "Skip final RDS snapshot on destroy. Use true only for disposable assessment/dev environments."
  default     = true
}
variable "final_snapshot_identifier" {
  type        = string
  description = "Unique RDS final snapshot identifier required when skip_final_snapshot is false."
  default     = ""
}
variable "db_backup_retention_days" {
  type        = number
  description = "RDS automated backup retention in days (1-35; 0 disables backups)."
  default     = 7
  validation {
    condition     = var.db_backup_retention_days >= 0 && var.db_backup_retention_days <= 35
    error_message = "db_backup_retention_days must be between 0 and 35."
  }
}
variable "alarm_notification_email" {
  type        = string
  description = "Optional email for CloudWatch alarm notifications; leave blank to create topic without subscription. Confirm subscription in email."
  default     = ""
  validation {
    condition     = var.alarm_notification_email == "" || can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alarm_notification_email))
    error_message = "alarm_notification_email must be blank or a valid email address."
  }
}
variable "enable_s3_versioning" {
  type    = bool
  default = true
}
variable "s3_noncurrent_version_expiration_days" {
  type        = number
  description = "Days to retain noncurrent artifact bucket versions before expiration."
  default     = 90
}

variable "certificate_arn" {
  type        = string
  description = "Optional ACM certificate ARN in the same Region as the ALB. When set, HTTP redirects to HTTPS."
  default     = ""
}
