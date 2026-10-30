# 01 · Account setup and hardening

> **Goal:** create the AWS account with the **new AWS experience**, confirm its Region, secure the sign-in, and set up a budget alert **before a single resource exists.**

## Why a company does this

The first hour of a new AWS account decides how bad a mistake can get later. Any real company's onboarding checklist covers the same items: protect the most powerful sign-in, give people their own identities with MFA, keep long-lived keys out of the picture, and alert on spend. An account with no budget alert can run up a bill for weeks before anyone notices.

## The new AWS experience

AWS now offers a simpler sign-up (**"Sign up for AWS (new)"**). You sign in with a login you already have (Google, GitHub, Apple or Amazon), and AWS creates an **AWS Builder ID** for you and a first **project**. A project is an AWS account plus its sharing settings. Account-level tasks (billing, plan, credits, team members, closing the account) live in **AWS Settings** at <https://settings.aws.com>. Your actual resources live in the normal **AWS Management Console**. AWS manages the guardrails: service control policies (SCPs) that block account-level changes and keep each project in **one Region**. Details: [Sign up for AWS (new)](https://docs.aws.amazon.com/accounts/latest/reference/sign-in-new.html), [SCPs and RCPs for projects](https://docs.aws.amazon.com/accounts/latest/reference/scps-and-rcps-for-projects.html).

> ⚠️ The new experience is still rolling out, and its console labels change. If a button below has a different name, the goal of the step stays the same.

## Key decisions before clicking anything

| Decision | My choice | Why |
|---|---|---|
| Sign-up | **Sign up for AWS (new)** with my own login | Simplest path, and the Free Tier credits come with it |
| Account plan | **Free Tier**, credits only | Credits instead of a bill. Do **not** upgrade: the upgrade can't be reversed, and from then on charges above the credits are billed |
| Region | `ap-southeast-2` **Asia Pacific (Sydney)** | Assigned by AWS from the country in the contact address. A project can only build in its own Region (design decisions D-01) |
| Day-to-day identity | The project's console session (`AccountFullAccessRole`), signed in through my login with MFA | AWS manages human access in a project. No IAM users |
| CLI credentials | **`aws login`** (short-lived, from the browser sign-in) | **No access keys.** Nothing long-lived on disk that can leak |
| Budget | $5/month, alerts at $1 and $5 | Credits cover the lab, but I want an email the moment real usage starts |

> ⚠️ **Do not activate "advanced AWS features", AWS Organizations or IAM Identity Center for this lab.** In a company, people sign in through IAM Identity Center. In a new-experience project, Organizations and Identity Center are not supported unless you activate advanced features, and activating them changes the managed guardrails this lab relies on. Nothing in this lab needs them. Source: [supported services](https://docs.aws.amazon.com/accounts/latest/reference/supported-services-sign-up-new.html).

## Steps

### 1. Create the account

1. Go to <https://aws.amazon.com/> → **Create an AWS account** → **Sign up for AWS (new)**.
2. Choose a login type (Google, GitHub, Apple or Amazon) and sign in with it.
3. Enter your name, verify your email with the code AWS sends, and set a strong password. AWS creates your **AWS Builder ID** and your first project.
4. Enter your contact details. The **country** in your contact address decides the project's Region (a Philippine address gets `ap-southeast-2`).
5. If AWS asks for payment information, it holds about USD $1 for 3-5 days to verify it. You are not charged unless you upgrade.

### 2. Confirm the Region and note the account ID

**AWS Settings** (<https://settings.aws.com>) → **View all projects** → your project → **Overview** → **Additional info**. Write down:

- **Region:** this guide assumes `ap-southeast-2` (Sydney). If yours is `us-east-2` or `eu-north-1`, change every `ap-southeast-2` to your Region: the `region` default in `terraform/variables.tf`, the `region` line of the `harbor` profile in doc 02, the `--region` values in docs 06 and 07, and `AWS_DEFAULT_REGION` in `app/Dockerfile` (doc 10).
- **Account ID (233402379125):** the 12-digit number. Doc 02 checks the CLI is signed in to this account.

Changing your contact address later does **not** move the project to another Region.

### 3. Secure the sign-in

In a new-experience project your AWS Builder ID owns the account instead of a root user email address, and nobody can sign in as the root user. Your **login** (and the AWS Builder ID behind it) is the most powerful credential you have, so protect that:

1. Turn on **2-step verification** on the login you signed up with (your Google, GitHub, Apple or Amazon account settings). Prefer a passkey or an authenticator app over SMS.
2. If AWS Settings or your AWS Builder ID profile offers **MFA**, register a passkey or an authenticator app there too. When MFA is enabled, AWS asks for it at every sign-in.
3. Store the password and recovery codes in a password manager.
4. **Do not create access keys** (IAM → Users → Create access key). The console warns against it for good reason.

### 4. Look at what AWS manages for you

Open the console (top-right shows your project) → **IAM** → **Roles**. You will see roles that AWS manages for the project, including `AccountFullAccessRole`: that is the identity your console session and your CLI use. Roles under the `/managed/` path are protected by the project SCP, so don't try to edit them.

Billing works differently from a classic account: payment details, the plan, credits and invoices live in **AWS Settings → Billing**, not in the console. Budgets and Cost Explorer stay in the console (**Billing and Cost Management**).

### 5. Create the budget alert

**Billing and Cost Management** → **Budgets** → **Create budget**:

1. **Customize (advanced)** → **Cost budget**.
2. Name `lab-monthly-5usd` (type it without backticks: the name can't be changed later), period **Monthly**, budget method **Fixed**, amount **$5.00**, scope **All AWS services**.
3. Under the advanced options, make sure **Credits** are **not** included in the costs. The goal is for the budget to track real usage *before* credits are applied. If credits are counted, the budget shows about $0 while the credits quietly drain.
4. Alert thresholds, each emailed to you:
   - **Actual** cost > **20%** of budget ($1)
   - **Actual** cost > **100%** ($5)
   - **Forecasted** cost > **100%**
5. Create.

#### If the email recipient stays "Inactive"

Since 30 September 2026, Budgets must verify each new email recipient before it sends alerts. In a new-experience project, **Send verification** fails with *"You do not have permission to send verification emails … notifications-contacts:CreateEmailContact …"*. The project's SCP denies every `notifications-contacts` action, so retrying or waiting won't help. Send the alerts through an SNS topic instead. SNS confirms the address with its own email, which the project allows.

1. **SNS** (console Region Sydney) → **Topics** → **Create topic** → **Standard**, name `budget-alerts`.
2. In **Access policy** → **Advanced**, add this statement to the `Statement` list (use your account ID):
   ```json
   {
     "Sid": "AllowBudgets",
     "Effect": "Allow",
     "Principal": { "Service": "budgets.amazonaws.com" },
     "Action": "SNS:Publish",
     "Resource": "arn:aws:sns:ap-southeast-2:<account-id>:budget-alerts",
     "Condition": { "StringEquals": { "aws:SourceAccount": "<account-id>" } }
   }
   ```
3. **Create subscription** → **Email** → your address. Open the "AWS Notification - Subscription Confirmation" email and click the link until the page says **Subscription confirmed!**
4. **Budgets** → your budget → **Edit** → add the topic ARN to each of the 3 alerts. The inactive email recipient can stay.
5. Test the email path: topic → **Publish message**. The email arrives within a minute. (Budgets' own permission to publish is only proven when a real alert fires.)

Keep this topic after `terraform destroy`, like the budget. It isn't part of the lab's Terraform, and it costs nothing at this volume.

If the Budgets list already shows a budget you didn't create, don't delete it until you know where it came from (check its name and its alert or action settings).

> 💡 **Earn the extra credits.** The Free Tier gives $100 at sign-up and up to $100 more for trying key services. Check the Console Home (or AWS Settings) for the list of activities. If setting up a budget is one of them, start the budget from there so it counts.

If the option names differ from these steps, the goal stays the same: **a $5 monthly cost budget, credits excluded, emailing at $1 actual, $5 actual and $5 forecast.**

### 6. Turn on Cost Explorer

**Billing and Cost Management** → **Cost Explorer** → open it once. The first visit enables it, and data can take up to 24 hours to appear. Use it to see what the lab actually cost, grouped by **Service**.

### 7. Look at CloudTrail event history

**CloudTrail** → **Event history**. No setup needed: AWS keeps 90 days of management events (who did what, from where) for free. A project's console has no Region selector: it always shows the project's Region (Sydney).

Event history is per Region. Regional services (EC2, VPC, RDS) log in Sydney. Global services such as IAM and Budgets log their events in **US East (N. Virginia) `us-east-1`**, so `CreateBudget` from step 5 is recorded there, out of the console's view. Read it with the CLI once doc 02 is done:

```powershell
aws cloudtrail lookup-events --region us-east-1 `
  --lookup-attributes AttributeKey=EventName,AttributeValue=CreateBudget `
  --query "Events[].[EventTime,Username,EventName]" --output table
```

In the console, click any event and read the **User name** and **Source IP address**. This is the AWS version of the Security log on DC01. Your own actions show up under the `AccountFullAccessRole` session.

## Verify it worked

| Check | Where | Expected |
|---|---|---|
| Region and account ID noted | AWS Settings → project → Overview → Additional info | `ap-southeast-2` (or yours), 12-digit ID |
| Login has 2-step verification | Your Google/GitHub/Apple/Amazon account security page | On, with a passkey or authenticator app |
| No access keys | IAM → Users | No users, or users with no access keys |
| Plan and credits visible | AWS Settings → Billing | Free Tier, credits balance shown |
| Budget exists | Billing and Cost Management → Budgets | `lab-monthly-5usd`, 3 alerts |
| Alerts can reach you | Email recipient **Active**, or SNS → `budget-alerts` → Subscriptions | Active recipient, or a **Confirmed** email subscription on the topic attached to all 3 alerts |
| Audit trail works | CloudTrail → Event history (Sydney), and the `lookup-events` command in step 7 after doc 02 | Your own events, and `CreateBudget` by your session |

**My output** (from my own account):

![AWS Settings: project overview, Region ap-southeast-2](../screenshots/01-aws-settings-project-region.png)

![CloudTrail event history in Sydney](../screenshots/01-cloudtrail-event-history.png)

![Budget details](../screenshots/01-budget-details.png)

## Common mistakes

| Mistake | Result |
|---|---|
| Activating advanced features or IAM Identity Center "to do it properly" | Changes the project's managed guardrails. Not needed for this lab |
| Clicking **Upgrade** | Can't be undone. Charges above the credits go to the card |
| Building in a Region other than the project's | `AccessDenied` from the project SCP. Every regional resource must be in `ap-southeast-2` |
| No 2-step verification on the social login | One phished password owns the whole project |
| Creating access keys "for the CLI" | Long-lived keys end up in a script or a Git commit. Bots scan GitHub for `AKIA…` keys within minutes |
| Budget counts credits | Budget shows $0 spend while credits drain, so the alert never fires |

## Interview questions

- **"Why shouldn't you use the root user?"** It can do everything, including closing the account and changing billing, and IAM policies can't restrict it. Protect it with MFA, give it no access keys, and use it only for the few root-only tasks. (In my new-experience project, my AWS Builder ID owns the account and nobody can sign in as root. I sign in through a managed role instead.)
- **"What's the difference between an IAM user, group, role and policy?"** A user is a long-term identity for one person. A group is a set of users that share policies. A role is an identity that something *assumes* for temporary credentials (an EC2 instance, a Lambda function, a person from another account). A policy is the JSON document that allows or denies actions.
- **"What is a service control policy?"** A guardrail set above the account (by AWS Organizations, or here by AWS for the project). It limits the maximum permissions: even a full-access role can't do what the SCP denies, such as building outside the project's Region.
- **"How would you stop a surprise AWS bill?"** AWS Budgets with alerts on actual and forecasted cost, tags on every resource, Cost Explorer reviews, and tearing down what isn't needed. For hard limits: spend limits (new-experience paid plan), Budget actions or SCPs.
- **"What is CloudTrail?"** The audit log of API calls: who did what, when, and from which IP. Event history keeps 90 days of management events for free, per Region. Global services such as IAM log to `us-east-1`. A trail sends events to S3 for longer retention and can cover all Regions.
- **"Your lab uses a full-access role. Is that least privilege?"** No. It's acceptable for a one-person lab. In a company I'd use IAM Identity Center with permission sets scoped to the job (e.g. read-only for the help desk, PowerUser for developers) and keep admin access behind approval.
- **"Why no access keys?"** Long-term keys never expire on their own and are the most common way AWS accounts are compromised. `aws login` gives short-lived credentials from a browser sign-in that already passed MFA.

⬅️ [00 · What is AWS](00-what-is-aws.md) | ➡️ [02 · Workstation tooling](02-workstation-tooling.md)
