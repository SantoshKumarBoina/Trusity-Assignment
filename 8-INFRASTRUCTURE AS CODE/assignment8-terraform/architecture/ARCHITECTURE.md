# Assignment 3 — AWS Architecture Design (EC2)

## Request flow
Users → Route 53 (DNS, optional custom domain) → AWS WAF → public Application Load Balancer → EC2 Auto Scaling Group in private application subnets → private Amazon RDS PostgreSQL Multi-AZ.

Supporting services: VPC across two Availability Zones, public and private subnets, Internet Gateway, NAT Gateways, IAM instance profile, Secrets Manager, S3, and CloudWatch.

## 1. Why EC2?
EC2 provides control over the operating system and runtime and supports Docker-based deployment. An Auto Scaling Group maintains instance capacity and replaces unhealthy instances. It is suitable when host-level control is required; ECS Fargate could reduce host administration but is not necessary for this design.

## 2. High availability
Deploy the ALB across public subnets in two Availability Zones and EC2 instances in private subnets across both AZs. The Auto Scaling Group replaces unhealthy instances. Use RDS Multi-AZ for managed database failover. This improves resilience but increases costs.

## 3. Traffic distribution
The ALB listener forwards HTTP requests to an instance-type target group. Health checks determine whether an EC2 instance should receive traffic. In production, use Route 53 for a domain and ACM for HTTPS; this starter uses HTTP for initial testing.

## 4. Scaling
Configure minimum, desired, and maximum capacity for the Auto Scaling Group. Target tracking on average EC2 CPU utilization scales out when demand increases and scales in when demand decreases. Tune thresholds after load testing.

## 5. Database security
RDS is placed in private database subnets with public accessibility disabled. Its security group accepts port 5432 only from the application EC2 security group. Storage encryption and automated backups are enabled. Credentials are stored in Secrets Manager and should be retrieved by the application at runtime.

## 6. Failure handling
ALB health checks stop routing traffic to unhealthy instances. EC2 Auto Scaling replaces unhealthy instances. CloudWatch alarms identify ALB 5xx responses, target 5xx responses, and high ASG CPU. RDS Multi-AZ supports automatic failover. Deployments should be rolled out gradually and validated before completion.

## 7. Supporting traffic growth
Scale EC2 horizontally through the Auto Scaling Group and distribute traffic through the ALB. Tune database indexes and connection pooling; scale RDS when metrics show database saturation. Add caching or SQS/Lambda-based asynchronous work when justified by measured bottlenecks.

## 8. Serverless components to retain
Retain S3 for object storage, Lambda for event-driven tasks, SQS for asynchronous decoupling, Secrets Manager for credentials, and CloudWatch for logs and alarms. Route 53 provides DNS when a custom domain is available, and WAF helps filter malicious web traffic. These supporting services do not require replacing the main ALB → EC2 → RDS request path.


## Infrastructure as Code and operational controls

Terraform is split into reusable modules for networking, security groups, ALB, compute, database, storage, and monitoring. Shared naming and default tags identify the project, environment, and Terraform ownership. Variables expose the region, VPC, AZs, capacity, database settings, snapshot/backup policy, optional HTTPS certificate, alarm email, and S3 lifecycle controls.

The RDS master password is managed by RDS and stored in Secrets Manager; Terraform consumes the secret ARN for the EC2 instance role policy rather than a password value. State should be stored in an encrypted, versioned, access-controlled S3 bucket with locking through DynamoDB for compatibility with Terraform 1.5.x. Bootstrap the backend separately and migrate existing local state only after a secure backup.

Development, staging, and production should use separate state keys and preferably separate AWS accounts for production. Production changes should go through pull requests, `terraform fmt`, `terraform validate`, security checks, reviewed plans, approval gates, and a controlled deployment role. Inspect every planned replacement or deletion before applying. Production should enable RDS deletion protection, retain final snapshots, use an ACM certificate for HTTPS, and have an approved rollback/recovery plan.

The current EC2 user data still starts a placeholder Nginx container for infrastructure testing. It must be replaced with the actual FastAPI image and tested against RDS before the architecture can be considered end-to-end complete. HTTPS is optional until an ACM certificate ARN and domain are configured. WAF, CloudTrail, VPC Flow Logs, and a production CI/CD workflow remain documented production enhancements rather than enabled resources in this Terraform starter.
