# AWS security setup: my notes

## The overall design

I'd go with a three-tier setup: a public entry point, private app servers, and a private database. The idea is that each piece can only be reached by the thing that's supposed to reach it.

Traffic flows like this:

1. Users hit CloudFront + WAF (optional, but good for filtering attacks and rate limiting)
2. That goes to a public Application Load Balancer (HTTPS only, ACM cert, HTTP redirects to HTTPS)
3. The ALB forwards to the app in private subnets (EC2/ECS/EKS, no direct public access), which pulls secrets from Secrets Manager
4. The app talks to RDS in private database subnets (no public IP, locked-down security group)

On top of that: IAM least privilege, KMS encryption, CloudTrail, logging/monitoring, and image scanning. Spread it across at least two AZs, and keep separate subnets and security groups for the app and database tiers.

## Going through each requirement

1. IAM least privilege
- Use IAM roles for EC2/ECS/EKS instead of putting access keys in code.
- Only give each role the actions and resources it really needs.
- Use IAM Identity Center with MFA, and give each admin and dev their own identity.
- Keep dev, test, and prod permissions separate, and review unused permissions every so often.
- IAM Access Analyzer helps spot policies that are too broad.

2. Security groups

One for each layer:

| Security group | Inbound |

| ALB | 443 from the internet |
| App | App port only, from the ALB security group |
| RDS | DB port only, from the app security group |

For example, if it's PostgreSQL, allow 5432 only from the app security group. Never allow DB traffic from `0.0.0.0/0`.

3. Private RDS
- Put it in private subnets using a DB subnet group across multiple AZs.
- Set Publicly accessible to No, with no public IP and no route to the internet.
- Only the app security group can connect.
- Turn on backups, encryption, monitoring, and TLS.
- For admin access, use a VPN or Systems Manager, not public access.

4. Secrets Manager
- Keep DB credentials, API keys, and other sensitive stuff in there.
- Encrypt with KMS, and give the app role access only to the secrets it needs.
- Turn on automatic rotation where it's supported.
- Fetch secrets at runtime with the SDK, don't hardcode them.
- Don't print secrets in app logs, CI/CD logs, or error messages.
- Use a VPC interface endpoint so secrets can be fetched privately.

5. Encryption at rest
- RDS: turn on storage encryption and encrypted backups.
- EBS: encrypt the instance volumes.
- S3: server-side encryption, and SSE-KMS if you want control over the keys.
- Secrets Manager: already KMS-encrypted.
- Lock down who can use and manage the KMS keys through key policies and IAM.

Encryption protects the stored data, but access controls decide who can actually decrypt it, so you need both.

6. Encryption in transit
- HTTPS/TLS for all public traffic.
- Make the app use TLS to RDS and validate the server certificate.
- Use HTTPS for AWS API calls, including Secrets Manager.
- Turn off insecure protocols and never send credentials in plaintext.

7. HTTPS with ACM
- Request or import a cert in ACM and attach it to the ALB's HTTPS listener.
- Redirect port 80 to 443.
- Pick a sensible TLS security policy and let ACM handle renewals.

The ALB terminates HTTPS. If the app tier is in a separate trust boundary, encrypt between the ALB and the app too.

8. WAF
- Attach it to CloudFront or the ALB.
- Turn on the managed rule groups for common attacks like SQL injection and XSS.
- Add rate-based rules to stop abusive request rates.
- Only add IP or geo restrictions if the app really needs them.
- Turn on WAF logging and look at what's being blocked.
- Test rule changes before enforcing them in prod, otherwise you'll get false positives.

WAF is an extra layer. It doesn't replace proper auth, input validation, or secure code.

9. S3
- Keep Block Public Access on unless public access is really needed and reviewed.
- Disable ACLs where you can and use bucket policies and IAM.
- Turn on default encryption (SSE-KMS if required).
- Force HTTPS-only access with a bucket policy.
- Use versioning and lifecycle/retention rules.
- Use CloudTrail data events where needed, and Macie to find sensitive data.

10. Containers and images
- Use trusted, minimal base images and keep dependencies patched.
- Scan images in CI/CD (ECR scanning, Trivy, or similar) and block releases with critical vulnerabilities.
- No secrets in Dockerfiles, image layers, or default env vars.
- Run as non-root, use read-only filesystems where possible, and drop Linux capabilities you don't need.
- Keep prod images in private ECR repos with restricted push/pull.

11. CloudTrail
- Enable a multi-Region trail (org-wide if you have an organization).
- Record management events, plus S3 data events for sensitive buckets.
- Send logs to a separate, encrypted, access-restricted S3 bucket.
- Turn on log file validation and retention controls to protect the audit trail.
- Alert on important changes: security groups, IAM policies, RDS public access, KMS keys, Secrets Manager access.
- Hook it up to CloudWatch alarms and EventBridge.

CloudTrail tells you who did what API action and when. You still need app and DB logs for the full picture.

## Interview question: how do you stop an internet user from reaching the database directly?

Here's how I'd answer it:

"I'd put the database in private subnets and set RDS to not be publicly accessible. The database security group would only allow inbound traffic on the DB port from the application security group.

Users would reach the app over HTTPS through an Application Load Balancer with WAF in front. The ALB forwards requests to the app tier, and only the app tier is allowed to talk to RDS.

I'd never expose the DB port to the internet or allow `0.0.0.0/0` on it. I'd also enforce TLS for DB connections, turn on encryption at rest, and use CloudTrail to watch for config changes.

So even though the app is public, an internet user has no direct path to the database."

## Interview question: how do you protect sensitive credentials?

"I'd keep DB credentials, API keys, and other secrets in AWS Secrets Manager, not hardcoded in the app or sitting in GitHub.

The app would use an IAM role with least-privilege permissions to fetch only the secrets it needs. Secrets Manager encrypts them with KMS, and I'd turn on automatic rotation where it's supported.

I'd also make sure credentials never end up in logs, Docker images, or CI/CD output. DB connections would use TLS, and I'd monitor secret access through CloudTrail. For private workloads, I'd use a Secrets Manager VPC endpoint so nothing has to go over the public internet."

## Quick checklist

- IAM: least privilege, roles, MFA, separate environments
- Network: public ALB, private app and DB subnets
- Database: RDS not public, DB security group only allows the app
- Credentials: Secrets Manager, KMS, rotation
- Encryption: at rest and TLS in transit
- Web protection: ACM HTTPS cert and WAF
- Storage: S3 Block Public Access, bucket policies, encryption
- Containers: trusted images, scanning, non-root
- Audit: CloudTrail, protected logs, alerts

Overall this follows least privilege, defense in depth, private networking, encryption, and continuous auditing. Once it's built, check it with Security Hub, AWS Config rules, and a Well-Architected security review.
