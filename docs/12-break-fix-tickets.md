# 12 · Break-fix tickets

> **Goal:** work eight realistic cloud support tickets from the symptom alone: find the cause, fix it properly, and write it up. This is what AWS Cloud Support Associate and cloud ops interviews test.

## How it works

1. Build the full lab (docs 03-08) and check that the portal, `/db` and the alarms all work.
2. Inject one fault: `.\breakfix\break.ps1 -Ticket 1` (from the repo root, with `$env:AWS_PROFILE` set).
3. **Close the script without reading it.** It contains the answer.
4. Read the ticket below and troubleshoot using doc 11's method. Time yourself.
5. Fix it the way a team would: if Terraform manages the resource, `terraform plan` to see the drift, then `terraform apply`. Otherwise fix it in the console or CLI.
   > ⚠️ Read the plan before you apply. If AWS has published a newer Amazon Linux AMI since your last apply, the plan also shows a **new launch template version**, and applying it starts a rolling instance refresh (servers replaced one by one, unhealthy-target alarms). That's unrelated to the ticket. To keep the fix clean, apply only the drifted resource with `terraform apply -target=<address from the plan>`, then run a full `terraform apply` after the ticket is closed.
6. Check the fix from the client's side, and confirm the alarms return to OK.
7. Stuck for more than 45 minutes? Read the hint. Still stuck? `.\breakfix\restore.ps1 -Ticket N` and open the answer at the bottom.

One ticket at a time. Some tickets need doc 07 (S3) or doc 08 (CloudWatch agent and alarms) built first.

## Write-up template (copy into your notes for each ticket)

```
Ticket:        BF-N
Reported:      <time>       Resolved: <time>       Time spent: <min>
Symptom:       <what the client sees, exact error>
Scope:         <everyone / some requests / one page>
Steps taken:   <commands, what each showed>
Root cause:    <the one thing that was wrong>
Who/when:      <CloudTrail event, user, time>
Fix:           <what you changed, and how>
Verification:  <how you proved it's fixed>
Prevention:    <what would stop it happening again or catch it sooner>
```

## The tickets

### BF-1 · "The client portal won't load"
> From: Front desk, 9:05 a.m. "None of our clients can open the portal since this morning. The browser just spins and then says the site can't be reached. Our office internet is fine."
>
> No alarm emails have arrived.

<details><summary>Hint</summary>The servers say they're healthy. So where between the client and the servers can traffic stop?</details>

### BF-2 · "Portal down, and IT can't get into the servers either"
> From: Front desk, 10:30 a.m. "The portal is timing out for everyone."
> From: IT, 10:35 a.m. "I tried to open a Session Manager shell to look, and the servers show as not connected."

<details><summary>Hint</summary>Two unrelated-looking symptoms, one cause. What do clients reaching the load balancer and the servers reaching AWS have in common?</details>

### BF-3 · "The portal is flaky"
> From: Accounting, 2:15 p.m. "Sometimes the portal opens instantly, sometimes it hangs until it times out. Refreshing a few times usually gets it to load."
>
> You may also get `harbor-unhealthy-targets` alarm emails, and see the server in one AZ being replaced.

<details><summary>Hint</summary>"Works sometimes" usually means "works in one place, not the other". Compare the two AZs hop by hop, including the parts of the network that don't belong to any instance.</details>

### BF-4 · "Servers keep getting replaced"
> Alarm email: `harbor-unhealthy-targets` in ALARM.
>
> From: IT lead, 8:50 a.m. "The Auto Scaling group has been terminating and relaunching servers all morning, and the new ones are marked unhealthy too. A couple of clients saw an error page for a moment. Find out what's wrong before it gets worse."
>
> Keep doc 05's watch loop running while you work, so you can see what clients see.

<details><summary>Hint</summary>Log in to a server: does the app actually answer? If it does, why does the load balancer think it doesn't? `describe-target-health` gives a reason code.</details>

### BF-5 · "Last night's database backup failed"
> From: IT lead, 7:40 a.m. "The backup job failed overnight. Please run `sudo harbor-backup` on a server, find out why it fails and get backups working again. Nobody touched the servers."

<details><summary>Hint</summary>Read the whole error. It names the API call that was refused. What decides what a server is allowed to do?</details>

### BF-6 · "Disk space alarm"
> Alarm email: `harbor-disk-high` in ALARM. No client has complained yet.
>
> From: IT lead. "Find out which server, what's using the space, and clean it up safely before it fills."

<details><summary>Hint</summary>The alarm watches the combined series. The per-server series (with an `InstanceId` dimension) tells you which machine. On the machine, `df` tells you how full, `du` and `find` tell you what.</details>

### BF-7 · "Client list page is broken"
> From: Accounting, 11:20 a.m. "The portal opens, but the client list page (`/db`) takes a few seconds and then shows a database error about a timeout."

<details><summary>Hint</summary>The database itself reports as Available. A timeout (not "refused", not "wrong password") is a network symptom.</details>

### BF-8 · "Client list page: password error"
> From: Accounting, 3:05 p.m. "The client list page (`/db`) shows an error that mentions `password authentication failed`. It worked this morning."

<details><summary>Hint</summary>The app doesn't store the password; it reads it every time. From where? Does that place keep history?</details>

## Record a demo

Like the AD lab's help desk video: pick one ticket (BF-4 and BF-7 show well), screen-record yourself reproducing it, finding the cause and fixing it, with narration. 3 minutes is plenty. Save it under `media/` and link it from the README.

---

## ⚠️ Spoilers: answers

Only open these after you've solved the ticket or given up.

<details><summary>BF-1 answer · ALB security group lost its HTTP rule</summary>

**Cause:** the inbound rule allowing TCP 80 from `0.0.0.0/0` was removed from `harbor-alb-sg`.

**How to find it:** `Test-NetConnection <alb-dns> -Port 80` fails, but `describe-target-health` shows both targets `healthy` and the servers answer `curl localhost` fine. So the break is in front of the ALB. `aws ec2 describe-security-group-rules --filters "Name=group-id,Values=<alb-sg>"` shows only the egress rule. CloudTrail: `RevokeSecurityGroupIngress`. `terraform plan` shows `aws_vpc_security_group_ingress_rule.alb_http` will be created.

**Fix:** `terraform apply`.

**Why no alarm fired:** every metric is measured *behind* the load balancer, and nothing failed there. Only an outside check (a CloudWatch Synthetics canary, an uptime monitor) catches this. That's the prevention.
</details>

<details><summary>BF-2 answer · Public route table lost its internet route</summary>

**Cause:** the `0.0.0.0/0 → internet gateway` route was deleted from `harbor-public-rt`.

**How to find it:** the ALB can't reply to clients on the internet, and the servers can't reach the SSM endpoints (so Session Manager drops), because both live in the public subnets that use that route table. `aws ec2 describe-route-tables --filters "Name=tag:Name,Values=harbor-public-rt"` shows only the `local` route. VPC Reachability Analyzer from the internet gateway to the ALB shows the missing route. CloudTrail: `DeleteRoute`.

**Fix:** `terraform apply` (recreates `aws_route.public_internet`).

**Lesson:** "public" is only a route. Lose it and the subnet is private.
</details>

<details><summary>BF-3 answer · A network ACL blocking port 80 on one subnet</summary>

**Cause:** a new network ACL `harbor-bf3` with **rule 50: DENY TCP 80 from 0.0.0.0/0** was associated with `harbor-public-b`. Rule 50 is evaluated before rule 100 (allow all).

**Why "flaky":** the ALB's DNS name returns one IP per AZ. Clients that get AZ b's ALB node time out; clients that get AZ a's node succeed. NACLs only filter traffic *entering or leaving* a subnet, so AZ a's ALB node can't reach the AZ b server on port 80, while AZ b's own node (same subnet) still can. Depending on how the ALB combines those health check results, the AZ b server may show as unhealthy (`Target.Timeout`) and get replaced.

**How to find it:** `Resolve-DnsName <alb-dns>` gives two IPs (one ALB node per AZ). `Test-NetConnection <ip> -Port 80` against each shows one answers and one doesn't. Everything in AZ b has the same security groups as AZ a, so look at what's different about the subnet: **VPC → Subnets → harbor-public-b → Network ACL**. It isn't the default ACL. CloudTrail: `CreateNetworkAcl`, `CreateNetworkAclEntry`, `ReplaceNetworkAclAssociation`.

**Fix:** associate `harbor-public-b` with the VPC's default network ACL again, then delete `harbor-bf3` (VPC → Network ACLs). Terraform doesn't manage this association, so `terraform plan` shows nothing. That's a lesson too. `restore.ps1 -Ticket 3` does the same.

**Lesson:** NACLs are subnet-wide, stateless and ordered. When two identical servers behave differently, compare what's *around* them.
</details>

<details><summary>BF-4 answer · Health check path changed</summary>

**Cause:** the target group's health check path was changed from `/health` to `/healthz`, which returns 404.

**How to find it:** on a server, `curl -s localhost/health` returns `ok`, so the app is fine. `aws elbv2 describe-target-health` shows every target `unhealthy` with reason **`Target.ResponseCodeMismatch`**: "Health checks failed with these codes: [404]". **EC2 → Target groups → harbor-app-tg → Health checks** shows `/healthz`. The ASG (health check type `ELB`) replaces servers that were never broken, over and over. CloudTrail: `ModifyTargetGroup`.

**Why clients mostly still got pages:** ALBs **fail open**. When every target is unhealthy, the ALB sends traffic to all of them anyway. The brief error pages (503) came from moments during the churn when no target was registered yet.

**Fix:** `terraform apply`.

**Lesson:** a bad health check can churn a perfectly healthy fleet. Check the health check itself before blaming the servers. 503 from an ALB = nothing registered to send to.
</details>

<details><summary>BF-5 answer · Instance role lost its S3 permissions</summary>

**Cause:** the inline policy `harbor-backup-s3` was deleted from `harbor-app-role`.

**How to find it:** `pg_dump` works, then `aws s3 cp` fails with `AccessDenied … not authorized to perform: s3:PutObject`. The role's inline policies (`aws iam list-role-policies --role-name harbor-app-role`) are `harbor-read-params` and `harbor-cloudwatch-agent`: `harbor-backup-s3` is missing. The policy simulator (doc 07) says `implicitDeny`. CloudTrail in `us-east-1` (IAM is global; use `aws cloudtrail lookup-events --region us-east-1` as in doc 01): `DeleteRolePolicy`.

**Fix:** `terraform apply`. IAM changes can take a few seconds to apply everywhere, so retry the backup after a short wait.

**Lesson:** "nobody touched the servers" is true. Permissions aren't on the server. Prevention: alert on IAM changes (EventBridge rule on IAM API calls → SNS).
</details>

<details><summary>BF-6 answer · Root disk filled by a hidden file</summary>

**Cause:** a large hidden file `/var/tmp/.cache-0001` filled the root disk of one server to about 300 MB free.

**How to find it:** **CloudWatch → Metrics → CWAgent**: the `disk_used_percent` series whose dimensions include `InstanceId` show which server. On it: `df -h /` (around 95%), then
`du -xh / --max-depth=2 2>/dev/null | sort -h | tail` (points at `/var/tmp`), then `ls -lah /var/tmp` or `find / -xdev -type f -size +500M 2>/dev/null`.

**Fix:** confirm it's not needed (unknown name, and no process holds it open: `dnf install -y lsof`, then `lsof /var/tmp/.cache-0001` returns nothing), then `rm /var/tmp/.cache-0001`. `restore.ps1 -Ticket 6` does the same on every server. The alarm returns to OK within about 5 minutes.

**Lesson:** use the per-instance dimension to find the server, then go from big directories down. Prevention: log rotation, temp file cleanup (`systemd-tmpfiles`), and alarms with headroom.
</details>

<details><summary>BF-7 answer · Database security group lost its rule</summary>

**Cause:** the inbound rule allowing TCP 5432 from `harbor-app-sg` was removed from `harbor-db-sg`.

**How to find it:** the home page works, so the ALB and the app are fine. RDS shows `Available`. From a server: the endpoint resolves (`getent hosts $PGHOST`), but `timeout 3 bash -c "</dev/tcp/$PGHOST/5432"` fails. A timeout means packets are dropped, which is a security group or NACL, not the database. `harbor-db-sg` has no inbound rules. CloudTrail: `RevokeSecurityGroupIngress`.

**Fix:** `terraform apply`.

**Lesson:** timeout = network path. "Connection refused" = reached the host, nothing listening. "Authentication failed" = reached the database (see BF-8).
</details>

<details><summary>BF-8 answer · Wrong password in Parameter Store</summary>

**Cause:** the SecureString parameter `/harbor/db/password` was overwritten with a wrong value. The database password itself never changed.

**How to find it:** the error says the connection *reached* PostgreSQL and the login was refused, so the network is fine. The app reads the password from Parameter Store on every request. **Systems Manager → Parameter Store → /harbor/db/password → History** shows a new version at the time the errors started. CloudTrail: `PutParameter`. `terraform plan` shows `aws_ssm_parameter.db_password` will be updated (the value is hidden as sensitive).

**Fix:** `terraform apply` puts the correct value back.

**Lesson:** secrets have history; check it. Prevention: limit who can `ssm:PutParameter` on `/harbor/*`, or use Secrets Manager with managed rotation.
</details>

⬅️ [11 · Troubleshooting and lessons](11-troubleshooting-and-lessons.md) | ➡️ [13 · Teardown and cost report](13-teardown-and-cost-report.md)
