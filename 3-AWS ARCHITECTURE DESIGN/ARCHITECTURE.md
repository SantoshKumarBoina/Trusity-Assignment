# AWS Architecture Design – Trusity Application

## 1. Overview

This document describes the proposed AWS architecture for deploying a containerized FastAPI application using Amazon ECS with AWS Fargate and Amazon RDS for PostgreSQL.

The architecture is designed to provide high availability, scalability, security, and operational visibility while minimizing infrastructure management overhead.

The application runs across multiple Availability Zones to reduce the impact of individual infrastructure failures. Application containers run in private subnets, while an Application Load Balancer receives and distributes incoming HTTP/HTTPS requests.

## 2. Architecture Diagram

The architecture diagram is available in this directory:

The design includes the following major components:

- Amazon Route 53 for DNS resolution.
- AWS Certificate Manager (ACM) for TLS certificates.
- AWS WAF for web application protection.
- Application Load Balancer (ALB) for traffic distribution.
- Amazon VPC with public and private subnets across two Availability Zones.
- Amazon ECS with AWS Fargate for running FastAPI containers.
- Amazon RDS for PostgreSQL with Multi-AZ deployment.
- Amazon ECR for container image storage.
- Amazon S3 for static files, backups, and logs.
- Amazon SQS and AWS Lambda for asynchronous processing.
- Amazon CloudWatch for monitoring and logging.
- AWS Secrets Manager for database credentials.
- AWS IAM for access control.

## 3. AWS Network Design

### 3.1 Amazon VPC

A dedicated Amazon VPC isolates the application infrastructure from other AWS resources.

- **VPC CIDR:** `10.0.0.0/16`
- **Availability Zones:** Two Availability Zones.
- **Public subnets:** Host the Application Load Balancer and NAT Gateways.
- **Private application subnets:** Host ECS Fargate tasks.
- **Private database subnets:** Host Amazon RDS for PostgreSQL.

The application and database tiers are not directly exposed to the public internet.

### 3.2 Subnet Allocation

| Availability Zone | Subnet Type | CIDR |
|---|---|---|
| AZ A | Public | `10.0.1.0/24` |
| AZ A | Private application | `10.0.3.0/24` |
| AZ B | Public | `10.0.2.0/24` |
| AZ B | Private application | `10.0.4.0/24` |

Database subnets are private and distributed across both Availability Zones. Their CIDR ranges will be defined separately in the Terraform configuration.

### 3.3 Internet Gateway

An Internet Gateway provides internet connectivity for resources in public subnets.

The public route table contains a default route (`0.0.0.0/0`) to the Internet Gateway. The Application Load Balancer can receive traffic from the internet through its public-facing configuration.

### 3.4 NAT Gateways

NAT Gateways allow resources in private application subnets to initiate outbound internet connections without accepting unsolicited inbound internet traffic.

For production, deploying one NAT Gateway per Availability Zone improves availability and reduces cross-AZ dependency. NAT Gateway routing should be configured so each application's private subnet uses the NAT Gateway in its own Availability Zone.

NAT Gateways are not required for all architectures; VPC endpoints can provide private connectivity to supported AWS services.

## 4. Application Traffic Flow

The expected request flow is:

1. Users access the application using its DNS name.
2. Amazon Route 53 resolves the application domain to the Application Load Balancer. If a custom domain is not required, users can access the ALB DNS name directly.
3. AWS WAF evaluates incoming requests against configured web security rules when associated with the ALB.
4. The Application Load Balancer terminates HTTPS using an ACM certificate and distributes requests to healthy targets.
5. ECS Fargate tasks run the containerized FastAPI application in private application subnets.
6. The FastAPI application connects to Amazon RDS for PostgreSQL using private network connectivity.
7. The application retrieves database credentials from AWS Secrets Manager using its assigned IAM task role.
8. Application logs and metrics are sent to Amazon CloudWatch for monitoring and troubleshooting.

Security groups restrict communication between the load balancer, application tasks, and database.

## 5. Compute Layer – Amazon ECS with AWS Fargate

Amazon ECS manages the containerized application, while AWS Fargate provides serverless container compute without requiring direct management of EC2 worker nodes.

### Key components

- **ECS Cluster:** Logical grouping for application workloads.
- **Task Definition:** Defines the container image, CPU, memory, ports, environment configuration, logging, and IAM roles.
- **ECS Service:** Maintains the desired number of running application tasks.
- **Fargate Tasks:** Run the FastAPI application in private subnets.
- **Application Load Balancer Target Group:** Routes traffic to healthy application tasks.
- **Amazon ECR:** Stores versioned container images.

### Scaling and availability

The ECS service should run tasks across both Availability Zones. Service Auto Scaling can increase or decrease the number of tasks based on CPU utilization, memory utilization, request count, or other suitable metrics.

Health checks allow the load balancer to stop routing traffic to unhealthy tasks.

Container images should be tagged with release versions or immutable image digests rather than relying exclusively on the `latest` tag.

## 6. Database Layer – Amazon RDS for PostgreSQL

Amazon RDS for PostgreSQL provides a managed relational database for application data.

### Database design

- Database instances reside in private database subnets.
- A DB subnet group spans multiple Availability Zones.
- Multi-AZ deployment provides a standby database in another Availability Zone.
- Encryption at rest should be enabled using AWS KMS.
- Connections should use TLS where supported and configured.
- Automated backups and an appropriate backup retention period should be configured.
- Deletion protection should be enabled for production databases.

### Database connectivity

The database security group allows PostgreSQL traffic on port `5432` only from the ECS application security group.

The database must not be publicly accessible.

**Note:** In a standard RDS Multi-AZ DB instance deployment, the standby is for availability and failover; it is not normally used to serve read traffic. Read scaling requires an appropriate read-replica or alternative database design.

## 7. Security Architecture

Security is implemented using multiple layers.

### AWS WAF

AWS WAF protects the application against common web exploits and malicious requests. Managed rule groups and rate-based rules can be configured according to application requirements.

### AWS Certificate Manager

ACM manages TLS certificates for HTTPS connections at the Application Load Balancer. A custom domain and Route 53 hosted zone are optional.

### AWS IAM

IAM follows the principle of least privilege.

- ECS task execution role: Allows ECS to retrieve container images and publish container logs.
- ECS task role: Grants the application only the AWS permissions it requires.
- Deployment role: Allows approved deployment pipelines to update the ECS service and related resources.

Long-lived AWS access keys should not be embedded in container images or source code.

### Security groups

Security groups enforce tier-to-tier network restrictions:

- **ALB security group:** Allows inbound HTTP/HTTPS traffic from approved sources.
- **ECS task security group:** Allows application traffic only from the ALB security group.
- **RDS security group:** Allows PostgreSQL traffic only from the ECS task security group.

### AWS Secrets Manager

Secrets Manager stores database credentials and other sensitive configuration. The application retrieves secrets at runtime or through an appropriately configured ECS secret integration.

Secret rotation should be implemented where supported by the application and database configuration.

## 8. Supporting AWS Services

### Amazon S3

S3 stores application files, backups where applicable, and selected log or artifact data.

Recommended controls include encryption, restricted bucket policies, Block Public Access, versioning where appropriate, and lifecycle policies.

### Amazon SQS

SQS decouples asynchronous work from the synchronous request path. Tasks such as notifications, report generation, or other background operations can be queued and processed independently.

A dead-letter queue (DLQ) should capture messages that cannot be processed successfully after the configured retry policy.

For operations that may be retried, consumers should be idempotent to prevent duplicate side effects.

### AWS Lambda

Lambda can execute event-driven operations, including SQS message processing, scheduled maintenance, and lightweight automation. It should be introduced only where a suitable event-driven requirement exists.

### Amazon ECR

ECR stores versioned container images for the FastAPI application. Image scanning and controlled access should be enabled as part of the container release process.

### Amazon CloudWatch

CloudWatch collects application logs, ECS metrics, load balancer metrics, and RDS metrics.

Recommended alarms include:

- Elevated ALB HTTP 5xx responses.
- Unhealthy load balancer targets.
- High ECS CPU or memory utilization.
- ECS task count below the required minimum.
- High RDS CPU utilization or database connection count.
- Low database storage capacity.
- SQS queue backlog or messages in the dead-letter queue.

### AWS IAM and Secrets Manager

IAM manages access to AWS resources, while Secrets Manager stores sensitive credentials. Both services help reduce the risk of unauthorized access and credential exposure.

## 9. High Availability and Disaster Recovery

The architecture improves availability through:

- Application deployment across two Availability Zones.
- Load balancing across healthy application tasks.
- ECS service health checks and task replacement.
- RDS Multi-AZ failover.
- Automated database backups and point-in-time recovery, subject to the configured backup retention.
- Container images stored in ECR.
- Infrastructure configuration maintained as code.

Disaster recovery requirements should define recovery time objective (RTO) and recovery point objective (RPO). Cross-region replication or recovery infrastructure can be added if the business requires regional disaster recovery.

## 10. Monitoring and Troubleshooting

Operational monitoring should cover the complete request path.

| Component | Monitoring Focus |
|---|---|
| Application Load Balancer | Request count, latency, HTTP 4xx/5xx responses, healthy targets |
| ECS Fargate | Task health, CPU, memory, desired versus running tasks |
| RDS PostgreSQL | CPU, connections, storage, latency, failover events |
| SQS | Queue depth, message age, processing failures, DLQ messages |
| Lambda | Errors, duration, throttles, invocation count |
| Application | API errors, request latency, dependency failures |

CloudWatch alarms should notify the responsible team through an appropriate notification or incident-management channel.

Application logs should include request correlation identifiers where practical, while avoiding passwords, tokens, and sensitive personal data.

## 11. Infrastructure as Code and Deployment

Terraform should provision and manage the AWS infrastructure consistently.

Recommended infrastructure components include:

- VPC, subnets, route tables, Internet Gateway, and NAT Gateways.
- Security groups and IAM roles.
- Application Load Balancer and target groups.
- ECS cluster, task definition, and service.
- ECR repository.
- RDS PostgreSQL instance and subnet group.
- Secrets Manager secrets.
- CloudWatch log groups and alarms.
- S3 buckets and SQS queues where required.

A typical deployment workflow is:

1. Validate Terraform configuration using `terraform fmt` and `terraform validate`.
2. Review the infrastructure changes using `terraform plan`.
3. Apply approved infrastructure changes.
4. Build and scan the FastAPI container image.
5. Push the versioned image to Amazon ECR.
6. Update the ECS task definition with the new image.
7. Deploy through the ECS service using rolling deployments or another suitable deployment strategy.
8. Validate application health, database connectivity, logs, and alarms.

Terraform state should be stored securely in a remote backend with encryption, access controls, and state locking where supported.

## 12. Cost Optimization

The following practices help control operational costs:

- Right-size ECS task CPU and memory allocations.
- Scale ECS tasks based on measured demand.
- Select an appropriate RDS instance class and storage configuration.
- Evaluate NAT Gateway charges and use VPC endpoints where cost-effective.
- Configure S3 lifecycle rules for older logs and artifacts.
- Set CloudWatch log retention periods.
- Monitor spending through AWS Budgets and cost alerts.
- Review idle resources and unnecessary data transfer.

Multi-AZ resources, NAT Gateways, logging, and security services introduce additional costs. Production availability and security requirements should be balanced against the expected budget.

## 13. Assumptions and Design Considerations

1. The application is a containerized FastAPI service.
2. Amazon ECS with AWS Fargate is selected to reduce infrastructure management overhead.
3. PostgreSQL is hosted on Amazon RDS rather than inside the application container.
4. Application and database tiers use private subnets.
5. Route 53 and a custom domain are optional.
6. AWS WAF is recommended for internet-facing workloads, subject to security requirements.
7. SQS and Lambda support asynchronous workloads and should be configured according to actual application needs.
8. The diagram illustrates the intended design; the deployed resources and Terraform configuration must be verified independently.
9. Database subnet CIDRs, application ports, scaling thresholds, retention periods, and backup policies must be finalized before production deployment.

## 14. Conclusion

This architecture provides a scalable and secure foundation for deploying the Trusity FastAPI application on AWS. ECS Fargate simplifies container operations, an Application Load Balancer distributes requests across healthy tasks, and Amazon RDS for PostgreSQL provides managed relational database capabilities.

Multi-AZ deployment, layered security controls, infrastructure as code, monitoring, and automated deployment practices support maintainability and production readiness.