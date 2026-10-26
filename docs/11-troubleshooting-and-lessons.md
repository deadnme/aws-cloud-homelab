# 11 · Troubleshooting method and lessons

> **Goal:** have one repeatable way to troubleshoot "the site is down / slow / erroring" on AWS, a toolkit of commands for each layer, and a record of what actually broke while I built this lab.

## The method: follow the request

A request to the portal travels: **client → DNS → load balancer (SG, NACL, listener) → target group health → instance (SG, NACL, route) → nginx → app → Parameter Store → database (SG, port, credentials).** Find the first hop where it stops. Don't guess and restart things.

1. **Reproduce and scope it.** Everyone or one user? All pages or one (`/` vs `/db`)? Since when? What changed (CloudTrail Event history)?
2. **Read the error you get.** A timeout, a 502, a 503 and a 500 point at different hops (table below).
3. **Check from the outside in**, one hop at a time, with the tool for that hop.
4. **Fix one thing, re-test, write it down.**
5. **If Terraform manages it, fix it in Terraform.** `terraform plan` shows drift: someone changed a resource by hand.

### What the symptom tells you

| Symptom from the client | Most likely hop | First checks |
|---|---|---|
| Timeout, no answer at all | Network in front of the ALB: ALB SG, NACL, route table / IGW | ALB SG inbound 80, subnet NACLs, `0.0.0.0/0` route |
| Works sometimes, times out other times | One AZ's path is broken | Per-subnet NACLs/routes; target health per AZ |
| **502** Bad Gateway | Target answered badly: app down behind nginx, connection reset | `systemctl status harbor-app`, `journalctl -u harbor-app` |
| **503** Service Unavailable | No registered targets (ASG empty or replacing everything) | `describe-target-health`, ASG activity, health check path/port, app SG from ALB SG |
| Servers replaced again and again | Health check failing on servers that are actually fine | Health check path/port/matcher vs `curl localhost/health` on a server |
| **504** Gateway Timeout | Target too slow or unreachable from the ALB | App SG, app hanging (database calls) |
| **500** from `/db` only | App fine, dependency broken | The error text, Parameter Store values, DB SG, RDS status |
| `AccessDenied` in a script | IAM | The action and resource named in the error; role policies; simulator |

### Toolkit by layer

| Layer | Tool | Example |
|---|---|---|
| DNS | `Resolve-DnsName` (Windows), `dig` / `getent hosts` (Linux) | `Resolve-DnsName harbor-db.….rds.amazonaws.com` |
| TCP port | `Test-NetConnection` (Windows), `/dev/tcp` (Linux) | `timeout 3 bash -c "</dev/tcp/$HOST/5432" && echo open` |
| HTTP | `curl.exe -v` / `curl -sv` | `curl -s -o /dev/null -w "%{http_code}\n" localhost/` |
| Path | `traceroute` / `tracepath`, VPC Reachability Analyzer (console) | Reachability Analyzer explains *which* SG/NACL/route blocks a path |
| Load balancer | `aws elbv2 describe-target-health` | `TargetHealth.Reason`: `Target.FailedHealthChecks`, `Target.Timeout`, `Target.ResponseCodeMismatch` |
| Instance | Session Manager + `systemctl`, `journalctl`, `ss -tlnp`, `df -h`, `free -m` | `journalctl -u nginx --since "10 min ago"` |
| First boot | `cloud-init status`, `/var/log/cloud-init-output.log` | Did user data finish? |
| Config drift | `terraform plan` | Shows anything changed outside Terraform |
| Who changed it | CloudTrail Event history | Filter by event name, e.g. `RevokeSecurityGroupIngress` |
| Logs | CloudWatch Logs Insights | 5xx in `/harbor/nginx/access` |
| Permissions | `aws iam simulate-principal-policy`, the AccessDenied message | Doc 07 |

## Problems you're likely to hit while building

These are **anticipated**, not observed. They're the usual first-run problems with this kind of setup. Move them to the next section if they happen to you, with your real error text.

| Symptom | Likely cause | Fix |
|---|---|---|
| `aws login` not a valid command | AWS CLI older than 2.32.0 | `winget upgrade --id Amazon.AWSCLI -e`, reopen terminal |
| Terraform `No valid credential sources found` | `$env:AWS_PROFILE` not set in this terminal, or the login session expired | Doc 02's "every session" block |
| `TargetNotConnected` on `start-session` | SSM agent not registered yet | Wait 2-3 minutes after launch |
| Targets `unhealthy` right after launch | User data still installing | Wait out the 300 s grace period; check `cloud-init status` |
| ASG keeps replacing new instances | Health check fails for real (bootstrap error) | Session Manager into the newest instance, read `/var/log/cloud-init-output.log` |
| `/db` says `not configured` | Doc 06 not applied yet, or parameters deleted | `aws ssm get-parameters-by-path --path /harbor --recursive` |
| RDS create fails with a free-tier backup retention error | Free plan limit | `backup_retention_period = 0` (doc 06) |
| No alarm emails | SNS subscription not confirmed | Click the confirmation link (doc 08) |
| Budget email recipient "Inactive"; **Send verification** says no permission for `notifications-contacts:*` | Budgets verifies new recipients since 30 September 2026, and the project SCP denies `notifications-contacts` | Send the alerts through an SNS topic (doc 01, step 5) |
| `CWAgent` metrics missing | Instances booted before doc 08 | Instance refresh (doc 08) |
| `AccessDenied` mentioning a service control policy, on a call that worked before | Wrong Region (the project only allows `ap-southeast-2`), or the project is near its spend limit | Check `region` in `~/.aws/config` and `variables.tf`. Check credits and spend in AWS Settings → Billing |
| An S3 or IAM action the docs say is DENIED works | An extra managed policy is attached to `harbor-app-role` (a project may add one) | `aws iam list-attached-role-policies --role-name harbor-app-role`, then `terraform apply` (doc 04) |
| `terraform destroy` hangs on the VPC or subnets | Something not managed by Terraform still uses them (e.g. a test security group, the BF-3 NACL) | Delete it by hand (doc 13 lists where to look), destroy again |

## What actually broke for me

_Fill this in as you go: symptom, the exact error text, how you found the cause, the fix, and the lesson. Only real events, like doc 11 of the AD lab._

| # | Symptom (exact error) | Cause | How I found it | Fix | Lesson |
|---|---|---|---|---|---|
| 1 | | | | | |

## Interview questions

- **"A client says the website is down. What do you do?"** Confirm and scope it, check what changed (CloudTrail, deployments), then follow the request hop by hop: DNS, load balancer and its target health, instance, app, database, reading each error code for where it points.
- **"Target group shows all targets unhealthy. Causes?"** Wrong health check path/port, app not running, app SG not allowing the ALB SG, NACL blocking, or the app returning a non-200 status (redirect, auth).
- **"How would you find out who deleted a security group rule?"** CloudTrail Event history, filter on `RevokeSecurityGroupIngress`: it shows the user, time and source IP.
- **"What is configuration drift and how do you detect it?"** Real infrastructure no longer matching the code because someone changed it by hand. `terraform plan` shows it; AWS Config can alert on it.
- **"How do you troubleshoot an instance you can't connect to?"** EC2 status checks, the serial console or instance screenshot, the system log, and whether SSM can reach it (role, network path).

⬅️ [10 · Docker](10-docker.md) | ➡️ [12 · Break-fix tickets](12-break-fix-tickets.md)
