# 07 · S3 backups and least-privilege IAM roles

> **Goal:** back up the portal database to a private, versioned, encrypted S3 bucket, using only the server's IAM role, and prove the role can do **exactly** what the job needs and nothing more.

## Why a company does this

RDS already takes automated snapshots, but those live inside RDS and vanish with a deleted instance. A logical `pg_dump` in S3 is a second, portable copy that can be restored anywhere. It's also the most common S3 + IAM task a junior engineer gets: "make server X write to bucket Y, safely".

The safety part is **least privilege**. If an attacker takes over a server, they get its role. A role that can delete backups helps them hold the company to ransom. A role that can only add backups doesn't.

## What gets built ([`terraform/s3.tf`](../terraform/s3.tf))

| Setting | Value | Why |
|---|---|---|
| Bucket name | `harbor-backups-<account-id>` | Bucket names are global across every AWS account |
| Block Public Access | All four on | The bucket can never be made public by mistake |
| Versioning | Enabled | Overwrites and deletes keep the old version |
| Default encryption | SSE-S3 (AES-256) | Encrypted at rest (S3 does this by default since 2023; set explicitly so it's visible) |
| Lifecycle | Delete backups after 30 days, old versions after 7 | Storage doesn't grow forever |
| Bucket policy | Deny any request not over HTTPS | Encryption in transit |
| `/harbor/backup/bucket` | SSM parameter | The script looks the name up; nothing hard-coded |
| `harbor-backup-s3` role policy | `s3:ListBucket` (only `db/` prefix), `s3:PutObject` + `s3:GetObject` on `db/*` | **No delete. No other buckets. No other prefixes** |

> ⚠️ `force_destroy = true` lets `terraform destroy` remove the bucket with backups still in it. That's for the lab only. Production buckets don't have it.

## Build it

```powershell
cd $HOME\aws-cloud-homelab\lab
Copy-Item ..\terraform\s3.tf .
terraform apply
$bucket = terraform output -raw backup_bucket
```

Cost: a few kilobytes of backups, effectively $0.

## Run a backup

```powershell
aws ssm start-session --target <instance-id>
```

```bash
sudo cat /usr/local/bin/harbor-backup      # read it first: parameters → pg_dump → gzip → aws s3 cp
sudo harbor-backup                          # Uploaded s3://harbor-backups-…/db/ip-10-20-…-2026….sql.gz
```

## Test the least-privilege boundary (still on the server, as root)

```bash
B=$(aws ssm get-parameter --region ap-southeast-1 --name /harbor/backup/bucket --query Parameter.Value --output text)

aws s3 ls "s3://$B/db/"                     # allowed: list the db/ prefix
aws s3 cp "s3://$B/db/$(aws s3 ls "s3://$B/db/" | tail -1 | awk '{print $4}')" /tmp/latest.sql.gz   # allowed: read a backup
gunzip -c /tmp/latest.sql.gz | grep -A4 "COPY public.clients"   # the 3 seeded clients are in the dump

aws s3 ls                                   # DENIED: listing all buckets isn't part of the job
aws s3 ls "s3://$B/"                        # DENIED: only the db/ prefix may be listed
aws s3 rm "s3://$B/db/$(aws s3 ls "s3://$B/db/" | tail -1 | awk '{print $4}')"   # DENIED: no deletes
echo test | aws s3 cp - "s3://$B/other/test.txt"   # DENIED: writes only under db/
```

Each denied command prints an `AccessDenied` error naming the action that's missing. Reading those messages is a daily cloud support skill.

### Ask IAM instead of guessing

From your laptop, the policy simulator answers "would this role be allowed to…?" without touching anything:

```powershell
$role = "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/harbor-app-role"
aws iam simulate-principal-policy --policy-source-arn $role `
  --action-names s3:PutObject s3:DeleteObject `
  --resource-arns "arn:aws:s3:::$bucket/db/x.sql.gz" `
  --query "EvaluationResults[].[EvalActionName,EvalDecision]" --output table
```

Expected: `s3:PutObject  allowed`, `s3:DeleteObject  implicitDeny`.

### Versioning in action (from the laptop)

```powershell
aws s3api list-object-versions --bucket $bucket --prefix db/ --query "Versions[].[Key,VersionId,IsLatest]" --output table
```

## Verify it worked

| Check | Expected |
|---|---|
| `sudo harbor-backup` | `Uploaded s3://…/db/….sql.gz` |
| Dump contents | `COPY public.clients` with 3 rows |
| `aws s3 rm` / `aws s3 ls` (all buckets) from the server | `AccessDenied` |
| Policy simulator | PutObject allowed, DeleteObject implicitDeny |
| **S3 console → bucket → Permissions** | Block all public access: **On** |

_My output: (paste the backup line and the AccessDenied errors here)_

## Common mistakes

| Mistake | Result |
|---|---|
| `"Action": "s3:*", "Resource": "*"` on the role | A compromised server can read, wipe or leak every bucket |
| `ListBucket` on `bucket/*` | Doesn't work: `ListBucket` applies to the **bucket** ARN, object actions to `bucket/*` |
| Turning off Block Public Access to "share a file" | Use a pre-signed URL instead |
| Backups with no lifecycle rule | Storage cost grows every day, forever |
| Never testing a restore | A backup you've never restored is a guess |

## Interview questions

- **"How does an EC2 instance write to S3 without keys?"** An IAM role attached through an instance profile. The SDK/CLI gets temporary credentials from the metadata service.
- **"What is least privilege? Give an example."** Only the actions and resources the job needs. Here: add and read backups under `db/` in one bucket, no delete, no other buckets.
- **"Identity policy vs bucket policy?"** An identity policy is attached to a user or role ("what can I do"). A bucket policy is attached to the bucket ("who can do what to me"). For access within one account, either can allow it, and an explicit deny in either wins.
- **"How do you stop an S3 bucket from ever being public?"** Block Public Access at the bucket and account level, no public bucket policy or ACLs, and alerting (e.g. the health report in doc 09).
- **"What does versioning protect against?"** Accidental overwrites and deletes: the previous versions stay. Add MFA delete or Object Lock for stronger protection.
- **"How do you read an AccessDenied error?"** It names the principal, the action and the resource. Check the identity policy, the resource policy, any explicit deny, and permission boundaries or SCPs.
- **"S3 storage classes?"** Standard, Intelligent-Tiering, Standard-IA, One Zone-IA, Glacier Instant/Flexible/Deep Archive. Lifecycle rules move or expire objects between them.

⬅️ [06 · RDS PostgreSQL](06-rds-postgresql.md) | ➡️ [08 · CloudWatch monitoring](08-cloudwatch-monitoring.md)
