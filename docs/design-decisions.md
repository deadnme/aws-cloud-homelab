# Design decisions

> **Goal:** record *why* the lab is built the way it is: what was chosen, what else was considered, what the choice costs, and when it should change. Each **Revisit when** line answers the interview question *"What would you change for production?"*

The decisions were made when the lab was written (with AI assistance, see the [README](../README.md)), before any of it ran in a real account. If a real run proves a decision wrong, the change and the reason go into [doc 11](11-troubleshooting-and-lessons.md) and the entry here gets updated.

Three constraints drive almost every decision:

1. **Free Plan, credits only.** Nothing may end the Free Plan (that rules out AWS Organizations and IAM Identity Center), and anything billed by the hour while idle has to justify itself.
2. **Teach what PH junior cloud postings ask for:** EC2, Linux, VPC, IAM, RDS, S3, CloudWatch, Terraform (see the [README table](../README.md#what-employers-ask-for-and-where-its-covered)).
3. **Build it, break it, destroy it every session.** Everything must come back with one `terraform apply`.

## Architecture

The diagram is in the [README](../README.md#architecture). The decisions below refer to the parts shown there.

## Index

| # | Decision | Doc |
|---|---|---|
| [D-01](#d-01-region-ap-southeast-1-singapore) | Region: Singapore | 00 |
| [D-02](#d-02-identity-iam-user-with-mfa-and-aws-login-no-access-keys) | Identity: IAM user + MFA + `aws login`, no access keys | 01, 02 |
| [D-03](#d-03-billing-guards-are-made-by-hand-not-by-terraform) | Budget and CloudTrail made by hand, not by Terraform | 01 |
| [D-04](#d-04-terraform-one-root-module-local-state) | Terraform, one root module, local state | 02 |
| [D-05](#d-05-app-servers-in-public-subnets-no-nat-gateway) | App servers in public subnets, no NAT Gateway | 03 |
| [D-06](#d-06-two-azs-four-24-subnets) | Two AZs, four /24 subnets | 03 |
| [D-07](#d-07-ec2-in-an-auto-scaling-group-not-containers-or-serverless) | EC2 in an Auto Scaling group, not containers or serverless | 04, 05 |
| [D-08](#d-08-graviton-t4gmicro-and-the-latest-al2023-ami) | Graviton `t4g.micro`, latest AL2023 AMI | 04 |
| [D-09](#d-09-configure-servers-with-user-data-not-a-baked-ami) | Configure servers with user data, not a baked AMI | 04 |
| [D-10](#d-10-session-manager-instead-of-ssh) | Session Manager instead of SSH | 04 |
| [D-11](#d-11-imdsv2-required-hop-limit-2) | IMDSv2 required, hop limit 2 | 04, 10 |
| [D-12](#d-12-application-load-balancer-on-http-with-a-shallow-health-check) | ALB on HTTP, shallow `/health` check | 05 |
| [D-13](#d-13-security-groups-reference-each-other-not-ip-ranges) | Security groups reference each other | 05, 06 |
| [D-14](#d-14-rds-postgresql-single-az) | RDS PostgreSQL, single-AZ | 06 |
| [D-15](#d-15-parameter-store-for-settings-and-the-password) | Parameter Store for settings and the password | 06 |
| [D-16](#d-16-pg_dump-backups-to-s3-with-a-role-that-cannot-delete) | `pg_dump` backups to S3, role can't delete | 07 |
| [D-17](#d-17-cloudwatch-agent-alarms-and-email) | CloudWatch agent, 4 alarms, email | 08 |
| [D-18](#d-18-a-tiny-stdlib-python-app-behind-nginx) | Tiny stdlib Python app behind nginx | 04 |
| [D-19](#d-19-ci-runs-fmt-and-validate-only) | CI runs `fmt` and `validate` only | – |

---

## D-01 Region: ap-southeast-1 (Singapore)

- **Choice:** every resource in `ap-southeast-1` ([`variables.tf`](../terraform/variables.tf)).
- **Considered:** Hong Kong (`ap-east-1`) and Taipei (`ap-east-2`), which are closer to Manila; `us-east-1` (often slightly cheaper, and new services usually launch there first).
- **Why:** Singapore is the oldest AWS Region in Southeast Asia (2010), with the widest range of services nearby, and it is the parent Region of the Manila Local Zone. Hong Kong and Taipei are opt-in Regions with fewer services. Latency from Manila has not been measured for this lab.
- **Trade-off:** prices are a little higher than `us-east-1`. Global services (IAM, Budgets) still log their CloudTrail events in `us-east-1`, which doc 01 points out.
- **Revisit when:** data residency or a client contract names a specific Region.

## D-02 Identity: IAM user with MFA and `aws login`, no access keys

- **Choice:** root has MFA and is locked away. Daily work uses the IAM user `sean.admin` with MFA. The CLI signs in with `aws login` (short-lived credentials), and Terraform/boto3 reuse them through `credential_process` (doc 02).
- **Considered:** IAM Identity Center (the production standard); an IAM user with long-lived access keys; using root.
- **Why:** Identity Center needs AWS Organizations, and creating an organization upgrades a Free Plan account and ends the credits. Access keys are the credential most often leaked (Git commits, screenshots). Root is never for daily use.
- **Trade-off:** IAM users don't scale past one or two people, and there's no central place to manage several accounts.
- **Revisit when:** the account moves to a paid plan or a second person or account joins. Then: Identity Center with permission sets.

## D-03 Billing guards are made by hand, not by Terraform

- **Choice:** the $5 budget and CloudTrail event history are set up in the console in doc 01, before Terraform creates anything.
- **Considered:** `aws_budgets_budget` in Terraform; a CloudTrail trail delivering to S3.
- **Why:** `terraform destroy` runs every session. A budget in the same state would be destroyed with everything else, leaving no alert exactly when it's needed most. Event history keeps 90 days of management events for free, and a trail adds an S3 bucket and setup for little gain in a one-person lab.
- **Trade-off:** two settings live outside code, so they're documented as manual steps instead.
- **Revisit when:** there's a long-lived "account baseline" Terraform state separate from the lab, or logs must be kept longer than 90 days (then: an organization trail to a locked-down S3 bucket).

## D-04 Terraform, one root module, local state

- **Choice:** Terraform with the AWS provider, one root module, one `.tf` file per doc, state on the laptop ([`terraform/`](../terraform/)).
- **Considered:** clicking in the console; CloudFormation; AWS CDK; reusable Terraform modules; an S3 backend with state locking.
- **Why:** PH postings that name an IaC tool mostly name Terraform. Destroy-and-rebuild every session only works if the whole lab is code. One file per doc lets the lab grow in the same order as the docs (`lab/` gets one file at a time). Modules and a remote backend solve problems of teams and many environments, and this lab has one person and one environment.
- **Trade-off:** local state holds the database password in plain text ([D-15](#d-15-parameter-store-for-settings-and-the-password)) and is lost if the laptop is. That's acceptable for a lab that is destroyed every session.
- **Revisit when:** a second person or a second environment (dev/prod). Then: S3 backend with locking, and modules per layer (network, app, data).

## D-05 App servers in public subnets, no NAT Gateway

- **Choice:** the app instances sit in the public subnets with public IPs. Only the database is private ([`network.tf`](../terraform/network.tf)).
- **Considered:** private app subnets with a NAT Gateway; private app subnets with VPC endpoints.
- **Why:** a NAT Gateway costs roughly $40/month in Singapore (about $0.06/hour), idle or not. That adds more than half again to the lab's roughly $0.10/hour, and one per AZ would about double it. VPC interface endpoints (SSM, CloudWatch Logs, CloudWatch metrics) are also billed per hour per AZ, and `pip` still needs a way out to PyPI. The security groups do the protecting: nothing from the internet reaches an instance except port 80 from the ALB, and there is no SSH.
- **Trade-off:** instances have public IPs (about $0.005/hour each), and a mistake in a security group exposes them directly. Break-fix tickets practise exactly that kind of mistake.
- **Revisit when:** the portal holds real client data. Then: app servers in private subnets with a NAT Gateway per AZ, or endpoints plus a baked AMI so instances never need the internet.

## D-06 Two AZs, four /24 subnets

- **Choice:** `10.20.0.0/16`, one public and one private `/24` in each of two AZs.
- **Considered:** the default VPC; three AZs; smaller subnets.
- **Why:** the default VPC has no private subnets, so it teaches nothing about routing. An ALB needs subnets in at least two AZs and so does an RDS subnet group, so two is the minimum that shows high availability. `/24`s are easy to read in the CIDR exercises (doc 03), and `10.20.0.0/16` doesn't overlap the AD lab's `10.10.10.0/24`, so the two could be joined by a VPN later without renumbering either.
- **Trade-off:** losing one of two AZs halves capacity.
- **Revisit when:** production. Then: three AZs, and an IP plan agreed with the on-premises network.

## D-07 EC2 in an Auto Scaling group, not containers or serverless

- **Choice:** two EC2 instances in an Auto Scaling group (min 2, max 3), health-checked by the ALB, rolling instance refresh ([`compute.tf`](../terraform/compute.tf)).
- **Considered:** a single EC2 instance; ECS on Fargate; Lambda + API Gateway; Elastic Beanstalk.
- **Why:** junior cloud and cloud support roles expect EC2 and Linux administration, and the point of docs 04–05 is to see `systemd`, logs and nginx on a real server. The Auto Scaling group gives the self-healing demo (terminate an instance, watch it come back). Fargate and Lambda hide the operating system. Beanstalk hides how the pieces connect. Containers are covered separately in doc 10.
- **Trade-off:** more to patch and look after than a managed service.
- **Revisit when:** the app is shipped as a container image anyway (doc 10). Then: ECS on Fargate behind the same ALB. There is no scaling policy because the load is tiny. Add target tracking on CPU if traffic ever grows; until then the CPU alarm emails instead.

## D-08 Graviton t4g.micro and the latest AL2023 AMI

- **Choice:** `t4g.micro` (Arm). The AMI ID comes from AWS's public SSM parameter for the latest Amazon Linux 2023.
- **Considered:** `t3.micro` (x86); a hard-coded AMI ID.
- **Why:** `t4g.micro` is about 20% cheaper than `t3.micro` for the same size. A hard-coded AMI ID goes stale and differs per Region.
- **Trade-off:** Arm means container images must exist for `arm64` (the Python base image in doc 10 does). "Latest AMI" means two applies on different days can boot different images.
- **Revisit when:** a vendor tool only ships x86, or builds must be reproducible. Then: a pinned, tested AMI (see D-09).

## D-09 Configure servers with user data, not a baked AMI

- **Choice:** a first-boot script installs nginx, the app, the backup script and the CloudWatch agent ([`user-data.sh.tftpl`](../scripts/user-data.sh.tftpl)). Terraform inlines `app.py` and the `Dockerfile` into it.
- **Considered:** a "golden" AMI built with Packer; Ansible or SSM State Manager.
- **Why:** one file to read, nothing extra to install, and changing it rolls the fleet through an instance refresh. It also shows how instances are configured at boot, which comes up a lot in support tickets.
- **Trade-off:** every new instance downloads packages on first boot, so launching is slow (hence the 300-second health check grace period) and fails if a package repository is down. The app code travels in user data, which has a 16 KB limit (the rendered script is about 9 KB now).
- **Revisit when:** boot time matters for scaling, or the app grows. Then: bake an AMI with Packer, or move to containers.

## D-10 Session Manager instead of SSH

- **Choice:** no key pair, no port 22. Shell access is `aws ssm start-session`.
- **Considered:** SSH with a key pair; SSH through a bastion host; EC2 Instance Connect.
- **Why:** Session Manager is authenticated by IAM (with MFA), is recorded in CloudTrail, and needs no open inbound port and no key to lose or share. A bastion is one more server to patch and pay for.
- **Trade-off:** the instance needs the SSM agent and a path to the SSM service, and copying files is less direct than `scp`.
- **Revisit when:** rarely. Production adds session logging to S3 or CloudWatch Logs.

## D-11 IMDSv2 required, hop limit 2

- **Choice:** `http_tokens = "required"`, `http_put_response_hop_limit = 2`.
- **Considered:** IMDSv1 allowed (the old default); hop limit 1.
- **Why:** IMDSv2 blocks the classic SSRF attack that steals instance role credentials. Hop limit 2 lets the Docker container in doc 10 still reach the metadata service through the extra network hop.
- **Trade-off:** hop limit 2 also lets any container on the host get the instance role's credentials.
- **Revisit when:** no containers run on the instances. Then: hop limit 1.

## D-12 Application Load Balancer on HTTP with a shallow health check

- **Choice:** an internet-facing ALB on port 80. The target group checks `GET /health` every 15 seconds, and the Auto Scaling group uses that result (`health_check_type = "ELB"`) ([`alb.tf`](../terraform/alb.tf)).
- **Considered:** a Network Load Balancer; one instance with an Elastic IP; HTTPS with an ACM certificate; a health check that also queries the database.
- **Why:** the portal is HTTP, and an ALB understands HTTP (paths, status codes, 5xx metrics). HTTPS needs a domain to validate the certificate against, and the lab has no paid domain. `/health` deliberately does not touch the database ([`app.py`](../app/app.py)): if it did, one slow database would mark every server unhealthy and the Auto Scaling group would replace healthy servers in a loop.
- **Trade-off:** traffic is unencrypted, so nothing real may go through it. A broken database shows up as 5xx errors from `/db` (`HTTPCode_Target_5XX_Count`), not as unhealthy targets, and no alarm watches that metric today (see D-17).
- **Revisit when:** there is a domain. Then: Route 53, an ACM certificate, an HTTPS listener and a port 80 → 443 redirect.

## D-13 Security groups reference each other, not IP ranges

- **Choice:** the app SG allows port 80 from *the ALB's security group*, and the DB SG allows 5432 from *the app's security group*.
- **Considered:** CIDR rules such as "port 80 from 10.20.1.0/24".
- **Why:** a reference stays correct when instances are replaced or subnets change, and it says what is meant: "only the load balancer may talk to the app".
- **Trade-off:** none worth noting. This is standard practice.
- **Revisit when:** never for this design.

## D-14 RDS PostgreSQL, single-AZ

- **Choice:** RDS PostgreSQL 16, `db.t4g.micro`, 20 GB gp3, encrypted, private, single-AZ, 1-day automated backups ([`rds.tf`](../terraform/rds.tf)).
- **Considered:** PostgreSQL on an EC2 instance; Aurora; DynamoDB; Multi-AZ RDS.
- **Why:** RDS does backups, patching and (with Multi-AZ) failover, which is what most companies pay AWS for, and RDS appears in nearly every posting. Self-managed PostgreSQL teaches DBA work instead of cloud work. Aurora and Multi-AZ cost more for no lab benefit. DynamoDB would need a different app.
- **Trade-off:** an AZ failure takes the database down. `skip_final_snapshot` and no deletion protection mean `terraform destroy` deletes the data with no way back, on purpose.
- **Revisit when:** production. Then: Multi-AZ, 7–35 days of backups, deletion protection and a final snapshot.

## D-15 Parameter Store for settings and the password

- **Choice:** Terraform generates the password and stores it in SSM Parameter Store as a SecureString under `/harbor/`. The app and the backup script read it at run time with the instance role.
- **Considered:** AWS Secrets Manager; putting the password in user data or an environment file; RDS-managed master passwords.
- **Why:** standard Parameter Store parameters are free, and Secrets Manager costs about $0.40 per secret per month. Nothing secret is written to the instance's disk or its user data, which anyone with `ec2:DescribeInstanceAttribute` can read.
- **Trade-off:** no automatic rotation. The lab's own policy scopes reads to `/harbor/*`, but the attached AWS managed policy `AmazonSSMManagedInstanceCore` also allows `ssm:GetParameter` and `ssm:GetParameters` on every parameter, so in practice the role can read any String parameter, and any SecureString encrypted with the default `aws/ssm` key, in the account. The password is also in `terraform.tfstate` in plain text, which is one more reason state never goes into Git.
- **Revisit when:** rotation is required, or other secrets share the account. Then: Secrets Manager with rotation, or `manage_master_user_password` so the password never passes through Terraform, and a custom replacement for `AmazonSSMManagedInstanceCore` without account-wide parameter reads.

## D-16 pg_dump backups to S3 with a role that cannot delete

- **Choice:** `harbor-backup` dumps the database to the S3 bucket under `db/`. The bucket is private, versioned, encrypted with SSE-S3, HTTPS-only, and expires backups after 30 days. The instance role may list, put and get under `db/` but **not delete** ([`s3.tf`](../terraform/s3.tf)).
- **Considered:** relying only on RDS automated backups; AWS Backup; SSE-KMS with a customer managed key; S3 Object Lock.
- **Why:** a logical dump is a second, portable copy that survives deleting the RDS instance, and it's the clearest way to practise least privilege (doc 07). A server that gets taken over can't delete backups. It can overwrite them, but versioning keeps the old copy for 7 days after an overwrite, so an attack must be noticed within that week. SSE-S3 costs nothing. A customer managed KMS key costs about $1/month and adds key policies the lab doesn't need yet.
- **Trade-off:** backups run only when someone runs the script (there is no schedule). `force_destroy = true` lets `terraform destroy` delete the bucket with backups inside, for the lab only.
- **Revisit when:** production. Then: schedule it (systemd timer or AWS Backup), Object Lock or a copy to a second account for ransomware protection, and no `force_destroy`.

## D-17 CloudWatch agent, alarms and email

- **Choice:** the CloudWatch agent sends memory, disk and nginx logs. Four alarms (CPU, unhealthy targets, ALB 5xx, disk) go to an SNS topic with an email subscription, plus one dashboard ([`monitoring.tf`](../terraform/monitoring.tf)).
- **Considered:** default EC2 metrics only; Prometheus and Grafana; a third-party tool.
- **Why:** default EC2 metrics don't include memory or disk. CloudWatch is what AWS support and ops teams use first, and it needs no extra servers. Terraform creates the log groups with 7-day retention, and the agent policy deliberately lacks `logs:CreateLogGroup`, so a still-running agent can't recreate a group during `terraform destroy` and break the next apply. The agent publishes a combined metric per Auto Scaling group, so alarms keep working when instances are replaced.
- **Trade-off:** email is not paging, and nobody is woken up. There is no alarm on the database itself or on `/db` errors.
- **Revisit when:** someone is on call. Then: route SNS to a paging or chat tool, and add RDS alarms (CPU, free storage, connections) and an app-level check on `/db`.

## D-18 A tiny stdlib Python app behind nginx

- **Choice:** `app.py` uses the Python standard library HTTP server, plus boto3 and psycopg imported only inside `/db`. nginx in front proxies to it on `127.0.0.1:8080`.
- **Considered:** Flask or Django; a static site; serving straight from Python on port 80.
- **Why:** the lab is about infrastructure, so the app stays small enough to read in a few minutes. Lazy imports keep `/` and `/health` working even if boto3 or psycopg is missing or fails to import. nginx is what real Linux servers run in front of apps, and its access and error logs feed CloudWatch.
- **Trade-off:** the stdlib server is not built for production traffic.
- **Revisit when:** the app does real work. Then: a framework with a production WSGI/ASGI server, still behind nginx or straight behind the ALB.

## D-19 CI runs fmt and validate only

- **Choice:** GitHub Actions runs `terraform fmt -check` and `terraform validate` on every push, with no AWS credentials ([`.github/workflows/terraform.yml`](../.github/workflows/terraform.yml)).
- **Considered:** `terraform plan` in CI using OIDC federation to an IAM role.
- **Why:** it catches syntax and formatting mistakes for free, and a public repo with no cloud credentials has nothing to leak.
- **Trade-off:** CI can't catch mistakes that only AWS can see (a bad AMI, a quota, a wrong ARN).
- **Revisit when:** there's shared state (D-04). Then: OIDC to a read-only plan role, with `plan` output on pull requests.
