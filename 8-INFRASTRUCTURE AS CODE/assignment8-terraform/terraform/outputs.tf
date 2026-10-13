output "application_url" {
  description = "HTTP URL of the Application Load Balancer (assessment only; use HTTPS in production)"
  value       = "http://${module.alb.alb_dns_name}"
}
output "alb_dns_name" { value = module.alb.alb_dns_name }
output "autoscaling_group_name" { value = module.compute.autoscaling_group_name }
output "rds_endpoint" {
  description = "Private database endpoint; not publicly accessible"
  value       = module.database.db_address
}
output "db_secret_arn" {
  description = "ARN of the Secrets Manager secret containing database credentials; this is not the secret value."
  value       = module.database.secret_arn
}
output "s3_bucket_name" { value = module.storage.bucket_name }
output "cloudwatch_alarm_names" { value = module.monitoring.alarm_names }
output "alarm_sns_topic_arn" { value = module.monitoring.sns_topic_arn }
