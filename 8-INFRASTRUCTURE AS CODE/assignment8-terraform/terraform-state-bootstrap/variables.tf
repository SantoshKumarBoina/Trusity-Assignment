variable "aws_region" {
  type = string
  default = "ap-south-1"
}
variable "state_bucket_name" {
  type        = string
  description = "Globally unique bucket name for Terraform state."
  default = "xyzz-terraform-state-2026-unique123"
}
variable "lock_table_name" {
  type = string
  default = "xyzz-terraform-locks"
}
