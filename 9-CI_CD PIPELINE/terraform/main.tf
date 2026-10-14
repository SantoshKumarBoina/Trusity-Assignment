terraform {
  required_version = ">= 1.5.0"
}

variable "environment" {
  description = "Target environment name"
  type        = string
  default     = "demo"
}

output "deployment_environment" {
  description = "Environment this demo configuration targets"
  value       = var.environment
}
