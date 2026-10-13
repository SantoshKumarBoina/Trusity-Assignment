# Troubleshooting HTTP 503 after a deployment: my notes

## How I'd approach it

A 503 after a deploy usually means the app can't serve requests. The ALB itself is often fine, it's the targets behind it that are unhealthy, overloaded, or just not there. My approach is to get service back first, figure out which layer is failing, and then fix the root cause without poking around in prod more than I have to.

## Step 1: Confirm the impact

Figure out when it started and who's affected.

- Compare the deploy time with when the first 503s showed up.
- Is every endpoint failing or just a few?
- Compare the new release with the last working one.
- Look at CloudWatch metrics and the ALB access logs.

The big question is whether the ALB is generating the 503 or the app is. In the access logs, compare `elb_status_code` with `target_status_code`. That tells you which side it came from.

## Step 2: Check the ALB

Go to EC2 → Load Balancers → your ALB → Monitoring and look at:

- `HTTPCode_ELB_5XX_Count` (errors the load balancer made itself)
- `HTTPCode_Target_5XX_Count` (errors your targets returned)
- `HealthyHostCount` and `UnHealthyHostCount`
- `TargetResponseTime`
- Listener rules and target group forwarding

Also make sure the listener is sending traffic to the right target group, and that nobody changed a rule recently that points it somewhere wrong. If ELB 503s are going up while the healthy host count is dropping, jump straight to the target group.

## Step 3: Check target health

Go to EC2 → Target Groups → your group → Targets.

- **No registered targets:** look at registration, the Auto Scaling attachment, or the ECS service config.
- **Unhealthy targets:** check the health check path, port, protocol, response code, and timeout.
- **Flapping between healthy and unhealthy:** could be slow startup, resource pressure, a flaky dependency, or a health check that's too aggressive.
- **Only some targets failing:** compare instances/containers for config or version differences.

Read the health reason and description, not just the status. A classic one: the ALB checks `/health` but the app exposes `/healthz`, so every target fails even though the app is running fine. Hit the health endpoint directly from the host or container to confirm it returns what the ALB expects.

## Step 4: Check EC2 or ECS

**On EC2:**
- Are the instances running and passing status checks?
- Is the app process actually running?
- Check system logs and the service status.
- Are the instances in the right target group?
- Did a launch template or user-data change break something?

Handy commands (swap `myapp` for your real service name):

```
sudo systemctl status myapp
sudo journalctl -u myapp --since "30 minutes ago"
ps aux | grep myapp
sudo ss -lntp
```

**On ECS:** go to ECS → Cluster → Service and look at:
- running vs desired tasks
- stopped tasks and why they stopped
- service events and deployment status
- target registration
- task definition changes (env vars, secrets, port mappings)

For example, if the new task definition points at the wrong secret or the app starts on the wrong port, new tasks fail health checks while the old ones are being replaced.

## Step 5: Check containers and logs

Compare a healthy instance or task with a failing one.


docker ps -a
docker logs --tail 200 <container_id>
docker inspect <container_id>


Look for startup exceptions, missing env vars or secrets, failed dependency installs, wrong container port, crashes or restarts, OOM kills, and failed DB connections. If the container is up but the app isn't listening on the expected port, the health check will fail.

## Step 6: Check ports and security groups

Walk the whole network path:

- **ALB security group:** allows inbound on the listener port, usually 443.
- **App security group:** allows the app port from the ALB security group.
- **Target group port:** matches the port the app is really listening on.

If those look right, check network ACLs, routing, and container networking too. Example: the app listens on `8080` but the target group forwards to `80`. The ALB is perfectly healthy and requests still fail.

## Step 7: Check CPU and memory

Use CloudWatch, EC2 monitoring, or ECS Container Insights to look at CPU, memory (where available), network throughput, container restarts, OOM kills, request latency, and worker/thread saturation.

If CPU or memory is maxed out, the app can get slow, fail health checks, or stop processing requests. Find out which process or container is the culprit, then either add capacity or fix the leak or workload problem.

## Step 8: Check the database

Since this started after a deploy, check whether the new version broke something with the DB.

- RDS availability, CPU, memory, storage, network
- Security group rules
- Endpoint, port, credentials
- TLS settings and certificate validation
- Connection errors, timeouts, auth failures
- Connection count vs. the configured limit

For PostgreSQL, a quick check is:

```
SELECT count(*) FROM pg_stat_activity;
```

If the app opens too many connections, RDS can hit its limit and requests will time out or throw 5xx errors. Check pool settings, make sure connections get released, and see whether more workers or ECS tasks pushed the total up.

## Step 9: Check Auto Scaling and deployment settings

See whether capacity or rollout settings caused the outage.

**EC2 Auto Scaling:**
- Desired, min, and max capacity
- Scaling activities and failed launches
- Do new instances pass health checks before the healthy ones get replaced?
- Is the launch template and bootstrap config correct?

**ECS rolling deployments:**
- Minimum healthy percent and maximum percent
- Are enough healthy tasks staying up during the rollout?
- Deployment circuit breaker and rollback settings
- Does the new task definition have the right image, ports, secrets, and env vars?

If a deploy swaps out healthy targets too fast, or pushes a broken version to every target, you get intermittent or full downtime.

## Step 10: Restore and verify

If the new release is the likely cause and users are hurting, recover first. Don't sit there debugging in prod.

1. Stop or pause the rollout if you can.
2. Roll back to the last known-good version or image.
3. Confirm the healthy target count is back to normal.
4. Check that 503s drop and successful requests recover.
5. Run smoke tests on the critical endpoints.
6. Watch latency, errors, CPU, memory, and DB connections.
7. Save the logs and deployment details for the root-cause work.

On ECS, redeploy the previous task definition. On EC2, restore the previous artifact or image through whatever deployment process you normally use.

I wouldn't just bump the health check timeout or force targets to healthy without knowing why they're failing.
