output "alarm_names" {
  value = [
    aws_cloudwatch_metric_alarm.alb_5xx.alarm_name,
    aws_cloudwatch_metric_alarm.target_5xx.alarm_name,
    aws_cloudwatch_metric_alarm.asg_cpu.alarm_name,
    aws_cloudwatch_metric_alarm.unhealthy_hosts.alarm_name,
    aws_cloudwatch_metric_alarm.rds_cpu.alarm_name,
    aws_cloudwatch_metric_alarm.rds_low_storage.alarm_name,
    aws_cloudwatch_metric_alarm.rds_connections.alarm_name
  ]
}
output "sns_topic_arn" { value = aws_sns_topic.alarms.arn }
