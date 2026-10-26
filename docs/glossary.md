# Glossary

| Term | Meaning |
|---|---|
| **ALB** (Application Load Balancer) | Layer-7 (HTTP/HTTPS) load balancer. Spreads requests across targets in several AZs and health-checks them (doc 05) |
| **AMI** | Amazon Machine Image: the disk image an EC2 instance boots from |
| **ARN** | Amazon Resource Name, the unique ID of any AWS resource, e.g. `arn:aws:iam::123456789012:role/harbor-app-role` |
| **Auto Scaling group (ASG)** | Keeps a set number of instances running, replaces unhealthy ones, scales on load (doc 05) |
| **Availability Zone (AZ)** | One or more isolated data centres inside a Region (doc 00) |
| **AWS Settings** | The site (settings.aws.com) where a new-experience customer manages projects, billing, credits and team members (doc 01) |
| **`aws login`** | AWS CLI command (2.32.0+) that gets short-lived credentials from a browser sign-in (doc 02) |
| **AWS Builder ID** | Your personal AWS profile. In the new AWS experience it owns your projects instead of a root user (doc 01) |
| **boto3** | The AWS SDK for Python (doc 09) |
| **CIDR** | Notation for an IP range, e.g. `10.20.0.0/16` = 65,536 addresses (doc 03) |
| **cloud-init / user data** | The first-boot script mechanism on EC2. Log: `/var/log/cloud-init-output.log` (doc 04) |
| **CloudTrail** | Audit log of AWS API calls: who did what, when, from where (doc 01) |
| **CloudWatch** | Metrics, logs, alarms and dashboards (doc 08) |
| **CloudWatch agent** | Software on the instance that sends OS metrics (memory, disk) and log files to CloudWatch |
| **Cost allocation tag** | A tag activated in Billing so Cost Explorer can group spend by it. Not available in a new-experience project without advanced features (doc 03, 13) |
| **`credential_process`** | AWS config setting that runs a command to fetch credentials; used to give Terraform the `aws login` session (doc 02) |
| **Drift** | Real infrastructure no longer matching the Terraform code because of a manual change (doc 11, 12) |
| **EBS** | Elastic Block Store: the network disks attached to EC2 instances |
| **EC2** | Elastic Compute Cloud: virtual servers (doc 04) |
| **ECR / ECS / EKS / Fargate** | Container registry / AWS's container orchestrator / managed Kubernetes / serverless compute for containers (doc 10) |
| **Free Plan / Free Tier credits** | New-account plan (since July 2025): credits instead of a bill, for 6 months or until the credits run out (doc 00, 01) |
| **Health check** | The load balancer's regular request (`GET /health`) deciding whether a target gets traffic |
| **IAM** | Identity and Access Management: users, groups, roles and policies (doc 01, 07) |
| **IAM role** | An identity that something assumes for temporary credentials, e.g. an EC2 instance (doc 04, 07) |
| **IMDS / IMDSv2** | Instance Metadata Service at `169.254.169.254`. v2 requires a session token (doc 04) |
| **Instance profile** | The container that attaches an IAM role to an EC2 instance |
| **Instance refresh** | Rolling replacement of an ASG's instances, e.g. after a launch template change (doc 05, 08) |
| **Internet gateway (IGW)** | Connects a VPC to the internet. A route to it makes a subnet public (doc 03) |
| **Launch template** | The recipe an ASG uses for new instances: AMI, type, SG, role, user data (doc 04) |
| **Least privilege** | Granting only the permissions a job needs (doc 07) |
| **Multi-AZ (RDS)** | A synchronous standby database in another AZ with automatic failover (doc 06) |
| **NAT Gateway** | Lets private-subnet resources reach the internet outbound. Paid per hour; not used in this lab (doc 03) |
| **Network ACL (NACL)** | Stateless, ordered allow/deny rules on a subnet (doc 03, BF-3) |
| **Parameter Store** | Part of AWS Systems Manager: stores settings and secrets (`SecureString`) (doc 06) |
| **Project** | In the new AWS experience: one AWS account plus its sharing settings, limited to one Region (doc 01) |
| **RDS** | Relational Database Service: managed PostgreSQL, MySQL and others (doc 06) |
| **Region** | A geographic area with its own copy of AWS services, e.g. `ap-southeast-2` Sydney (doc 00) |
| **Route table** | Decides where traffic leaving a subnet goes (doc 03) |
| **S3** | Simple Storage Service: object storage in buckets (doc 07) |
| **SCP** (service control policy) | A guardrail above the account that caps what any role in it can do. AWS sets them on new-experience projects (doc 01) |
| **S3 Block Public Access** | Bucket/account settings that override anything that would make data public |
| **Security group (SG)** | Stateful, allow-only firewall on a network interface. Can reference other SGs (doc 03, 05) |
| **Session Manager** | Systems Manager feature: a shell on an instance through the AWS API, no SSH or open ports (doc 04) |
| **Shared responsibility model** | AWS secures the cloud; the customer secures what's in it (doc 00) |
| **SNS** | Simple Notification Service: topics that fan out messages, e.g. alarm emails (doc 08) |
| **SSM agent** | The Systems Manager agent on the instance; needed for Session Manager and Run Command |
| **STS** | Security Token Service: issues temporary credentials (`aws sts get-caller-identity`) |
| **Target group** | The set of targets (instances) behind a load balancer listener, plus the health check (doc 05) |
| **Terraform state** | Terraform's record of what it created; never committed to Git (doc 02) |
| **VPC** | Virtual Private Cloud: your isolated network in a Region (doc 03) |
| **Well-Architected Framework** | AWS's six pillars of good design (doc 00) |
