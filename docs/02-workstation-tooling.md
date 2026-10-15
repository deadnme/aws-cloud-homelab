# 02 · Workstation tooling

> **Goal:** install the AWS CLI, Terraform and the Session Manager plugin on Windows. Sign the CLI in with short-lived credentials (no access keys), and prove Terraform can reach the account **without creating anything.**

## Why a company does this

Clicking through the console is fine for learning, but nobody can review or repeat clicks. Cloud teams work from the CLI and from code (Terraform), so every change can be reviewed, repeated and undone. The console stays useful for looking around and for troubleshooting.

## Key decisions

| Decision | My choice | Why |
|---|---|---|
| Shell | PowerShell (built-in Windows PowerShell 5.1 or PowerShell 7, both work) | Same shell as the AD lab. Linux commands come later, *inside* the EC2 instances |
| CLI sign-in | `aws login` (needs AWS CLI **2.32.0 or later**) | Temporary credentials from my console sign-in, which already passed MFA. They refresh for up to 12 hours, then I sign in again |
| Terraform credentials | A second profile that borrows the `aws login` session through `credential_process` | AWS documents this bridge for tools that don't read `aws login` sessions directly. Terraform reads `credential_process` profiles |
| Terraform state | Local file, ignored by Git | One person, one environment. A team would use an S3 backend with state locking |

## Steps

### 1. Install the tools

```powershell
winget install --id Amazon.AWSCLI -e
winget install --id Hashicorp.Terraform -e
winget install --id Amazon.SessionManagerPlugin -e
```

**Close and reopen the terminal**, so the new `PATH` is loaded. Then check:

```powershell
aws --version              # must be aws-cli/2.32.0 or later
terraform version
session-manager-plugin     # prints a "installed successfully" message
```

The Session Manager plugin is not needed until doc 04. It lets `aws ssm start-session` open a shell on an EC2 instance **without SSH and without port 22.**

### 2. Sign the CLI in

```powershell
aws login --profile harbor-login
```

- When asked for a Region, enter `ap-southeast-1`.
- A browser opens. Pick the `sean.admin` session (or sign in with MFA), then return to the terminal.

Test it:

```powershell
aws sts get-caller-identity --profile harbor-login
```

Expected: JSON with `UserId`, `Account` (your 12-digit account ID) and an `Arn` ending in `:user/sean.admin`. If the ARN ends in `:root`, you signed in as root. Run `aws logout --profile harbor-login` and sign in again as the admin user.

### 3. Add the profile Terraform will use

Open `%USERPROFILE%\.aws\config` (e.g. `notepad $HOME\.aws\config`). `aws login` already wrote a `[profile harbor-login]` block. Add this one below it:

```ini
[profile harbor]
credential_process = aws configure export-credentials --profile harbor-login --format process
region = ap-southeast-1
```

`harbor` holds no secrets. Whenever a tool needs credentials, it runs the CLI, which hands over the current short-lived ones from the `harbor-login` session.

```powershell
$env:AWS_PROFILE = 'harbor'
aws sts get-caller-identity        # same account and ARN as before
```

### 4. Make your working folder

The repo's [`terraform/`](../terraform/) folder holds the **finished** lab: every `.tf` file for docs 03-08. To learn it piece by piece, build up your own copy in a git-ignored `lab/` folder, one file per doc. Each doc tells you which file to copy, and you read the file before you apply it.

```powershell
cd $HOME\aws-cloud-homelab        # wherever you cloned the repo
mkdir lab
Copy-Item terraform\providers.tf, terraform\variables.tf, terraform\outputs.tf, terraform\.terraform.lock.hcl lab\
cd lab
```

`providers.tf` sets the Region and the default tags. `variables.tf` holds settings with defaults. `outputs.tf` only reads *who am I*. There are no resources yet. `.terraform.lock.hcl` pins the exact provider versions the repo was tested with.

> 💡 **In a hurry?** You can build everything at once from `terraform/` itself (it needs the `terraform.tfvars` file from doc 08). You learn far more by adding one file per doc.

### 5. Terraform smoke test (creates nothing)

```powershell
terraform init       # downloads the providers listed in the lock file
terraform plan       # should list only "Changes to Outputs", no resources
terraform apply      # type yes; expect "Resources: 0 added, 0 changed, 0 destroyed"
```

The outputs `account_id` and `caller_arn` must match `aws sts get-caller-identity`. That proves Terraform is using the right account and the right identity, and it costs nothing.

### 6. Confirm Git will not commit state

```powershell
cd ..
git status --short                          # nothing from lab\ may appear
git check-ignore -v lab/terraform.tfstate   # shows the .gitignore rule that hides it
```

_My output: (paste the real `terraform apply` output and the `git check-ignore` line here after running them. Mask the account ID if you prefer.)_

### 7. Allow local scripts to run (Windows PowerShell 5.1)

Windows PowerShell blocks `.ps1` files by default ("running scripts is disabled on this system"). Doc 12's break-fix scripts need this once:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

`RemoteSigned` runs your own local scripts but still blocks unsigned scripts downloaded from the internet. A `git clone` is fine. If you downloaded the repo as a ZIP instead, Windows marks every file as downloaded: run `Get-ChildItem -Recurse | Unblock-File` once in the repo folder.

## Every lab session from now on

```powershell
aws login --profile harbor-login      # once every 12 hours at most
$env:AWS_PROFILE = 'harbor'
cd $HOME\aws-cloud-homelab\lab
terraform apply                        # rebuilds everything you have copied in so far
# ... work ...
terraform destroy                      # ALWAYS, before closing the laptop
```

After doc 08: every rebuild creates a **new** SNS email subscription. Click the new "Subscription Confirmation" email each session, or alarms go nowhere.

## Common mistakes

| Mistake | Result |
|---|---|
| Old AWS CLI (before 2.32.0) | `aws: error: argument command: Invalid choice` for `login` |
| Not reopening the terminal after `winget` | `aws` / `terraform` is not recognized |
| `$env:AWS_PROFILE` not set in a new terminal | Terraform: `No valid credential sources found`. The CLI: `Unable to locate credentials` |
| Session older than 12 hours | An expired-session / sign-in-again error (Terraform reports it as a `credential_process` failure). Run `aws login --profile harbor-login` again |
| Signed in as root in the browser | `caller_arn` ends in `:root`. Everything works, which is exactly the problem |
| Committing `terraform.tfstate` | State holds resource details and secrets (doc 06's database password is in it). `.gitignore` blocks it, and `lab/` is ignored as a whole |

## Interview questions

- **"How does the AWS CLI authenticate?"** It signs every API request with credentials (SigV4). They come from a chain: environment variables, then the profile in `~/.aws/config` and `~/.aws/credentials`, then on EC2 the instance role. Mine come from `aws login`, so they are temporary and expire.
- **"Why not just create an access key?"** Access keys are long-lived and are the most common thing to leak (Git commits, screenshots, old laptops). Short-lived credentials limit the damage if they leak.
- **"What do `terraform init`, `plan`, `apply` and `destroy` do?"** `init` downloads providers. `plan` compares the code with the state and the real infrastructure and shows the difference. `apply` makes that change. `destroy` deletes everything in the state.
- **"What is Terraform state? Why not commit it to Git?"** It's Terraform's record of what it created, mapping code to real resource IDs. It can contain secrets, and two people working from two copies corrupt it. Teams keep it in a remote backend (S3 with locking) instead.
- **"What is `.terraform.lock.hcl` for?"** It pins exact provider versions and checksums, so everyone runs the same provider build.
- **"What is a Terraform provider?"** The plugin that turns Terraform resources into API calls for one platform, here `hashicorp/aws`.

⬅️ [01 · Account setup and hardening](01-account-setup-and-hardening.md) | ➡️ [03 · VPC networking](03-vpc-networking.md)
