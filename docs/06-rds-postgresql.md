# 06 · RDS PostgreSQL

> **Goal:** give the portal a managed PostgreSQL database in the private subnets, reachable only from the app servers, with its password kept out of the code and read from Parameter Store at run time.

## Why a company does this

Running a database on your own server means patching it, backing it up, watching disk space and planning failover. **RDS** does the patching, automated backups, point-in-time restore and (with Multi-AZ) failover. The company still owns who can connect and where the credentials live (doc 00, shared responsibility).

## What gets built ([`terraform/rds.tf`](../terraform/rds.tf))

| Resource | Setting | Why |
|---|---|---|
| `harbor-db-sg` | Inbound 5432 **from `harbor-app-sg` only** | Security group chaining again: only the app servers can connect |
| `harbor-db-subnets` | The two **private** subnets | No route to the internet, no public IP |
| `harbor-db` | PostgreSQL 16, `db.t4g.micro`, 20 GB gp3, encrypted, single-AZ, 1-day backups | Small and cheap. Production: Multi-AZ, longer retention, deletion protection |
| `random_password` | 24 characters | No human ever types or sees it |
| `/harbor/db/host`, `name`, `user` | SSM `String` parameters | Connection settings the app reads |
| `/harbor/db/password` | SSM **`SecureString`** | Encrypted with the AWS-managed `aws/ssm` KMS key |

```
app server ──(instance role: ssm:GetParameters /harbor/*)──► Parameter Store
     │
     └── :5432 ──► harbor-db (private subnet, harbor-db-sg allows only harbor-app-sg)
```

> ⚠️ **The password is also in `terraform.tfstate`**, because Terraform generated it. That's one more reason state never goes into Git. Teams store state in an encrypted S3 bucket, and Terraform 1.11+ offers write-only arguments (`password_wo`) that keep secrets out of state.

## Before you build: see the "not configured" state

```powershell
cd $HOME\aws-cloud-homelab\lab
$url = terraform output -raw alb_url
curl.exe -s "$url/db"
```

Expected: `Database not configured yet (missing /harbor/db/host, …). Build doc 06 first.` The app is handling a missing dependency gracefully, and the home page and `/health` still work.

## Build it

```powershell
cd $HOME\aws-cloud-homelab\lab
Copy-Item ..\terraform\rds.tf .
terraform init     # rds.tf uses a second provider, hashicorp/random
terraform apply    # RDS takes about 5-10 minutes to create
```

**Cost:** `db.t4g.micro` plus 20 GB storage, roughly $0.03/hour in Sydney. Destroy at the end of every session: it's the slowest piece to recreate, but also one of the most expensive to forget.

> If `apply` fails with a free-tier error about the **backup retention period**, set `backup_retention_period = 0` in `lab\rds.tf` and apply again. Write down what happened in doc 11.

## Test it

```powershell
1..4 | ForEach-Object { curl.exe -s "$url/db" }
```

Expected: `Connected to PostgreSQL 16.x at harbor-db.….rds.amazonaws.com. The clients table has 3 rows.` from both servers. The first request creates and seeds the table.

### Look at the network path

```powershell
$db = terraform output -raw db_endpoint
Resolve-DnsName $db          # resolves to a 10.20.11.x or 10.20.12.x private address
Test-NetConnection $db -Port 5432   # fails from your laptop: private subnet, and the SG only trusts the app
```

### Connect with psql from an app server

```powershell
aws ssm start-session --target <instance-id>
```

```bash
sudo -i
p() { aws ssm get-parameter --region ap-southeast-2 --name "$1" --with-decryption --query Parameter.Value --output text; }
export PGHOST=$(p /harbor/db/host) PGDATABASE=$(p /harbor/db/name) PGUSER=$(p /harbor/db/user) PGPASSWORD=$(p /harbor/db/password)

psql -c "SELECT version();"
psql -c "SELECT * FROM clients;"
psql -c "SELECT ssl, version FROM pg_stat_ssl WHERE pid = pg_backend_pid();"   # the connection is encrypted
timeout 3 bash -c "</dev/tcp/$PGHOST/5432" && echo "port 5432 reachable"
```

This is how a support engineer tests "can server X reach database Y": DNS first, then the TCP port, then a real login.

## Verify it worked

| Check | Expected |
|---|---|
| `curl.exe -s "$url/db"` | `Connected to PostgreSQL 16…`, `3 rows` |
| `Resolve-DnsName` the endpoint | A private `10.20.1x.x` address |
| `Test-NetConnection … -Port 5432` from the laptop | Fails |
| `psql` from an app server | Works, and `pg_stat_ssl` shows `ssl = t` |
| **RDS console → harbor-db → Connectivity & security** | Publicly accessible: **No** |

_My output: (paste the `/db` responses and the psql output here)_

## Common mistakes

| Mistake | Result |
|---|---|
| `publicly_accessible = true` + SG open to the world | A database on the internet, scanned within minutes |
| DB SG allows the VPC CIDR instead of the app SG | Any server in the VPC can reach the database |
| Password in code, user data or Git | Leaks with the repo. Use Parameter Store or Secrets Manager |
| `pg_dump` client older than the server | `server version mismatch` (doc 07 installs the matching client) |
| Forgetting RDS when "pausing" the lab | A stopped RDS instance starts again by itself after 7 days |

## Interview questions

- **"RDS vs running PostgreSQL on EC2?"** RDS handles patching, backups, point-in-time restore and failover; you lose OS access and some engine settings. EC2 gives full control and full responsibility.
- **"What is Multi-AZ?"** A synchronous standby in another AZ. RDS fails over to it automatically (DNS name stays the same). It's for availability, not read scaling.
- **"Multi-AZ vs read replica?"** Multi-AZ: standby, no reads, automatic failover. Read replica: asynchronous copy that serves reads, can be promoted manually.
- **"Where do you keep database credentials?"** Secrets Manager (rotation built in, small monthly cost) or SSM Parameter Store SecureString (free tier). Never in code. Read them at run time with an IAM role.
- **"The app can't connect to the database. Walk me through it."** Does the endpoint resolve (DNS)? Is port 5432 reachable (`/dev/tcp`, security groups, NACLs, route tables)? Do the credentials work (`psql`)? Is the database itself up (RDS events, CPU, connections)?
- **"Why is the database in a private subnet?"** It never needs to start connections to the internet, and nothing on the internet should reach it.

⬅️ [05 · Load balancer and Auto Scaling](05-load-balancer-and-auto-scaling.md) | ➡️ [07 · S3 and IAM roles](07-s3-and-iam-roles.md)
