# 05 · Load balancer and Auto Scaling

> **Goal:** put an Application Load Balancer in front of the two servers, so clients use one address and traffic spreads across both AZs. Then kill a server on purpose and watch AWS replace it while the site stays up.

## Why a company does this

One server is one failure away from an outage. With a load balancer and an Auto Scaling group:
- clients use a single DNS name, whichever servers are behind it,
- servers that fail the **health check** stop getting traffic within seconds,
- the Auto Scaling group launches replacements by itself, in a healthy AZ,
- updates roll out one server at a time (instance refresh) with no downtime.

## What gets built ([`terraform/alb.tf`](../terraform/alb.tf))

```
Internet ──:80──► harbor-alb (harbor-alb-sg: 80 from 0.0.0.0/0)
                     │ listener :80 → forward
                     ▼
                harbor-app-tg  (health check: GET /health every 15 s, expects 200)
                     │
          ┌──────────┴──────────┐
          ▼                     ▼
     app server, AZ a      app server, AZ b     (harbor-app-sg: 80 from harbor-alb-sg ONLY)
```

| Piece | What it does |
|---|---|
| **Security group chaining** | The app SG allows port 80 from *the ALB's security group*, not from an IP range. Nothing else can reach the servers, even inside the VPC |
| **Target group** | The list of servers plus the health check. `aws_autoscaling_attachment` registers every instance the ASG launches |
| **Listener** | Port 80 on the ALB; forwards everything to the target group |
| **Health check** | `GET /health` → `200`. Two failures in a row = unhealthy, two passes = healthy |
| **ASG `health_check_type = "ELB"`** (set in doc 04) | The ASG also replaces servers the *load balancer* says are unhealthy, not only ones whose hardware fails |

> 🎓 **Why `/health` doesn't touch the database:** if it did, one slow database would mark *every* server unhealthy at once. The ASG (health check type `ELB`) would then start replacing perfectly good servers, and during the replacements there can be moments with no registered targets, when the ALB returns 503. Health checks should test "is this server able to serve", nothing deeper.

> 🎓 **ALBs fail open.** If *every* target in a target group is unhealthy, the ALB doesn't give up: it sends traffic to all of them anyway, on the theory that something is better than nothing. A 503 from an ALB means there are **no registered targets** (or all are still starting or draining), not just "all unhealthy".

## Build it

```powershell
cd $HOME\aws-cloud-homelab\lab
Copy-Item ..\terraform\alb.tf .
terraform apply
$url = terraform output -raw alb_url
$url
```

**Cost:** an ALB is billed per hour plus usage (roughly $0.03/hour in Sydney when idle), plus a public IPv4 for each AZ it runs in. Destroy at the end of the session.

The DNS name takes a minute or two to resolve after creation.

## See the load balancing

```powershell
curl.exe -s "$url/health"
1..8 | ForEach-Object { curl.exe -s $url | Select-String "Served by" }
```

The "Served by" line alternates between the two instance IDs and the two AZs.

Check the targets:

```powershell
$tg = terraform output -raw target_group_arn
aws elbv2 describe-target-health --target-group-arn $tg `
  --query "TargetHealthDescriptions[].[Target.Id,TargetHealth.State,TargetHealth.Reason]" --output table
```

## Kill a server and watch it heal

Open a second PowerShell window and keep the site under watch:

```powershell
cd $HOME\aws-cloud-homelab\lab
$url = terraform output -raw alb_url
while ($true) { $r = curl.exe -s -o NUL -w "%{http_code}" $url; "$(Get-Date -Format T)  $r"; Start-Sleep 2 }
```

In the first window, terminate one server:

```powershell
$id = aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names harbor-app-asg `
  --query "AutoScalingGroups[0].Instances[0].InstanceId" --output text
aws autoscaling terminate-instance-in-auto-scaling-group --instance-id $id --no-should-decrement-desired-capacity
```

This asks the ASG to remove the server, so it **deregisters and drains it first**, then terminates it and launches a replacement (desired capacity stays 2). Try `aws ec2 terminate-instances --instance-ids i-0123456789abcdef0` (with one of your real instance IDs) another time to see the difference: the instance just dies, and the ALB keeps sending it requests until two health checks fail (about 30 s), so the watch window may show a few `502`s. That's what a real crash looks like.

Then watch:

```powershell
aws elbv2 describe-target-health --target-group-arn $tg --output table           # draining, then gone
aws autoscaling describe-scaling-activities --auto-scaling-group-name harbor-app-asg --max-items 3 `
  --query "Activities[].[StartTime,StatusCode,Description]" --output table          # a new launch
```

Expected: the watch window keeps printing `200` the whole time (the other server carries the traffic). A few minutes later a new instance boots, runs the user data, passes two health checks and starts appearing in the "Served by" line.

**My output** (from my own account):

![Terminating a server through the ASG; the target drains first](../screenshots/05-asg-terminate-and-drain.png)

![Scaling activities: drain, terminate, replacement launched](../screenshots/05-scaling-activities.png)

![Watch window: HTTP 200 on every request during the swap](../screenshots/05-watch-window-all-200.png)

## Rolling updates (instance refresh)

Change anything in the launch template, e.g. the page text in `app/app.py`, then `terraform apply`. Terraform creates a new launch template version, and the `instance_refresh` block makes the ASG replace servers one at a time, keeping at least 50% healthy. Follow it in **EC2 → Auto Scaling groups → harbor-app-asg → Instance refresh**.

## Verify it worked

| Check | Expected |
|---|---|
| `curl.exe -s "$url/health"` | `ok` |
| Target health | 2 × `healthy` |
| "Served by" | Both instance IDs and both AZs appear |
| Terminate test | Site keeps answering `200`; ASG launches a replacement |
| Servers from the laptop on port 80 | Still fail: only the ALB can reach them |

## Common mistakes

| Mistake | Result |
|---|---|
| App SG allows 80 from `0.0.0.0/0` "to make it work" | Servers reachable directly, bypassing the ALB |
| Health check path that needs login or returns 301/302 | All targets unhealthy → the ASG replaces healthy servers in a loop (the ALB fails open, so users may see errors only intermittently) |
| Grace period too short | ASG kills new servers before user data finishes, in a loop |
| ALB in only one AZ's subnet | Not allowed: an ALB needs subnets in at least two AZs |
| Expecting the ALB to have a fixed IP | It doesn't. Use its DNS name (or a Network Load Balancer for fixed IPs) |

## Interview questions

- **"ALB vs NLB?"** ALB works at layer 7 (HTTP/HTTPS): path and host routing, health checks on a URL. NLB works at layer 4 (TCP/UDP): very high throughput and static IPs.
- **"What does a 502 vs 503 vs 504 from an ALB mean?"** 502: the target sent a bad or no response (app crashed, connection reset). 503: no registered targets to send to (if targets exist but are *all* unhealthy, the ALB fails open and still sends to them). 504: the target took too long to answer.
- **"How does the ASG know to replace an instance?"** EC2 status checks always; with health check type `ELB`, also the target group's health check.
- **"What is connection draining / deregistration delay?"** Time the ALB keeps finishing in-flight requests to a target that is being removed (30 s here, 300 s by default).
- **"What is security group referencing?"** A rule whose source is another security group. It follows instances automatically as they're replaced, unlike IP rules.
- **"How do you deploy a new version with no downtime?"** New launch template version + instance refresh (rolling), or blue/green with two target groups.
- **"How would you scale on load?"** A target tracking scaling policy, e.g. keep average CPU at 50% or requests per target at a set number.

⬅️ [04 · Linux on EC2](04-linux-on-ec2.md) | ➡️ [06 · RDS PostgreSQL](06-rds-postgresql.md)
