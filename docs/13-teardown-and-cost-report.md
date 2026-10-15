# 13 · Teardown and cost report

> **Goal:** delete everything, **prove** nothing billable is left, and record what the whole lab cost. This is the habit that keeps a cloud bill (and a Free Plan's credits) under control.

## Why a company does this

"Turn off what you don't use" is the biggest cost saving in any cloud account. Forgotten test environments, unattached disks, idle load balancers and old snapshots are the classic surprise-bill items. Being able to show you clean up after yourself, and to prove it with data, is a real point in a junior cloud interview.

## Every session: destroy

```powershell
cd $HOME\aws-cloud-homelab\lab
terraform destroy      # review the list, type yes
```

RDS takes several minutes to delete. If `destroy` fails, read the error. The usual cause is something created **outside** Terraform that still uses the VPC (doc 11).

## Prove nothing is left

Run all of these. Each should return nothing, or only items in a deleted/terminated state.

```powershell
$env:AWS_PROFILE = 'harbor'

# Anything still carrying the lab's tag (can lag a few minutes behind deletions)
aws resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=aws-cloud-homelab `
  --query "ResourceTagMappingList[].ResourceARN" --output text

# The things that cost money while idle
aws ec2 describe-instances --filters "Name=instance-state-name,Values=pending,running,stopping,stopped" `
  --query "Reservations[].Instances[].InstanceId" --output text
aws ec2 describe-volumes --query "Volumes[].[VolumeId,State,Size]" --output text
aws ec2 describe-addresses --query "Addresses[].PublicIp" --output text
aws ec2 describe-nat-gateways --filter "Name=state,Values=available,pending" --query "NatGateways[].NatGatewayId" --output text
aws elbv2 describe-load-balancers --query "LoadBalancers[].LoadBalancerName" --output text
aws rds describe-db-instances --query "DBInstances[].[DBInstanceIdentifier,DBInstanceStatus]" --output text
aws rds describe-db-snapshots --snapshot-type manual --query "DBSnapshots[].DBSnapshotIdentifier" --output text
aws ec2 describe-snapshots --owner-ids self --query "Snapshots[].SnapshotId" --output text

# Leftovers from the lab's tools
aws logs describe-log-groups --log-group-name-prefix /harbor --query "logGroups[].logGroupName" --output text
aws ssm get-parameters-by-path --path /harbor --recursive --query "Parameters[].Name" --output text
aws ec2 describe-network-acls --filters "Name=tag:Name,Values=harbor-bf3" --query "NetworkAcls[].NetworkAclId" --output text
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=harbor-vpc" --query "Vpcs[].VpcId" --output text
```

The agent's policy deliberately can't create log groups, so they shouldn't come back. If a `/harbor/...` log group is still there after `destroy` anyway (e.g. you attached AWS's managed `CloudWatchAgentServerPolicy` while experimenting), delete it by hand, or the next `terraform apply` fails with `ResourceAlreadyExistsException`:

```powershell
aws logs delete-log-group --log-group-name /harbor/nginx/access
aws logs delete-log-group --log-group-name /harbor/nginx/error
```

Then run the health report (doc 09). With everything gone it lists **no** "Billable resources running" lines.

> 🎓 RDS creates automated snapshots during backups. They're deleted with the instance when `skip_final_snapshot = true` and no manual snapshots exist. The `describe-db-snapshots --snapshot-type manual` line catches the ones that would survive.

_My output: (paste the empty results here, or what you had to clean up by hand)_

## Cost report

Cost Explorer data lags up to 24 hours, so do this the day after a session.

1. **Billing and Cost Management → Cost Explorer**.
2. Date range: from the account's creation to today. Granularity: **Daily**. Group by: **Service**.
3. Filter **Tag: Project = aws-cloud-homelab** (works after you activated the tag in doc 03; earlier spend shows untagged).
4. Make sure **charge type** includes usage and excludes credits, so you see what the lab really used.
5. Screenshot it to `screenshots/13-cost-explorer.png`.
6. **Billing → Credits** (or the Free Plan panel on Console Home): note the credits used and remaining.

### Rough estimate for comparison

These are approximate Singapore on-demand prices. Check the [AWS Pricing Calculator](https://calculator.aws/) for current ones.

| Running | Approx. per hour |
|---|---|
| 2 × `t4g.micro` | $0.02 |
| Public IPv4: 2 instances + 2 ALB nodes | $0.02 |
| Application Load Balancer (idle) | $0.03 |
| RDS `db.t4g.micro` + 20 GB | $0.03 |
| EBS, S3, CloudWatch, Parameter Store | ≈ $0 |
| **Everything up** | **≈ $0.10/hour** |

At that rate, 40 hours of lab time is about $4 of credits.

### My numbers

_Fill in from Cost Explorer: total spend, spend by service, hours of lab time, credits remaining._

| Service | Cost |
|---|---|
| | |
| **Total** | |

## When you're completely done with the lab

- Leave the account on the Free Plan. It closes or asks you to upgrade when the plan ends (6 months or credits used). **Don't upgrade** unless you mean to pay.
- If you want to close the account: as root, **Account → Close account**. Do it only after the checks above are clean.
- Keep the repo: the docs, Terraform and screenshots are the portfolio piece; the AWS resources never were.

## Interview questions

- **"How do you make sure test resources don't keep costing money?"** Infrastructure as code with `destroy`, tags on everything, budgets with alerts, regular checks for idle resources (scripts or Trusted Advisor), and schedules that stop non-production resources out of hours.
- **"Which AWS resources cost money while idle?"** Running instances, EBS volumes and snapshots, public IPv4 addresses and Elastic IPs, load balancers, NAT Gateways, RDS instances (even stopped ones for storage), interface VPC endpoints.
- **"How do you see cost per project?"** Cost allocation tags (activated in Billing) plus Cost Explorer filtered or grouped by the tag. AWS Budgets can also be scoped to a tag.
- **"What did this lab cost you?"** Answer with your real Cost Explorer number and what you did to keep it low: destroy after each session, no NAT Gateway, single-AZ RDS, Arm instances.

⬅️ [12 · Break-fix tickets](12-break-fix-tickets.md) | 🏠 [README](../README.md)
