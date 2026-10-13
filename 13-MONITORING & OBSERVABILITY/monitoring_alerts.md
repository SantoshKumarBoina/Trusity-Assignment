# AWS production monitoring strategy: my notes

## Approach

CloudWatch is the core tool. It covers metrics, logs, dashboards, and alarms for every layer in the stack. Alarms go to SNS, which routes to email, Slack, or a paging tool. For deeper troubleshooting I'd add X-Ray or OpenTelemetry tracing. The goal is to catch problems early, tell the on-call person fast, and make it obvious which layer is failing.

Flow: App / ALB / EC2-ECS / RDS / Lambda → CloudWatch (metrics, logs, dashboards, alarms) → SNS → on-call team

## What I'd monitor

1. Application
- Request latency, using p95 and p99 and not just averages
- Error rate (5xx and app exceptions)
- Request volume, to catch spikes or sudden drops
- Dependency failures like DB errors, external API failures, and timeouts
- Correlation IDs in structured logs so one request can be followed across services

This is where you see user impact. The logs tell you why.

2. ALB
- `HTTPCode_ELB_4XX_Count` and `HTTPCode_ELB_5XX_Count`
- `HTTPCode_Target_4XX_Count` and `HTTPCode_Target_5XX_Count`
- `HealthyHostCount` and `UnHealthyHostCount`
- `TargetResponseTime` and `RequestCount`
- ALB access logs turned on for request-level digging

ELB vs target errors tells you whether the load balancer or the app is the problem.

3. EC2 / ECS
- CPU and memory. EC2 memory and disk need the CloudWatch agent since they aren't default metrics.
- Disk usage, disk I/O, and network throughput on EC2
- On ECS: desired vs running tasks, container health check failures, task restarts, failed deployments, and stopped task reasons

4. RDS
- CPU, connections, free storage, freeable memory
- Read and write latency, plus read/write IOPS
- Enhanced Monitoring and Performance Insights for finding expensive queries

5. Lambda
- Errors, duration, invocations, throttles, concurrent executions
- For async work, also SQS queue depth, oldest message age, and dead-letter queue activity

## Production alerts

The thresholds are starting points. I'd tune them from baselines, SLOs, and real traffic.

1. High application error rate
- Condition: 5xx above 5% of requests for 5 minutes, with a minimum request volume so low traffic doesn't trigger it
- Severity: Critical
- Why: Direct user impact. Usually means a bad deploy, a failing dependency, or an outage.
- First checks: app logs, recent deploys, DB errors, downstream services

2. High ALB target response time
- Condition: p95 above the SLO (say 2 seconds) for 5 minutes
- Severity: Warning, critical if it lasts or errors rise
- Why: Slowness usually shows up before a full outage, so it's an early warning.
- First checks: CPU and memory, DB latency, connection pools

3. No healthy ALB targets
- Condition: `HealthyHostCount` is 0 for 2 consecutive periods
- Severity: Critical
- Why: The ALB is up but has nowhere to send traffic, so users get 503s.
- First checks: target health reasons, health check config, ports, security groups, recent deploys

4. High compute utilization
- Condition: CPU or memory above 85% for 10 minutes
- Severity: Warning, critical if errors are also rising
- Why: Sustained pressure leads to slow responses, restarts, and outages.
- First checks: scaling policies, task count, memory leaks, failed scale-out

5. RDS connection exhaustion
- Condition: `DatabaseConnections` above 80% of the limit for 5 minutes
- Severity: Warning, critical if close to the limit or errors increase
- Why: Once the limit is hit, new requests fail even though the DB instance is healthy.
- First checks: pool settings, long-running queries, idle connections, recent app scale-out

6. Low RDS free storage
- Condition: Free storage below 15% of allocated (or a workload-specific minimum)
- Severity: Critical as it gets close
- Why: A full disk causes write failures and can take the app down.
- First checks: data growth, logs, temp files, storage autoscaling

7. Lambda errors or throttling
- Condition: Errors or throttles above baseline, or repeated errors in a short window for critical functions
- Severity: Based on the business impact of the function
- Why: Failed or throttled jobs delay notifications and data processing even if the main app looks fine.
- First checks: Lambda logs, timeouts, concurrency limits, downstream APIs, queue metrics

8. SQS backlog growing
- Condition: Oldest message age beyond the processing target, or queue depth rising over several periods
- Severity: Warning or critical depending on deadlines
- Why: Work is coming in faster than it's being processed.
- First checks: consumer health, Lambda concurrency, failures and retries, dead-letter queue

## Making alerts useful

For every alert I'd document:
1. Severity (warning or critical)
2. The dashboard to open first
3. A runbook with diagnosis and mitigation steps
4. Escalation path if it persists
5. Recovery criteria, meaning how you confirm things are back to normal

Other things I'd do:
- Use composite alarms, for example 5xx high *and* healthy hosts low, to cut noise.
- Only page for things needing action now. Send the rest to Slack or email.
- Evaluate over a window (like 3 of 5 minutes) so one blip doesn't trigger a page.
- Test alarms and notification delivery before relying on them.
- Review and tune thresholds regularly against SLOs.

## Best practices

- Dashboards that show app, ALB, compute, DB, and Lambda together
- Structured logs with correlation IDs
- Distributed tracing (X-Ray or OpenTelemetry) to find latency across services
- Log retention, access controls, and encryption set up properly
- Synthetic checks on critical user journeys

