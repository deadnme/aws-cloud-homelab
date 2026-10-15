# 00 · What is AWS, and what this lab builds

_Guide written with AI assistance; the build, outputs and notes are mine._

> **Goal:** understand the few AWS ideas that every later page depends on: Regions and Availability Zones, the shared responsibility model, how billing works, and which AWS service replaces which part of the Harbor Point AD lab.

## Why a company does this

Harbor Point Accounting runs a small **client portal**. Clients log in, see their invoices and upload documents. Today it runs on one server in the office closet. If that server, the office internet or the office power fails, the portal is down. Buying a second server and a second internet line costs money up front (CapEx) and still leaves everything in one building.

On AWS, Harbor Point rents servers by the second (OpEx), puts copies of the app in **two separate data centres**, and stops paying for anything the moment it is deleted. The trade-off is that the bill now depends on what is left running. Cost control becomes part of the IT job, so this lab treats it as a skill (docs 01 and 13).

## Regions and Availability Zones

| Term | What it is | In this lab |
|---|---|---|
| **Region** | A geographic area with its own separate copy of most AWS services, e.g. `ap-southeast-1` | **Asia Pacific (Singapore)**, the closest full Region to the Philippines, so latency from Manila is low |
| **Availability Zone (AZ)** | One or more data centres inside a Region, with separate power and networking, linked to the other AZs by fast private fibre | Two AZs, so one AZ can fail and the portal keeps running |
| **Edge location** | A smaller site used by CloudFront (CDN) and Route 53 (DNS) to serve users nearby | Not used. No domain name in this lab |

> 🎓 **AZ names are shuffled per account.** Your `ap-southeast-1a` may be a different building from someone else's `ap-southeast-1a`. The fixed name is the **AZ ID** (e.g. `apse1-az1`). This matters when two accounts must line up in the same physical AZ.

**Most services are regional.** If the console is set to N. Virginia (`us-east-1`), you will not see resources you built in Singapore. "My EC2 instance disappeared" is usually a wrong-Region problem. Some services are **global**: IAM, Billing, Budgets, CloudFront and Route 53.

## The shared responsibility model

AWS secures **the cloud** (buildings, hardware, the hypervisor, the network between AZs). The customer secures **what they put in the cloud**. How much falls on the customer depends on the service:

| Service | AWS handles | Harbor Point (me) handles |
|---|---|---|
| **EC2** (virtual server) | Hardware, hypervisor | OS patches, firewall rules (security groups), app, who can log in |
| **RDS** (managed database) | Hardware, OS, database engine patches, automated backups | Network access, database users, choosing encryption, choosing a backup retention period |
| **S3** (object storage) | Durability and availability of the stored files | Bucket policy, blocking public access, encryption setting, versioning |
| **IAM** (identity) | The service itself | Every user, role and policy, and MFA |

> 🎓 **Interview shortcut:** the more "managed" the service, the less you patch, but **identity, access and data settings are always yours.** Most cloud breaches in the news come from customer-side settings, such as a public S3 bucket or leaked access keys, not from AWS failures.

## From the AD lab to AWS

Most AWS services have a counterpart in the Windows lab I already built. This is the map I use:

| Job | Harbor Point AD lab | AWS (this lab) |
|---|---|---|
| Who can sign in and do what | AD users, groups, delegation | **IAM** users, groups, roles, policies |
| A server | DC01 VM in VirtualBox | **EC2** instance |
| Network and firewall | NAT Network `HarborNet`, Windows Firewall | **VPC**, subnets, route tables, **security groups** |
| File storage | `\\DC01\Public` share, NTFS permissions | **S3** bucket, bucket policy |
| Database | (none) | **RDS** PostgreSQL |
| Logs and alerts | Event Viewer, event 4740 | **CloudWatch** Logs and alarms, **CloudTrail** |
| "Who changed this?" | Security log auditing on the DC | **CloudTrail** event history |
| Build it again from scratch | `scripts/*.ps1` | **Terraform** |
| Health check script | `health-report/` (PowerShell) | `cloud-health-report.py` (Python, boto3), doc 09 |

## How AWS billing works (and what this lab does about it)

- **On-demand, per second or per hour.** A running EC2 instance costs money every hour, **even when nobody uses the app.**
- **Some things cost money while "doing nothing":** EBS disks, public IPv4 addresses (AWS charges for every public IPv4 address, about $0.005/hour), a load balancer that exists, an RDS database that exists, a NAT Gateway (roughly $40/month in Singapore before data charges, so this lab avoids it).
- **Free Plan (accounts created after July 2025):** new accounts get $100 in credits, plus up to $100 more for completing onboarding activities. The Free Plan ends after 6 months or when the credits run out, whichever comes first. Usage is paid from the credits. Check the exact current terms on the [AWS Free Tier page](https://aws.amazon.com/free/), because they change.

**Lab rules:**
1. A budget alert exists before any resource does (doc 01).
2. Every resource is tagged `Project=aws-cloud-homelab` by Terraform (`terraform/providers.tf`).
3. Every session ends with `terraform destroy`.
4. Doc 13 proves nothing was left behind and records the total cost.

## The Well-Architected Framework (one paragraph)

AWS's checklist for a good design has six pillars: **Operational Excellence, Security, Reliability, Performance Efficiency, Cost Optimization, Sustainability.** This lab touches each one: alarms and runbooks (operations), no SSH and least-privilege roles (security), two AZs and auto scaling (reliability), right-sized `t4g.micro` instances (performance), destroy-after-use and budgets (cost), and nothing left idle (sustainability).

## Common mistakes

| Mistake | Result |
|---|---|
| Building in the console's default Region by accident | Resources "disappear" when you switch to Singapore, and they keep costing money |
| Thinking "stopped" means free | A stopped EC2 instance still pays for its EBS disk. RDS restarts by itself after 7 days stopped |
| Thinking managed means "AWS secures it for me" | Public buckets and open security groups are still your fault |
| Using the root account day to day | One stolen password owns the whole account. See doc 01 |

## Interview questions

- **"What's the difference between a Region and an Availability Zone?"** A Region is a geographic area. An AZ is an isolated data centre group inside it. You spread an app across at least two AZs so one failure doesn't take it down.
- **"Explain the shared responsibility model."** AWS secures the infrastructure. The customer secures their data, identities and configuration. With EC2 I patch the OS. With RDS, AWS patches the engine, but I still control network access and database users.
- **"How would you make a web app highly available on AWS?"** Instances in two or more AZs behind a load balancer, an Auto Scaling group to replace failed instances, and a database with a standby (RDS Multi-AZ). That is the shape of this lab, except the database is single-AZ to save credits.
- **"What is CapEx vs OpEx?"** CapEx is buying hardware up front. OpEx is paying as you go. Cloud moves IT spending to OpEx.
- **"Name the six Well-Architected pillars."** Operational Excellence, Security, Reliability, Performance Efficiency, Cost Optimization, Sustainability.
- **"Why Singapore and not N. Virginia?"** It is closer to users in the Philippines (lower latency). Data-residency rules can also decide the Region.

➡️ [01 · Account setup and hardening](01-account-setup-and-hardening.md)
