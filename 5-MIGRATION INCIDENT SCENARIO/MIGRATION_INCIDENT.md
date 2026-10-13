# Migration incident notes (Lambda to EC2)

## What happened

We're mid-migration. 75% of traffic is still on API Gateway/Lambda and 25% is on ALB/EC2. Since we moved to 25%, latency has gone up, we're seeing more 5xx errors, RDS connections have shot up, and a few people have reported duplicate orders.

So I'm pausing at 25%. Nothing more goes to EC2 until we know what's going on. If customers are still getting hit or the order data looks risky, we roll back with whatever routing setup we built for that.

One thing I want checked early: an ALB by itself can't split traffic between API Gateway/Lambda and an EC2 path. So what is actually doing the split (Route 53 weighted records, CloudFront, something else)? The answer decides how rollback works.

## Right now

- Call it an incident and pick someone to lead it.
- Freeze traffic increases and deploys.
- Write down when the problems started and line that up with any traffic shifts, deploys, or config changes.
- Compare the Lambda path and the EC2 path over the same time window.
- Don't blindly retry order-creation requests. Keep the request IDs, idempotency keys, and logs.
- If it's bad or getting worse, just roll back, don't wait around.
- Keep people updated and write down what we did and when.

Fix the impact first and dig into root cause after.

## Where I'd look

First, figure out the scope. Is it just EC2 or both paths? Just order creation or everything? Is it one AZ or certain targets? And did RDS connections climb before or after the latency went up? That order tells you a lot.

**ALB / target groups:** check `HTTPCode_ELB_5XX_Count`, `HTTPCode_Target_5XX_Count`, `TargetResponseTime`, healthy/unhealthy host counts, `RequestCount`, and `TargetConnectionErrorCount` if it's there. Also look at target health reasons, listener rules, ports, health check path and thresholds, and security groups.

- ELB 5xx usually means the ALB can't reach the targets, or the listener is wrong.
- Target 5xx means the app itself is erroring (exceptions, failing dependencies, DB timeouts).
- High target response time probably means slow processing, slow queries, or requests stuck waiting for a connection from the pool.
- Unhealthy targets: is the process up, is the port right, does the health endpoint respond, and does the security group let the ALB in?

**EC2 / app:** CPU, memory, disk, network, status checks, Auto Scaling capacity, app logs, stack traces, worker saturation, queues, restarts, recent deploys. Memory and disk need the CloudWatch agent, so they won't show up by default. Also double check the app isn't only listening on `localhost`, and that the EC2 security group only allows traffic from the ALB's security group, not the whole internet.

**RDS:** `DatabaseConnections`, CPU, freeable memory, free storage, read/write latency, IOPS, slow query logs, lock waits, connection errors. Compare the connection count to the engine's limit. Things to watch for are connections opened per request, too many workers, pools that are too big, and connections never getting released. Every instance and every worker can have its own pool, so total connections across all of EC2 plus Lambda can swamp the database fast.

**Lambda:** `Errors`, `Duration`, `Invocations`, `Throttles`, API Gateway latency and 4xx/5xx, concurrency, timeouts. Both paths hit the same database, so look at the combined load and don't just blame EC2.

## Possible causes (guesses until we have proof)

- **Too many DB connections.** Check connections by path, worker counts, and pool settings. The fix is to cap pools, reuse connections, and work out the total limit across everything.
- **RDS overloaded.** Check CPU, memory, latency, and lock waits. Fix slow queries, check indexes, cut unnecessary queries, and look at capacity.
- **Not enough EC2 capacity.** Look for CPU/memory saturation, queues, and unhealthy targets. Scale out, but only after confirming that's not hiding the real problem.
- **ALB misconfig.** Look at health reasons, access logs, and listener rules. Fix the port, health check, rules, or security group references.
- **App behaves differently from Lambda.** Compare env vars, timeouts, and validation. Align the config and add regression tests.
- **Retries creating duplicates.** Look for one logical request creating multiple records. Fix with proper idempotency and safer retries.
- **Bad deployment.** Check whether the errors line up with a version or config change. If so, roll back the version or the traffic.

## Pause or roll back?

Stay paused at 25% if latency or 5xx is above baseline, RDS connections are getting close to the limit, we suspect duplicates, or we just don't know the cause yet.

Roll back toward Lambda if errors keep getting worse, RDS is about to run out of connections, duplicates are confirmed, or we can't stabilize EC2 in the time we agreed on. Before sending traffic back, make sure Lambda and the DB can actually handle it.

Also, DNS rollbacks aren't instant because resolvers cache stuff. Whatever the rollback method is, it has to match how we're really splitting traffic.

To resume, the cause needs to be fixed, orders checked, monitoring working, and tests passing. Then go up in small steps with a wait between each and clear go/no-go checks. Those percentages, wait times, and thresholds should be agreed before the migration, not made up halfway through.

## Duplicate orders

Make `POST /orders` idempotent.

1. Require a client-generated idempotency key (or some other reliable request ID).
2. Store the key and the resulting order in the DB with a unique constraint.
3. Reserve the key and create the order in the same transaction.
4. Same key again? Return the original result.
5. Same key with a different payload? Reject it.
6. Keep the records long enough to cover realistic retries.
7. Use bounded retries with backoff for transient failures, and never blindly retry non-idempotent calls.
8. Log correlation IDs but not sensitive customer data.

A cache isn't enough because entries expire or get lost. The unique constraint in the DB is what makes it hold up.

## Data consistency

- Keep one authoritative write path for orders during the migration.
- If both app versions write to the same DB, check that schema, validation, transactions, and idempotency behave the same.
- Avoid uncontrolled dual writes to separate databases. If we really need that, design the sync properly (transactional outbox plus reconciliation).
- Keep the order and idempotency records in one transaction.
- Compare order counts, status totals, and a sample of records across the migration window.
- Use business identifiers and correlation IDs to track down duplicate or missing orders.
- Don't auto-delete suspected duplicates. Get business sign-off and make it auditable.
- Have backups and a recovery option before touching the schema.

## When to stop

Stop increasing traffic and think about rolling back if:

- error rate or p95/p99 latency goes past the SLO or rollback threshold
- RDS connections approach the limit or connection failures start
- DB CPU, memory, I/O latency, or lock waits start threatening the database
- duplicate or missing orders are confirmed
- the two paths return different results
- ALB targets keep going unhealthy or there isn't enough capacity
- we can't see enough to judge the impact
- Lambda couldn't safely take the traffic back

The actual numbers should come from baselines, SLOs, DB capacity, and load tests, set before the migration. We shouldn't invent them during an incident.

## Recovery checklist

1. Errors and latency are back to baseline.
2. RDS connections and performance are stable.
3. ALB targets are healthy with enough capacity.
4. `/health`, order creation, and order retrieval all work.
5. Orders from the incident window are reconciled, with duplicates and gaps investigated.
6. Idempotency is tested by sending the same key twice.
7. Root cause and fix are confirmed with metrics and logs.
8. Timeline, dashboards, logs, and relevant changes are saved.
9. A blameless review is done (root cause, contributing factors, customer impact, owners, due dates).
10. Runbooks, alarms, load tests, and rollback steps are updated before we resume.

## Prevention

- Load test the EC2 app at expected peak before sending real traffic.
- Calculate pool limits across every instance and worker, and count Lambda too.
- Set alarms for ALB 5xx, target response time, unhealthy targets, EC2 saturation, RDS connections and CPU, and Lambda errors/throttles.
- Add correlation IDs and structured logging across API Gateway, Lambda, ALB, EC2, and the DB.
- Build and test idempotency for order creation.
- Shift traffic gradually with pause and rollback criteria set up front.
- Document and test exactly how traffic gets moved between Lambda and EC2.

## What we still don't know

Current path is API Gateway → Lambda → DB, and the target is ALB → EC2 → RDS, with both sharing the DB for now. We still need to confirm how traffic is being split, which DB engine we're on, the schema, baselines, SLOs, and alarm thresholds. And nothing counts as the root cause until metrics, logs, traces, and DB evidence back it up.

## Bottom line

Higher latency, 5xx errors, more RDS connections, and duplicate order reports at 25% is enough to pause. Protect customer data, get service back to normal, and look at both paths together since they share a database. Fix duplicates with real idempotency, and only resume once the cause is fixed and the go/no-go checks pass.

