# AWS Cloud Homelab: "Harbor Point" client portal

A hands-on AWS lab aimed at **junior cloud, cloud support and cloud operations roles in the Philippines.** The fictional **Harbor Point Accounting** (the same 20-person firm from my [Windows AD homelab](https://github.com/deadnme/windows-ad-homelab)) moves its client portal from an office server to AWS. I build it with Terraform, run it, break it on purpose, and fix it the way a cloud support engineer would.

> **About this project:** this is a **learning lab**, not production experience. The guide, Terraform code and scripts were written with AI assistance (Claude). **I'm the one building it:** I set up the AWS account, type and run every command, troubleshoot what breaks, and work the break-fix tickets without looking at the answers. The docs only show output I actually saw in my own account. Sections marked _"My output"_ get filled in as I complete each module.

## What employers ask for, and where it's covered

Before building, I reviewed entry-level and junior cloud postings in the Philippines (AWS partners, BPO/telco cloud ops teams, the AWS Cloud Support Associate role) in October 2026, with AI-assisted web research. The same skills kept coming up:

| Employers ask for | Where it's covered in this lab |
|---|---|
| AWS core services: EC2, VPC, IAM, S3, RDS, ELB, CloudWatch | Docs 03–08 |
| Linux administration: services, logs, permissions | Doc 04 (Amazon Linux 2023, `systemd`, `journalctl`, nginx) |
| Networking: subnets, routing, DNS, firewalls, troubleshooting tools | Doc 03, doc 11, break-fix tickets BF-1/2/3/7 |
| Infrastructure as code (Terraform preferred) | [`terraform/`](terraform/), built up one file per doc |
| Scripting (Bash / Python) | [`scripts/`](scripts/): first-boot Bash, backup script, `cloud_health_report.py` (doc 09) |
| Monitoring, health checks, first-level troubleshooting | Docs 05, 08, 11 and eight break-fix tickets in doc 12 |
| Cost and billing awareness | Docs 01 and 13: budget alerts, tagging, teardown proof, Cost Explorer report |
| Docker basics | Doc 10 |
| AWS Cloud Practitioner → Solutions Architect Associate | Interview questions at the end of every doc follow the CLF-C02 / SAA-C03 topics |

## Architecture

```
                       Internet
                          │
              ┌───────────┴───────────┐
              │ Application Load       │  VPC 10.20.0.0/16, ap-southeast-1 (Singapore)
              │ Balancer (2 AZs)       │
              └─────┬─────────────┬────┘
        public      │  AZ a       │  AZ b
        subnets ┌───┴────┐    ┌───┴────┐
                │ EC2    │    │ EC2    │  Auto Scaling group, t4g.micro, Amazon Linux 2023
                │ nginx  │    │ nginx  │  SG: HTTP from the ALB only. No SSH, no port 22.
                │ + app  │    │ + app  │  Shell access through SSM Session Manager
                └───┬────┘    └───┬────┘
        private     └──────┬──────┘
        subnets      ┌─────┴──────┐
                     │ RDS        │  PostgreSQL 16, single-AZ. SG: 5432 from the app SG only
                     └────────────┘

   Parameter Store (/harbor/*: DB settings, SecureString password) ◄── instance role
   S3 backup bucket (versioned, encrypted, private) ◄── instance role (write db/* only, no delete)
   CloudWatch agent ──► metrics, nginx logs, 4 alarms ──► SNS email     AWS Budgets $5/month · CloudTrail
```

**Deliberate cost trade-offs** (and what production would do instead):

| This lab | Production | Why the lab differs |
|---|---|---|
| App instances in public subnets, locked down by security groups | Private subnets plus a NAT Gateway or VPC endpoints | A NAT Gateway costs roughly $40/month in Singapore |
| RDS single-AZ, 1-day backups | RDS Multi-AZ, longer retention, deletion protection | Doubles the database cost |
| HTTP on the load balancer's DNS name | HTTPS with ACM and a Route 53 domain | Needs a paid domain |
| Local Terraform state | S3 backend with locking | One person, one environment |
| IAM user with MFA + `aws login` | IAM Identity Center | Identity Center creates an AWS Organization, which ends the Free Plan |

## Cost rules

1. A budget alert exists before any resource does (doc 01).
2. Terraform tags every resource `Project=aws-cloud-homelab`.
3. Every session ends with `terraform destroy`. With everything running, the lab costs roughly **$0.10/hour** of credits.
4. Doc 13 proves nothing was left behind and records the real total from Cost Explorer.

## Step-by-step documentation

Each page follows the same layout: **Goal → Why a company does this → What gets built → Steps → Verify → Common mistakes → Interview questions**.

| # | Page | You'll learn | Status |
|---|---|---|---|
| 00 | [What is AWS](docs/00-what-is-aws.md) | Regions, AZs, shared responsibility, billing, AD lab → AWS map | 📖 read |
| 01 | [Account setup and hardening](docs/01-account-setup-and-hardening.md) | Root MFA, admin user, billing access, budget, CloudTrail | 📝 to run |
| 02 | [Workstation tooling](docs/02-workstation-tooling.md) | AWS CLI, `aws login`, Terraform smoke test, the `lab/` folder | 📝 to run |
| 03 | [VPC networking](docs/03-vpc-networking.md) | Subnets, route tables, internet gateway, SG vs NACL, CIDR math | 📝 to run |
| 04 | [Linux on EC2](docs/04-linux-on-ec2.md) | User data, `systemd`, logs, IMDSv2, Session Manager instead of SSH | 📝 to run |
| 05 | [Load balancer and Auto Scaling](docs/05-load-balancer-and-auto-scaling.md) | Health checks, SG chaining, self-healing, rolling updates | 📝 to run |
| 06 | [RDS PostgreSQL](docs/06-rds-postgresql.md) | Private database, Parameter Store secrets, `psql` | 📝 to run |
| 07 | [S3 and IAM roles](docs/07-s3-and-iam-roles.md) | Backups to S3, least privilege, AccessDenied, policy simulator | 📝 to run |
| 08 | [CloudWatch monitoring](docs/08-cloudwatch-monitoring.md) | Agent, log groups, Logs Insights, alarms → email, dashboard | 📝 to run |
| 09 | [Automation: cloud health report](docs/09-automation-cloud-health-report.md) | Python + boto3 account checks | 📝 to run |
| 10 | [Docker](docs/10-docker.md) | Images, layers, containers; ECR/ECS/EKS | 📝 to run |
| 11 | [Troubleshooting and lessons](docs/11-troubleshooting-and-lessons.md) | A repeatable method and toolkit; what broke for me | 📝 to run |
| 12 | [Break-fix tickets](docs/12-break-fix-tickets.md) | Eight faults found and fixed from the ticket alone | 📝 to run |
| 13 | [Teardown and cost report](docs/13-teardown-and-cost-report.md) | Proving nothing is left; the real total cost | 📝 to run |
| – | [Glossary](docs/glossary.md) | Every term in one place | 📖 read |

## Repository layout

| Path | Contents |
|---|---|
| `docs/` | The pages above |
| `terraform/` | The finished lab: one root module, one file per doc (`network.tf`, `compute.tf`, `alb.tf`, `rds.tf`, `s3.tf`, `monitoring.tf`) |
| `app/` | The portal (`app.py`, Python standard library + boto3 + psycopg) and its `Dockerfile` |
| `scripts/` | `user-data.sh.tftpl` (first boot), `cloud_health_report.py` + its self-test |
| `breakfix/` | `break.ps1` / `restore.ps1` for the doc 12 tickets (**spoilers**: don't read before solving) |
| `.github/workflows/terraform.yml` | `terraform fmt` and `validate` on every push. No AWS credentials in GitHub |
| `screenshots/`, `media/` | Real screenshots and the demo video from my account |

> ⚠️ Before every push: `git grep -nE "A(KI|SI)A[0-9A-Z]{16}|aws_secret_access_key *=|aws_session_token *="` must return nothing, and `git status` must not list any `.tfstate` file or `lab/`.

## Skills practised

AWS (IAM, VPC, EC2, ELB, Auto Scaling, RDS, S3, CloudWatch, CloudTrail, SNS, Budgets, Systems Manager) · Terraform · AWS CLI · Linux (Amazon Linux 2023, systemd, nginx) · networking · PostgreSQL · Python (boto3) · Bash · PowerShell · Docker · troubleshooting · cost control · documentation
