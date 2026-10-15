"""Harbor Point cloud health report (doc 09).

Read-only checks of one AWS account and Region for the mistakes that cause most
real incidents and surprise bills: missing MFA, access keys, firewall rules
open to the internet, unencrypted disks, public S3 buckets, and paid resources
left running. The AWS counterpart of the AD health report in my AD lab.

Usage (PowerShell, with $env:AWS_PROFILE set as in doc 02):
    python scripts/cloud_health_report.py
    python scripts/cloud_health_report.py --markdown report.md

Exit code: 0 = no HIGH findings, 1 = at least one HIGH finding.
Needs: pip install boto3. Only Describe/List/Get calls; it changes nothing.
"""
import argparse
import datetime
import sys

WEB_PORTS = {80, 443}
SEVERITY_ORDER = {"HIGH": 0, "MEDIUM": 1, "LOW": 2, "INFO": 3}


def finding(severity, check, resource, detail):
    return {"severity": severity, "check": check, "resource": resource, "detail": detail}


# ---------------------------------------------------------------- pure checks
# These take plain dicts shaped like the AWS API responses, so they can be
# tested without an AWS account (see test_cloud_health_report.py).

def open_to_world(security_groups):
    """Inbound rules open to 0.0.0.0/0 or ::/0 on anything except HTTP/HTTPS."""
    out = []
    for sg in security_groups:
        for perm in sg.get("IpPermissions", []):
            world = any(r.get("CidrIp") == "0.0.0.0/0" for r in perm.get("IpRanges", [])) or \
                any(r.get("CidrIpv6") == "::/0" for r in perm.get("Ipv6Ranges", []))
            if not world:
                continue
            proto = perm.get("IpProtocol")
            lo, hi = perm.get("FromPort"), perm.get("ToPort")
            if proto != "-1" and lo == hi and lo in WEB_PORTS:
                continue  # a public web port on purpose (the load balancer)
            ports = "all traffic" if proto == "-1" else "%s %s-%s" % (proto, lo, hi)
            sev = "HIGH" if proto == "-1" or (lo is not None and lo <= 22 <= hi) or \
                (lo is not None and lo <= 3389 <= hi) else "MEDIUM"
            out.append(finding(sev, "Security group open to the internet",
                               "%s (%s)" % (sg["GroupId"], sg.get("GroupName", "")),
                               "Inbound %s from anywhere" % ports))
    return out


def unencrypted_volumes(volumes):
    return [finding("MEDIUM", "Unencrypted EBS volume", v["VolumeId"],
                    "Data at rest is not encrypted") for v in volumes if not v.get("Encrypted")]


def unattached_volumes(volumes):
    return [finding("LOW", "Unattached EBS volume (still billed)", v["VolumeId"],
                    "%s GiB, not attached to any instance" % v.get("Size"))
            for v in volumes if v.get("State") == "available"]


def unused_elastic_ips(addresses):
    return [finding("LOW", "Unused Elastic IP (still billed)", a.get("PublicIp", "?"),
                    "Not associated with anything") for a in addresses if not a.get("AssociationId")]


def missing_project_tag(instances, tag="Project"):
    out = []
    for i in instances:
        tags = {t["Key"]: t["Value"] for t in i.get("Tags", [])}
        if tag not in tags:
            out.append(finding("LOW", "Instance without a %s tag" % tag, i["InstanceId"],
                               "Can't be tracked in cost reports or cleanup checks"))
    return out


def render_text(findings):
    lines = []
    for f in sorted(findings, key=lambda f: SEVERITY_ORDER[f["severity"]]):
        lines.append("[%-6s] %s: %s | %s" % (f["severity"], f["check"], f["resource"], f["detail"]))
    return "\n".join(lines) if lines else "No findings."


def render_markdown(findings, account, region):
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    counts = {s: sum(f["severity"] == s for f in findings) for s in SEVERITY_ORDER}
    out = ["# Cloud health report", "",
           "Account `%s` · Region `%s` · %s" % (account, region, now), "",
           " · ".join("**%s** %d" % (s, n) for s, n in counts.items()), "",
           "| Severity | Check | Resource | Detail |", "|---|---|---|---|"]
    for f in sorted(findings, key=lambda f: SEVERITY_ORDER[f["severity"]]):
        out.append("| %s | %s | `%s` | %s |" % (f["severity"], f["check"], f["resource"], f["detail"]))
    if not findings:
        out.append("| - | No findings | - | - |")
    return "\n".join(out) + "\n"


# ---------------------------------------------------------------- AWS calls

def collect(session):
    from botocore.exceptions import ClientError

    findings = []
    ec2, iam, s3, rds = (session.client(n) for n in ("ec2", "iam", "s3", "rds"))

    def pages(client, op, key, **kw):
        for page in client.get_paginator(op).paginate(**kw):
            yield from page[key]

    # Identity
    summary = iam.get_account_summary()["SummaryMap"]
    if not summary.get("AccountMFAEnabled"):
        findings.append(finding("HIGH", "Root user has no MFA", "root", "Enable MFA on the root user"))
    if summary.get("AccountAccessKeysPresent"):
        findings.append(finding("HIGH", "Root user has access keys", "root", "Delete root access keys"))
    for user in pages(iam, "list_users", "Users"):
        name = user["UserName"]
        if not iam.list_mfa_devices(UserName=name)["MFADevices"]:
            findings.append(finding("HIGH", "IAM user without MFA", name, "Add an MFA device"))
        for key in iam.list_access_keys(UserName=name)["AccessKeyMetadata"]:
            if key["Status"] == "Active":
                age = (datetime.datetime.now(datetime.timezone.utc) - key["CreateDate"]).days
                findings.append(finding("MEDIUM", "Active long-lived access key",
                                        "%s / %s" % (name, key["AccessKeyId"]),
                                        "%d days old. Prefer aws login or roles" % age))

    # Network and compute
    findings += open_to_world(list(pages(ec2, "describe_security_groups", "SecurityGroups")))
    volumes = list(pages(ec2, "describe_volumes", "Volumes"))
    findings += unencrypted_volumes(volumes) + unattached_volumes(volumes)
    if not ec2.get_ebs_encryption_by_default()["EbsEncryptionByDefault"]:
        findings.append(finding("LOW", "EBS encryption by default is off", "account/region",
                                "New volumes are unencrypted unless asked. Turn on in EC2 settings"))
    findings += unused_elastic_ips(ec2.describe_addresses()["Addresses"])
    running = [i for r in pages(ec2, "describe_instances", "Reservations",
                                Filters=[{"Name": "instance-state-name", "Values": ["running"]}])
               for i in r["Instances"]]
    findings += missing_project_tag(running)

    # Storage and databases
    for bucket in s3.list_buckets().get("Buckets", []):
        name = bucket["Name"]
        try:
            cfg = s3.get_public_access_block(Bucket=name)["PublicAccessBlockConfiguration"]
            if not all(cfg.values()):
                findings.append(finding("HIGH", "S3 public access block not fully on", name, str(cfg)))
        except ClientError as e:
            code = e.response["Error"]["Code"]
            if code == "NoSuchPublicAccessBlockConfiguration":
                findings.append(finding("HIGH", "S3 bucket has no public access block", name,
                                        "Turn on Block Public Access"))
            else:
                findings.append(finding("INFO", "S3 bucket not checked", name, code))
    for db in pages(rds, "describe_db_instances", "DBInstances"):
        ident = db["DBInstanceIdentifier"]
        if db.get("PubliclyAccessible"):
            findings.append(finding("HIGH", "RDS instance is publicly accessible", ident, "Set publicly_accessible = false"))
        if not db.get("StorageEncrypted"):
            findings.append(finding("MEDIUM", "RDS storage not encrypted", ident, "Encrypt at creation"))

    # What is running right now (and costing money)
    elbv2 = session.client("elbv2")
    nat = [n for n in pages(ec2, "describe_nat_gateways", "NatGateways") if n["State"] == "available"]
    inventory = {
        "running EC2 instances": len(running),
        "load balancers": len(list(pages(elbv2, "describe_load_balancers", "LoadBalancers"))),
        "RDS instances": len(list(pages(rds, "describe_db_instances", "DBInstances"))),
        "NAT gateways": len(nat),
        "EBS volumes": len(volumes),
    }
    for what, n in inventory.items():
        if n:
            findings.append(finding("INFO", "Billable resources running", what, str(n)))
    return findings


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--markdown", metavar="FILE", help="also write a Markdown report to FILE")
    args = parser.parse_args(argv)

    import boto3  # imported here so the tests run without boto3 installed

    session = boto3.Session()
    account = session.client("sts").get_caller_identity()["Account"]
    findings = collect(session)
    print("Cloud health report for account %s, region %s\n" % (account, session.region_name))
    print(render_text(findings))
    if args.markdown:
        with open(args.markdown, "w", encoding="utf-8") as fh:
            fh.write(render_markdown(findings, account, session.region_name))
        print("\nMarkdown report written to %s" % args.markdown)
    return 1 if any(f["severity"] == "HIGH" for f in findings) else 0


if __name__ == "__main__":
    sys.exit(main())
