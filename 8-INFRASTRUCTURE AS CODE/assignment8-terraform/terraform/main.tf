module "networking" {
  source             = "./modules/networking"
  project_name       = var.project_name
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
}

module "security" {
  source       = "./modules/security"
  project_name = var.project_name
  vpc_id       = module.networking.vpc_id
  app_port     = var.app_port
}

module "alb" {
  source               = "./modules/alb"
  project_name         = var.project_name
  vpc_id               = module.networking.vpc_id
  public_subnet_ids    = module.networking.public_subnet_ids
  alb_security_group_id = module.security.alb_security_group_id
  app_port             = var.app_port
  certificate_arn      = var.certificate_arn
}

module "database" {
  source                     = "./modules/database"
  project_name               = var.project_name
  db_subnet_ids              = module.networking.db_subnet_ids
  db_security_group_id       = module.security.db_security_group_id
  db_instance_class          = var.db_instance_class
  db_name                    = var.db_name
  db_username                = var.db_username
  multi_az                   = var.multi_az
  enable_deletion_protection = var.enable_deletion_protection
  skip_final_snapshot         = var.skip_final_snapshot
  final_snapshot_identifier   = var.final_snapshot_identifier
  backup_retention_days       = var.db_backup_retention_days
}

module "compute" {
  source                 = "./modules/compute"
  project_name           = var.project_name
  environment            = var.environment
  private_subnet_ids     = module.networking.app_subnet_ids
  instance_security_group_id = module.security.ec2_security_group_id
  target_group_arn       = module.alb.target_group_arn
  instance_type          = var.instance_type
  ami_id                 = var.ami_id
  app_port               = var.app_port
  desired_capacity       = var.desired_capacity
  min_size               = var.min_size
  max_size               = var.max_size
  db_host                = module.database.db_address
  db_name                = var.db_name
  db_secret_arn          = module.database.secret_arn
}

module "monitoring" {
  source                    = "./modules/monitoring"
  project_name              = var.project_name
  load_balancer_arn_suffix  = module.alb.load_balancer_arn_suffix
  target_group_arn_suffix   = module.alb.target_group_arn_suffix
  autoscaling_group_name    = module.compute.autoscaling_group_name
  db_instance_identifier    = module.database.db_identifier
  alarm_notification_email  = var.alarm_notification_email
}

module "storage" {
  source                             = "./modules/storage"
  project_name                       = var.project_name
  enable_versioning                  = var.enable_s3_versioning
  noncurrent_version_expiration_days = var.s3_noncurrent_version_expiration_days
}
