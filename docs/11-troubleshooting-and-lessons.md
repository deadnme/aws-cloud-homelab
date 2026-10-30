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

These are **anticipated**, not observed: the usual first-run problems with this kind of setup. The ones I actually hit are in the next section.

| Symptom | Likely cause | Fix |
|---|---|---|
| `aws login` not a valid command | AWS CLI older than 2.32.0 | `winget upgrade --id Amazon.AWSCLI -e`, reopen terminal |
| `TargetNotConnected` on `start-session` | SSM agent not registered yet | Wait 2-3 minutes after launch |
| Targets `unhealthy` right after launch | User data still installing | Wait out the 300 s grace period; check `cloud-init status` |
| ASG keeps replacing new instances | Health check fails for real (bootstrap error) | Session Manager into the newest instance, read `/var/log/cloud-init-output.log` |
| `/db` says `not configured` | Doc 06 not applied yet, or parameters deleted | `aws ssm get-parameters-by-path --path /harbor --recursive` |
| RDS create fails with a free-tier backup retention error | Free plan limit | `backup_retention_period = 0` (doc 06) |
| No alarm emails | SNS subscription not confirmed | Click the confirmation link (doc 08) |
| `CWAgent` metrics missing | Instances booted before doc 08 | Instance refresh (doc 08) |
| `AccessDenied` mentioning a service control policy, on a call that worked before | Wrong Region (the project only allows `ap-southeast-2`), or the project is near its spend limit | Check `region` in `~/.aws/config` and `variables.tf`. Check credits and spend in AWS Settings → Billing |
| An S3 or IAM action the docs say is DENIED works | An extra managed policy is attached to `harbor-app-role` (a project may add one) | `aws iam list-attached-role-policies --role-name harbor-app-role`, then `terraform apply` (doc 04) |
| `terraform destroy` hangs on the VPC or subnets | Something not managed by Terraform still uses them (e.g. the doc 09 test security group) | Delete it by hand, destroy again, then run doc 02's leftover check |

## What actually broke for me

Real events from building docs 01-10 on my own new-AWS-experience project (`ap-southeast-2`), 26-30 October 2026. Docs 05, 06, 08 and 10 otherwise ran as written.

| # | Doc | Symptom (what I saw) | Cause | How I found it | Fix | Lesson |
|---|---|---|---|---|---|---|
| 1 | 01 | Budget email recipient stuck at **Inactive**; **Send verification** said I had no permission for `notifications-contacts:*` | Since 30 September 2026 Budgets verifies new email recipients, and the project's managed SCP has a `DenyNotificationContactsOperations` statement | Matched the denied action to the SCP list on AWS's "SCPs and RCPs for projects" page | Sent the alerts through an SNS topic (`budget-alerts`) whose access policy lets only Budgets, for my account, publish; confirmed the subscription and sent a test message | A guardrail above the account can block a console button. Find another path (here SNS) instead of retrying |
| 2 | 01 | The budget's real name came out with backticks around `lab-monthly-5usd` | I typed the backticks from the doc's code formatting | The name in the Budgets list | Left it (a budget can't be renamed); the doc now says to type the name without them | Copy values, not formatting |
| 3 | 02 | `terraform plan` showed only `region`, then `No valid credential sources found` (`no EC2 IMDS role found`) | `$env:AWS_PROFILE` wasn't set in that PowerShell window, so Terraform fell through to the EC2 instance-role lookup | `~/.aws/config` and the `homelab` login were fine; only the window's setting was missing | `$env:AWS_PROFILE = 'harbor'` in each new window (doc 02's "every session" block) | An environment variable lasts one window. Check the credential chain before blaming the code |
| 4 | 03 | Cost allocation tags page: *"This feature is only available in enterprise AWS"* | Activating cost allocation tags needs advanced features, which this lab doesn't turn on | The console message | Skipped it. The project holds only the lab, so Cost Explorer grouped by **Service** shows the lab's cost; the tags still work for the tagging API | Know what the account type can't do before planning around it |
| 5 | 04 | First `apply` failed at `aws_autoscaling_group.app`; ASG activity: `Authentication Failure. Launching EC2 instance failed.`; the group was `tainted` | IAM eventual consistency: the ASG launched before the new instance profile had reached EC2 | **Auto Scaling group → Activity**: two failed launches, then two successful ones a minute later | `terraform untaint aws_autoscaling_group.app`, then `terraform plan` showed no changes | New IAM roles take a moment to propagate. Read the activity history before rebuilding |
| 6 | 04, 06 | `Test-NetConnection <public-ip>` and `aws ssm start-session --target <instance-id>`, pasted as written, failed in PowerShell | `<` is a reserved operator in PowerShell, so the command never reached AWS | The error came from PowerShell, not from AWS | Docs 04, 06, 07 and 10 now look the value up into `$ip` / `$id` first; doc 05 builds `$url` from `terraform output` | Placeholders in copy-paste commands should be lookups, not angle brackets |
| 7 | 07 | Policy simulator returned `explicitDeny` for **both** `s3:PutObject` and `s3:DeleteObject`, although the real upload from the server worked | The project SCP denies requests outside `ap-southeast-2` with an `aws:RequestedRegion` condition, and a simulated request has no Region unless you give it one | Full JSON output: no matched statement in the role's own policies, and `OrganizationsDecisionDetail.AllowedByOrganizations: false` | Added `--context-entries` with `aws:RequestedRegion=ap-southeast-2`: `allowed` / `implicitDeny`, as expected | An `explicitDeny` that matches nothing in the role's own policies points above the account. Check `OrganizationsDecisionDetail` before touching the role |
| 8 | 09 | Health report: `[HIGH] Root user has no MFA`, exit code `1` | A new-experience project has no root sign-in, so `AccountMFAEnabled` is `0` | Doc 09's note on new-experience projects | Recorded as a known exception; no other HIGH findings with the lab up | A scanner finding needs context. Write accepted exceptions down instead of hiding them |
| 9 | 09 | `can't open file '...\lab\scripts\test_cloud_health_report.py'` | I ran it from `lab/` instead of the repo root | The path in the error | `cd $HOME\aws-cloud-homelab` first | Read the path in the error message |

## Adapting the guide to the new AWS experience

The guide was first written for a classic Free Plan account in Singapore. My account turned out to be a **new AWS experience project**: one fixed Region, no root sign-in, no IAM users for people, and AWS-managed guardrails (SCPs). These are the changes I made to each doc so it matches what I actually saw.

| Doc | Change | Why |
|---|---|---|
| All, Terraform | Region `ap-southeast-1` → `ap-southeast-2` (Sydney) everywhere; prices quoted for Sydney | A project builds only in its assigned Region; the SCP denies the others |
| 00 | Current Free Tier terms (credits, 6 months); the account is closed in AWS Settings | Billing for projects lives in AWS Settings |
| 01 | Rewritten: "Sign up for AWS (new)", confirm Region and account ID in AWS Settings, 2-step verification on the login instead of root MFA and an IAM admin user | Nobody can sign in as root, and people are invited as team members, not created in IAM |
| 01 | CloudTrail `us-east-1` events read with `aws cloudtrail lookup-events --region us-east-1` | A project console has no Region selector |
| 01 | Budget alerts through an SNS topic, plus a check that alerts can reach you | The SCP blocks email-recipient verification (problem 1) |
| 02 | `aws login --profile homelab` through the project's `AccountFullAccessRole`; Terraform's `harbor` profile borrows it with `credential_process`; no access keys | The managed sign-in issues short-lived credentials (12 hours, renewed for up to 90 days) |
| 02 | A leftover check after every `destroy` | Replaces the old teardown doc |
| 03 | Skip cost allocation tags; group Cost Explorer by Service | Needs enterprise AWS (problem 4) |
| 04 | `aws_iam_role_policy_attachments_exclusive` in `compute.tf`, plus a check that the role has only `AmazonSSMManagedInstanceCore` | A project may attach extra managed policies to new roles; Terraform now owns the full list |
| 04-07, 10 | Instance IDs, IPs and the ALB URL looked up into `$id` / `$ip` / `$url` (doc 04's first session example keeps a sample ID) | Placeholders failed in PowerShell (problem 6) |
| 07 | `--context-entries aws:RequestedRegion` on the policy simulator, with an explanation | The simulator also evaluates the project SCP (problem 7) |
| 08 | AWS Chatbot → Amazon Q Developer in chat applications | Renamed service |
| 09 | Root-MFA finding documented as expected | No root sign-in (problem 8) |
| 10 | App Runner → ECS Express Mode as the managed option | App Runner closed to new customers on 30 April 2026 |

## Interview questions

- **"A client says the website is down. What do you do?"** Confirm and scope it, check what changed (CloudTrail, deployments), then follow the request hop by hop: DNS, load balancer and its target health, instance, app, database, reading each error code for where it points.
- **"Target group shows all targets unhealthy. Causes?"** Wrong health check path/port, app not running, app SG not allowing the ALB SG, NACL blocking, or the app returning a non-200 status (redirect, auth).
- **"How would you find out who deleted a security group rule?"** CloudTrail Event history, filter on `RevokeSecurityGroupIngress`: it shows the user, time and source IP.
- **"What is configuration drift and how do you detect it?"** Real infrastructure no longer matching the code because someone changed it by hand. `terraform plan` shows it; AWS Config can alert on it.
- **"How do you troubleshoot an instance you can't connect to?"** EC2 status checks, the serial console or instance screenshot, the system log, and whether SSM can reach it (role, network path).

⬅️ [10 · Docker](10-docker.md)
