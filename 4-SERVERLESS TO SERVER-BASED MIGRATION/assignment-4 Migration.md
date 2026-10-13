# Serverless to Server-Based Migration Plan

**Project:** XYZZ Orders\
**Target:** Users → Application Load Balancer (ALB) → EC2 Auto Scaling
Group running Docker/FastAPI → Amazon RDS for PostgreSQL\
**Region:** `ap-south-1` (Mumbai)\
**Status:** Proposed plan

## 1. Objective

This document describes a controlled migration from the existing
serverless architecture to a server-based application tier while
minimizing downtime, protecting order data, and maintaining a rollback
path.

-   **Current:** Users → API Gateway → AWS Lambda → Database
-   **Target:** Users → ALB → EC2/Docker/FastAPI → RDS for PostgreSQL

EC2 is selected for the main application tier to match the current
infrastructure implementation. Services such as SQS, Lambda, S3, Secrets
Manager, and CloudWatch may remain where appropriate.

A zero-downtime migration cannot be guaranteed in advance. The outcome
depends on compatibility, database strategy, routing, testing, and
execution of cutover and rollback procedures.

## 2. Current architecture assessment

### Application assessment

-   Inventory API Gateway routes, Lambda functions, runtime versions,
    dependencies, layers, timeouts, memory, concurrency, environment
    variables, and AWS integrations.
-   Record request/response formats, authentication, validation, error
    codes, retry behavior, and background jobs.
-   Identify Lambda-specific assumptions such as event formats,
    execution time limits, temporary storage, and initialization
    behavior.
-   Measure baseline request volume, p50/p95/p99 latency, 4xx/5xx rates,
    timeouts, and concurrency.
-   Document existing logs, metrics, alarms, and traces.

### Database assessment

-   Identify engine/version, schema, indexes, constraints, extensions,
    data volume, and connection limits.
-   Review peak connections, slow queries, transaction duration, and
    database load.
-   Decide whether the existing database can remain the shared source of
    truth or whether data must move to RDS.
-   Choose a migration method based on engine compatibility and downtime
    requirements.
-   Take a backup and test restoration before production cutover.

### Baseline and acceptance criteria

Agree on measurable thresholds before migration: maximum acceptable
latency, error rate, database connection usage, and reconciliation
differences. Compare the new path against this baseline at every stage.

## 3. Target architecture

1.  Users send HTTPS requests to the application endpoint.
2.  The ALB terminates HTTPS using an ACM certificate and forwards
    requests to healthy targets.
3.  EC2 instances in private application subnets run Dockerized FastAPI.
4.  The application connects to private RDS PostgreSQL using TLS and
    credentials retrieved from Secrets Manager.
5.  CloudWatch collects ALB, EC2, application, and RDS metrics and logs.
6.  The Auto Scaling Group replaces unhealthy instances and scales
    according to configured policies.
7.  SQS and Lambda may remain for suitable asynchronous tasks.

Security controls include least-privilege IAM, database security-group
access only from the application security group, encryption at rest and
in transit, and no public RDS access.

## 4. Application changes

-   Keep API contracts stable to avoid unnecessary client changes.
-   Configure FastAPI with a production ASGI server and the correct
    application port.
-   Keep configuration in environment variables or managed
    configuration; never bake secrets into the image.
-   Retrieve database credentials from Secrets Manager using a
    least-privilege EC2 instance profile.
-   Implement request validation, structured logs, exception handling,
    and appropriate HTTP responses.
-   Ensure `/health` works for ALB health checks; readiness checks
    should not expose sensitive details.
-   Configure reliable container startup/shutdown and signal handling.
-   Use database connection pooling and bounded connection limits to
    avoid exhausting RDS.
-   Add request/correlation IDs to logs.
-   Build and scan immutable image versions in CI, and deploy the same
    tested image to each environment.
-   Run unit, integration, API contract, and failure-path tests before
    shifting traffic.

## 5. Database migration and consistency

### If both application versions can use the same database

This may simplify migration by retaining one source of truth. First
verify schema and transaction compatibility. Do not let both paths
independently create conflicting records.

### If data must move to RDS

1.  Create and secure RDS, including subnet placement, security groups,
    encryption, backups, and monitoring.
2.  Take and verify a source backup.
3.  Choose a method appropriate for the source/target engines and
    downtime objective. AWS DMS may support initial load plus change
    data capture for supported combinations.
4.  Test schema conversion and data migration outside production.
5.  Validate row counts, key records, constraints, indexes, and
    application read/write behavior.
6.  During final cutover, control writes as required, allow changes to
    catch up, and verify replication lag before switching the writer.
7.  Keep the old database recoverable until acceptance and the rollback
    window ends.

Do not assume reverse replication or instant failback is available;
design and test it for the selected engines and tools.

### Consistency controls

-   Use database transactions for related order writes.
-   Use an idempotency key for order creation and enforce uniqueness in
    the database.
-   Define the authoritative writer at every stage.
-   Avoid uncontrolled dual writes to two databases. If dual writes are
    required, design reconciliation and failure recovery explicitly.
-   Reconcile order counts and important fields before and after
    cutover.
-   Preserve relevant migration logs and audit records.

## 6. Pre-production testing

Deploy the target in a non-production environment and verify: - API
compatibility and all required endpoints. - Order creation/retrieval,
validation, error handling, and idempotency under retries. - Database
connections, transactions, and connection pool limits. - ALB health
checks, target registration, and instance replacement. - Auto Scaling
behavior, secret retrieval, and IAM permissions. - Load and soak tests
at expected and peak traffic. - Failure scenarios including application
crash, database unavailability, and dependency timeouts. - Backup
restoration and the documented rollback procedure.

Do not shift production traffic until agreed acceptance criteria pass.

## 7. Traffic migration strategy

Use a staged cutover. The exact mechanism depends on the existing
routing design. API Gateway and ALB do not automatically provide a
shared weighted traffic split; a suitable routing layer or integration
must be implemented and tested if traffic is to be split between the two
paths.

### Suggested stages

1.  **Internal validation:** Test the new path without production users.
2.  **Small canary:** Route a small portion, such as 5%, if the routing
    layer supports it.
3.  **Incremental increase:** Consider 10%, 25%, 50%, and 100%,
    advancing only when the current stage meets acceptance criteria.
4.  **Observe:** At every stage, check latency, error rate, database
    connections, order success, and duplicate-order indicators.
5.  **Full cutover:** Route intended traffic to the target after
    validation and approval.
6.  **Stabilization:** Keep the old path available during the agreed
    rollback window. Retire it only after acceptance.

Percentages are illustrative. Use smaller increments or longer
observation periods when risk warrants it.

### Routing considerations

-   The ALB distributes requests across healthy registered targets; it
    does not by itself split traffic between API Gateway/Lambda and the
    new architecture.
-   Route 53 weighted records can be affected by DNS caching and may not
    yield an exact request-level split.
-   Select routing that supports the required rollback speed and can be
    observed reliably.
-   Keep API contracts and authentication behavior consistent across
    both paths.

## 8. Duplicate request prevention

A client may time out even when the server has committed an order, then
retry. Do not rely on clients sending requests only once.

-   Require an idempotency key or suitable client-generated request
    identifier for order creation.
-   Store the key and resulting order in the same database transaction.
-   Enforce a unique constraint on the key in the appropriate scope.
-   Return the original result for a repeated key rather than creating
    another order.
-   Define behavior if a repeated key arrives with a different payload.
-   Use bounded retries with backoff for transient failures; do not
    retry validation errors.
-   Make SQS consumers idempotent because messages can be delivered more
    than once.
-   Monitor duplicate-key conflicts and reconcile orders during
    migration.

## 9. Monitoring during migration

Create dashboards and alerts for both paths and compare them over
equivalent time windows.

### Application and ALB

-   Request volume and success rate.
-   p50/p95/p99 latency.
-   ALB 4xx/5xx responses, target errors, unhealthy targets, and target
    response time.
-   Application exceptions, timeouts, and health-check failures.

### EC2 and Auto Scaling

-   CPU and memory (memory may require the CloudWatch agent).
-   Instance status checks and Auto Scaling activities.
-   Container restarts, process health, deployment version, and capacity
    saturation.

### RDS and data

-   CPU, free storage, connections, read/write latency, and relevant
    database logs.
-   Connection-pool saturation and connection errors.
-   Replication lag, if applicable.
-   Order creation success, duplicate indicators, and reconciliation
    differences.

### Decision gates

Agree on numerical thresholds before the migration. Pause or roll back
if the agreed error-rate or latency thresholds are breached, RDS
connections approach unsafe limits, target health becomes unstable, or
unexplained data loss/duplicates occur. Do not choose production
thresholds after migration starts.

## 10. Rollback strategy

Rehearse rollback outside production. The correct action depends on
whether the database writer or schema has changed.

### Trigger pause/rollback when

-   Error rate or latency breaches the agreed threshold for the agreed
    observation window.
-   ALB targets cannot remain healthy.
-   Database connections or resource saturation threaten availability.
-   Order creation/retrieval fails beyond the agreed tolerance.
-   Reconciliation reveals missing, inconsistent, or duplicate orders.
-   A security or data-integrity issue is detected.

### Rollback procedure

1.  Stop increasing traffic and pause the migration.
2.  If impact or data integrity is at risk, route traffic to the
    known-good path using the tested routing control.
3.  Confirm the old path is healthy and points to the authoritative,
    up-to-date data source.
4.  If writes occurred in a new database, do not blindly switch to a
    stale database. Preserve and reconcile new writes before changing
    the writer.
5.  Preserve logs, metrics, deployment versions, and database evidence.
6.  Investigate the root cause, fix it, and rerun failed tests before
    another canary.
7.  Communicate status and document timeline, impact, root cause, and
    corrective actions.

Application rollback is generally simpler when both versions share a
compatible database. Database rollback after writes or schema changes
requires a separately tested data recovery plan.

## 11. DNS strategy

-   Use a stable application hostname where possible.
-   Provision and validate HTTPS certificates before cutover.
-   If changing DNS, lower TTL in advance where appropriate and account
    for cached records.
-   Validate the new endpoint, certificate, health checks, and
    application behavior before changing records.
-   Keep the previous route available during the rollback window.
-   Do not rely on DNS alone for instant rollback or precise weighted
    request distribution.

## 12. Production change controls

-   Use a reviewed change request with implementation steps, risk
    assessment, validation, rollback triggers, and approvers.
-   Deploy an immutable, tested application image.
-   Review the Terraform plan before infrastructure changes.
-   Apply changes through the approved pipeline or controlled operator
    identity.
-   Prefer backward-compatible database schema changes.
-   Avoid unrelated infrastructure changes during the migration window.
-   Establish an incident communication channel and record approvals,
    versions, traffic changes, and validation results.

## 13. Post-migration validation

-   Test `GET /health`, `POST /orders`, and `GET /orders/{id}`.
-   Verify authentication, authorization, validation, and expected error
    responses.
-   Confirm order creation/retrieval with representative test cases.
-   Reconcile order counts and important fields against the
    authoritative source.
-   Test idempotency under retry scenarios.
-   Check ALB health, EC2 capacity, RDS connections, and CloudWatch
    alarms.
-   Verify Secrets Manager access, TLS, security-group boundaries,
    backups, and recovery procedures.
-   Compare latency, error rates, resource usage, and cost against
    baseline.
-   Obtain stakeholder acceptance and keep rollback available for the
    agreed period.
-   Retire old resources only after confirming they are no longer needed
    and the rollback window has closed.


## 14. Completion criteria

The migration is complete when: - All intended traffic uses the target
architecture. - API functionality and data reconciliation pass. - Error
rates and latency meet agreed objectives. - Database connections and
application capacity are stable. - Monitoring, alerts, backups, and
operational documentation are in place. - Stakeholders approve the
result. - The rollback window has ended and old resources can be safely
retired.

## 15. Assumptions and limitations

-   The source database and exact migration method are not specified and
    must be confirmed.
-   Weighted traffic percentages depend on the routing implementation.
-   Multi-AZ improves availability but does not eliminate all downtime.
-   Auto Scaling requires working health checks and scaling policies.
-   This document describes the intended process; each control must be
    implemented and verified before it is considered active.
