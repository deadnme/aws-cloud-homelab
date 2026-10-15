# 09 · Automation: the cloud health report

> **Goal:** write and run a Python (boto3) script that checks the AWS account for the mistakes behind most real incidents and surprise bills, the AWS counterpart of the AD health report from my AD lab.

## Why a company does this

Nobody can click through every console page every morning. Cloud teams script the checks they care about and run them on a schedule or in CI. Job posts that say "scripting (Python/Bash)" and "automation" mean exactly this: reading the AWS APIs and turning the results into a short list of things to fix.

## What it checks ([`scripts/cloud_health_report.py`](../scripts/cloud_health_report.py))

| Area | Check | Severity |
|---|---|---|
| Identity | Root user without MFA; root access keys | HIGH |
| Identity | IAM users without MFA | HIGH |
| Identity | Active long-lived access keys (with age) | MEDIUM |
| Network | Security groups open to `0.0.0.0/0` or `::/0` on anything except 80/443 (SSH, RDP and "all traffic" are HIGH) | HIGH / MEDIUM |
| Storage | Unencrypted EBS volumes; EBS encryption-by-default off | MEDIUM / LOW |
| Storage | S3 buckets without a full Block Public Access setting | HIGH |
| Databases | RDS publicly accessible; RDS unencrypted | HIGH / MEDIUM |
| Cost | Unattached EBS volumes, unused Elastic IPs (billed for nothing) | LOW |
| Cost | Running instances without a `Project` tag (invisible in cost reports) | LOW |
| Cost | Inventory of billable things running now: instances, load balancers, RDS, NAT gateways, volumes | INFO |

It only calls `Describe*`, `List*` and `Get*` APIs. It changes nothing. Exit code `1` if any HIGH finding, so a scheduler or CI job can fail on it.

## How it's built

- **Pure check functions** (`open_to_world`, `unencrypted_volumes`, …) take plain dicts shaped like the API responses. They're tested without an AWS account by [`scripts/test_cloud_health_report.py`](../scripts/test_cloud_health_report.py).
- **`collect()`** does the AWS calls with **paginators**, so it works with 5 resources or 5,000.
- `boto3` is imported inside `main()`, so the tests run even where boto3 isn't installed.

## Run it

```powershell
cd $HOME\aws-cloud-homelab
python -m pip install --user boto3         # same "python" as the commands below
python scripts\test_cloud_health_report.py # all checks passed
$env:AWS_PROFILE = 'harbor'
python scripts\cloud_health_report.py --markdown report.md
$LASTEXITCODE
```

boto3 uses the same `harbor` profile as the CLI and Terraform (`credential_process`, doc 02).

Run it twice: once with the full lab up, and once after `terraform destroy`. Expected with the lab up: INFO lines for the running instances, load balancer, RDS instance and volumes; **no** finding for `harbor-alb-sg` (port 80 to the world is the point of a public load balancer); no HIGH findings if docs 01-08 were followed. Expected after destroy: no INFO inventory lines. If something is still listed, doc 13's cleanup isn't finished.

`report.md` is git-ignored because it contains your account ID. To publish a sample (the way the AD lab did), copy it to `docs/sample-report.md` and mask the account ID first.

### Make it find something

Create a deliberately bad security group, run the report, then delete it:

```powershell
$vpc = aws ec2 describe-vpcs --filters "Name=tag:Name,Values=harbor-vpc" --query "Vpcs[0].VpcId" --output text
$sg = aws ec2 create-security-group --group-name report-test --description "health report test" --vpc-id $vpc --query GroupId --output text
aws ec2 authorize-security-group-ingress --group-id $sg --protocol tcp --port 22 --cidr 0.0.0.0/0
python scripts\cloud_health_report.py     # [HIGH] Security group open to the internet: sg-… (report-test) | Inbound tcp 22-22 from anywhere
aws ec2 delete-security-group --group-id $sg
```

## Ideas to extend it (good practice, not required)

- Run it every morning with **Windows Task Scheduler**, or as a **Lambda** function on an EventBridge schedule (Lambda's free tier covers this easily).
- Add checks: CloudTrail trail missing, IAM users who haven't signed in for 90 days, security groups attached to nothing, snapshots older than 30 days.
- Send the Markdown report to the `harbor-alerts` SNS topic.

## Verify it worked

| Check | Expected |
|---|---|
| `python scripts\test_cloud_health_report.py` | `all checks passed` |
| Report with the lab up | Inventory INFO lines, no HIGH |
| Bad SG test | HIGH finding for port 22, exit code 1 |
| Report after `terraform destroy` | No inventory lines |

_My output: (paste the report summary here, account ID masked)_

## Common mistakes

| Mistake | Result |
|---|---|
| No paginator on `describe_*` calls | Silently checks only the first page (often 50-1000 items) |
| Hard-coding access keys in the script | The script that checks for leaked keys becomes one. Use profiles and roles |
| Script that also "fixes" things automatically | One bug deletes production. Report first; auto-remediate only narrow, tested cases |
| Ignoring Regions | EC2/RDS checks are per Region. This script checks the profile's Region; loop over `ec2.describe_regions()` for all |

## Interview questions

- **"How would you find every security group open to SSH from the internet?"** `describe_security_groups` with a paginator, then filter `IpPermissions` for `0.0.0.0/0` or `::/0` covering port 22. Or AWS Config / Security Hub rules.
- **"How does boto3 find credentials?"** Same chain as the CLI: environment variables, profile files (including `credential_process`), then container/instance roles.
- **"What is a paginator and why use it?"** List APIs return results in pages. A paginator follows the `NextToken` for you, so nothing is missed.
- **"How would you run this daily in AWS?"** A Lambda function with a read-only role, triggered by an EventBridge schedule, publishing results to SNS.
- **"What AWS services already do this?"** Trusted Advisor (some checks free), AWS Config rules, Security Hub, IAM Access Analyzer. A script is still useful for company-specific rules.

⬅️ [08 · CloudWatch monitoring](08-cloudwatch-monitoring.md) | ➡️ [10 · Docker](10-docker.md)
