# XYZZ Orders API — Docker

## Run locally

Prerequisite: Docker Desktop with Docker Compose v2.

1. Copy `.env.example` to `.env`.
2. Change `POSTGRES_PASSWORD` to a local development password.
3. From this directory, run:

   
   docker compose up --build
  

4. Open the API docs at `http://localhost:8000/docs`.
5. Health endpoint: `http://localhost:8000/health`.

Example create order:


curl -X POST http://localhost:8000/orders \
  -H "Content-Type: application/json" \
  -d '{"customer_name":"Asha","item":"Keyboard","quantity":1}'


Fetch the order using the `id` returned by the POST request:


curl http://localhost:8000/orders/1


Stop containers with `Ctrl+C`, then run `docker compose down`. To delete the local database volume too, run `docker compose down -v` (this permanently deletes local database data).

# Docker Design Decisions

## 1. Why I Selected the Base Image

I selected the official `python:3.12-slim` Docker image for the FastAPI application.

**Reasons:**
- It provides the Python 3.12 runtime required by the application.
- The slim variant contains fewer unnecessary operating-system packages than a full Python image.
- A smaller base image reduces image size, download time, and the potential attack surface.
- Using an official Python image provides a standard, well-supported starting point.

For production, I would pin the image by digest and regularly rebuild it to include security updates.

## 2. How I Optimized the Docker Image

I applied the following optimizations:

- **Layer caching:** I copy `requirements.txt` and install dependencies before copying the application code. Docker can reuse the dependency layer when only the application changes.
- **Reduced image size:** I use a slim base image and install Python dependencies without retaining pip's cache.
- **`.dockerignore`:** I exclude unnecessary files such as `.git`, virtual environments, Python cache files, logs, and local environment files from the build context.
- **Non-root execution:** I run the application as a dedicated non-root user to reduce the impact of a potential container compromise.
- **Dependency pinning:** I specify dependency versions to make builds more reproducible.

I would also scan the built image for vulnerabilities and rebuild it regularly to incorporate security fixes.

## 3. How Application Configuration Is Managed

The application uses environment variables for configuration rather than hard-coding environment-specific values.

Examples include:

- `DATABASE_URL` — database connection URL.
- `LOG_LEVEL` — application logging level.

For local development, Docker Compose reads configuration values from a `.env` file. The `.env.example` file documents the expected variables without requiring a developer to create a database manually.

This approach allows the same application image to be used across development, testing, and production environments with different configurations.

## 4. How Secrets Are Handled

Database passwords, AWS credentials, API keys, and other sensitive information must not be hard-coded into the application or committed to GitHub.

For local development:
- Use a local `.env` file.
- Exclude `.env` from Git using `.gitignore`.
- Never use demonstration passwords in a shared or production environment.

For AWS production:
- Store database credentials in AWS Secrets Manager or Systems Manager Parameter Store.
- Encrypt secrets and restrict access using IAM permissions.
- Allow only the required workload identity to retrieve the necessary secrets.
- Rotate credentials periodically and audit access.
- Never bake secrets into the Docker image or pass them as image build arguments.

## 5. How Container Health Checks Are Implemented

I use health checks at both the database and application levels.

**PostgreSQL health check:** Docker Compose uses `pg_isready` to determine whether PostgreSQL is ready to accept connections.

**FastAPI health check:** The application exposes a `GET /health` endpoint. It executes a simple database query (`SELECT 1`) and returns a healthy response when the database is reachable. If the database is unavailable, it returns HTTP 503.

Docker Compose checks the application periodically and waits for the database health check before starting the application.

In production, I would combine health checks with CloudWatch monitoring, alarms, and load-balancer target health checks. A health check alone does not guarantee that all business operations are working correctly.

## 6. How I Would Deploy the Container to AWS

For this assessment, I would use an EC2-based architecture with an Application Load Balancer and Amazon RDS.

1. **Build and test:** Use a CI/CD pipeline to build the Docker image, run tests, and scan for vulnerabilities.
2. **Push to Amazon ECR:** Tag the image with an immutable version, such as the Git commit SHA, and push it to Amazon Elastic Container Registry.
3. **Deploy to EC2:** Run the container on EC2 instances in private subnets across multiple Availability Zones, managed by an Auto Scaling group.
4. **Configure the ALB:** Place the Application Load Balancer in public subnets and configure HTTPS using AWS Certificate Manager. Route requests only to healthy application targets.
5. **Connect to RDS:** Place the database in private subnets and allow database connections only from the application security group.
6. **Manage configuration and secrets:** Use environment-specific configuration and retrieve secrets from AWS Secrets Manager using an IAM role.
7. **Monitor the application:** Send application and infrastructure logs to CloudWatch and configure alarms for errors, latency, resource utilization, and unhealthy targets.
8. **Deploy safely:** Use rolling or blue/green deployments, health checks, and a rollback procedure to reduce deployment risk.
9. **Manage infrastructure:** Use Terraform to provision and maintain the AWS resources.

For larger-scale container management, I would also consider Amazon ECS with either EC2 capacity or AWS Fargate. For this assignment, EC2 is the selected target because it matches the chosen architecture.

### Conclusion

This Docker implementation provides a repeatable local environment for the FastAPI application and PostgreSQL database. The design emphasizes a smaller image, non-root execution, externalized configuration, secret protection, health checks, and a deployment approach that can be extended to a secure, highly available AWS environment.
