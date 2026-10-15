# 01 · Account setup and hardening

> **Goal:** create the AWS account, lock down the root user, create a day-to-day admin user with MFA, and set up a budget alert **before a single resource exists.**

## Why a company does this

The first hour of a new AWS account decides how bad a mistake can get later. Any real company's onboarding checklist covers the same items: protect the root user, never share it, give people their own identities with MFA, and alert on spend. An account with no budget alert can run up a bill for weeks before anyone notices.

## Key decisions before clicking anything

| Decision | My choice | Why |
|---|---|---|
| Account plan | **Free Plan** | Credits instead of a bill. It stops when the credits run out unless I upgrade, so do **not** click "Upgrade". |
| Day-to-day identity | **IAM user** with MFA, in an `Admins` group | See the warning below about IAM Identity Center |
| CLI credentials | **`aws login`** (short-lived, from the console sign-in) | **No access keys.** Nothing long-lived on disk that can leak |
| Region | `ap-southeast-1` Singapore | Doc 00 |
| Budget | $5/month, alerts at $1 and $5 | Credits cover the lab, but I want an email the moment real usage starts |

> ⚠️ **Do not enable IAM Identity Center or AWS Organizations on this account.** In a company, people sign in through IAM Identity Center. But enabling it creates an AWS Organization, and AWS's own documentation warns that **creating an organization on a free-plan account upgrades it to the paid plan and the free credits expire immediately.** For this lab, an IAM user with MFA and no access keys is the safe choice. Source: [Enable IAM Identity Center](https://docs.aws.amazon.com/singlesignon/latest/userguide/enable-identity-center.html).

## Steps

### 1. Create the account

1. Go to <https://aws.amazon.com/> → **Create an AWS account**.
2. Use an email address only for this account. It becomes the **root user** login.
3. When asked to choose a plan, choose **Free plan**.
4. Enter a card for identity verification (AWS may place a small temporary hold) and verify your phone number.
5. Support plan: **Basic (free)**.

### 2. Lock down the root user

Sign in as root (the email address you just used).

1. Top-right account menu → **Security credentials**.
2. **Multi-factor authentication (MFA)** → **Assign MFA device** → a passkey or an authenticator app (Google Authenticator, Microsoft Authenticator, etc.).
3. On the same page, confirm **Access keys** shows none. Never create root access keys.
4. Store the root password and MFA recovery details in a password manager.

### 3. Let IAM users see billing

On many accounts only root can see Billing at first, even for an admin user. Still as root (if it already shows as active, move on):

1. Account menu → **Account**.
2. Scroll to **IAM user and role access to Billing information** → **Edit** → tick **Activate IAM Access** → **Update**.

If you skip this, the admin user gets *"You don't have permission"* on every Billing, Budgets and Cost Explorer page.

### 4. Create the admin user

Still as root, open **IAM**:

1. **User groups** → **Create group** → name `Admins` → attach the policy **AdministratorAccess** → Create.
2. **Users** → **Create user** → name e.g. `sean.admin` → tick **Provide user access to the AWS Management Console** → choose **I want to create an IAM user** → set a custom password → Next.
   > ⚠️ The wizard highlights **"Specify a user in Identity Center – Recommended"**. **Do not pick it.** It leads into enabling IAM Identity Center, which creates an Organization and ends the free plan (see the warning above).
3. **Add user to group** → `Admins` → Create.
4. **Do not create access keys** for this user.
5. On the IAM **Dashboard**, under **AWS Account**, note the **sign-in URL** (`https://<account-id>.signin.aws.amazon.com/console`). Optional: create an **account alias** so the URL is easier to remember.
6. Sign out of root.

### 5. Switch to the admin user and add MFA

1. Open the sign-in URL and sign in as `sean.admin`.
2. Top-right menu → **Security credentials** → **Assign MFA device**, as in step 2.
3. Sign out and back in to confirm MFA is asked for.
4. Set the console Region (top-right) to **Asia Pacific (Singapore) ap-southeast-1**.

From now on, **use only this user.** Root is for the few tasks that need it (closing the account, the billing-access setting above).

### 6. Create the budget alert

**Billing and Cost Management** → **Budgets** → **Create budget**:

1. **Customize (advanced)** → **Cost budget**.
2. Name `lab-monthly-5usd`, period **Monthly**, budget method **Fixed**, amount **$5.00**, scope **All AWS services**.
3. Under the advanced options, make sure **Credits** are **not** included in the costs. The goal is for the budget to track real usage *before* credits are applied. If credits are counted, the budget shows about $0 while the credits quietly drain.
4. Alert thresholds, each emailed to you:
   - **Actual** cost > **20%** of budget ($1)
   - **Actual** cost > **100%** ($5)
   - **Forecasted** cost > **100%**
5. Create.

> 💡 **Earn the extra credits.** On the free plan, Console Home shows onboarding activities that each add credits (up to $100 more). Setting up a cost budget is one of them. To be sure it counts, start the budget from that Console Home activity instead of opening Budgets directly, then follow the settings below.

If the option names differ from these steps, the goal stays the same: **a $5 monthly cost budget, credits excluded, emailing at $1 actual, $5 actual and $5 forecast.**

### 7. Turn on Cost Explorer

**Billing and Cost Management** → **Cost Explorer** → open it once. The first visit enables it, and data can take up to 24 hours to appear. Doc 13 uses it for the final cost report.

### 8. Look at CloudTrail event history

**CloudTrail** → **Event history**. No setup needed: AWS keeps 90 days of management events (who did what, from where) for free.

**Switch the console Region to US East (N. Virginia) `us-east-1` for this check.** Event history only shows the Region selected in the console. IAM and Budgets are *global* services, and their events are recorded in `us-east-1`. In Singapore you would see none of them and might think auditing is broken. Switch back to Singapore afterwards.

In `us-east-1` you should see the events from this page, such as `CreateUser`, `CreateGroup`, `AttachGroupPolicy` and `CreateBudget`. Click one and read the **User name** and **Source IP address**. This is the AWS version of the Security log on DC01.

## Verify it worked

| Check | Where | Expected |
|---|---|---|
| Root has MFA | IAM → Dashboard → Security recommendations | Root MFA shown as done |
| Root has no access keys | Root → Security credentials | "No access keys" |
| Admin user has MFA, no keys | IAM → Users → `sean.admin` → Security credentials | MFA device listed, no access keys |
| Admin can see billing | Signed in as `sean.admin` → Billing home | Page loads, credits balance shown |
| Budget exists | Budgets | `lab-monthly-5usd`, 3 alerts |
| Audit trail works | CloudTrail → Event history, Region **us-east-1** | `CreateUser` by root |

_My result: (add screenshots to `screenshots/01-*.png` after doing this)_

## Common mistakes

| Mistake | Result |
|---|---|
| Enabling IAM Identity Center "to do it properly" | Creates an AWS Organization, which moves a free-plan account to the paid plan and expires the credits |
| Using root every day | One phished password or session owns the whole account, including billing |
| Creating access keys "for the CLI" | Long-lived keys end up in a script or a Git commit. Bots scan GitHub for `AKIA…` keys within minutes |
| Skipping "IAM access to Billing" | The admin user can't open Budgets or Cost Explorer |
| Budget counts credits | Budget shows $0 spend while credits drain, so the alert never fires |
| Clicking "Upgrade to paid plan" | Charges go to the card after credits are used |

## Interview questions

- **"Why shouldn't you use the root user?"** It can do everything, including closing the account and changing billing, and IAM policies can't restrict it. Protect it with MFA, give it no access keys, and use it only for the few root-only tasks.
- **"What's the difference between an IAM user, group, role and policy?"** A user is a long-term identity for one person. A group is a set of users that share policies. A role is an identity that something *assumes* for temporary credentials (an EC2 instance, a Lambda function, a person from another account). A policy is the JSON document that allows or denies actions.
- **"How would you stop a surprise AWS bill?"** AWS Budgets with alerts on actual and forecasted cost, tags on every resource, Cost Explorer reviews, and tearing down what isn't needed. In a company, add Budget actions or SCPs for hard limits.
- **"What is CloudTrail?"** The audit log of API calls: who did what, when, and from which IP. Event history keeps 90 days of management events for free, per Region. Global services such as IAM log to `us-east-1`. A trail sends events to S3 for longer retention and can cover all Regions.
- **"Your lab uses AdministratorAccess. Is that least privilege?"** No. It's acceptable for a one-person lab account. In a company I'd use IAM Identity Center with permission sets scoped to the job (e.g. read-only for the help desk, PowerUser for developers) and keep admin access behind approval.
- **"Why no access keys?"** Long-term keys never expire on their own and are the most common way AWS accounts are compromised. `aws login` gives short-lived credentials from a console session that already passed MFA.

⬅️ [00 · What is AWS](00-what-is-aws.md) | ➡️ [02 · Workstation tooling](02-workstation-tooling.md)
