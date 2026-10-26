"""Self-check for the pure parts of cloud_health_report.py. No AWS account needed.

Run: python scripts/test_cloud_health_report.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cloud_health_report as r  # noqa: E402


def rule(proto, lo, hi, cidr="0.0.0.0/0"):
    return {"IpProtocol": proto, "FromPort": lo, "ToPort": hi, "IpRanges": [{"CidrIp": cidr}]}


sgs = [
    {"GroupId": "sg-alb", "GroupName": "harbor-alb-sg", "IpPermissions": [rule("tcp", 80, 80)]},
    {"GroupId": "sg-ssh", "GroupName": "bad-ssh", "IpPermissions": [rule("tcp", 22, 22)]},
    {"GroupId": "sg-all", "GroupName": "bad-all", "IpPermissions": [{"IpProtocol": "-1", "IpRanges": [{"CidrIp": "0.0.0.0/0"}]}]},
    {"GroupId": "sg-v6", "GroupName": "bad-v6", "IpPermissions": [
        {"IpProtocol": "tcp", "FromPort": 5432, "ToPort": 5432, "Ipv6Ranges": [{"CidrIpv6": "::/0"}]}]},
    {"GroupId": "sg-vpc", "GroupName": "internal", "IpPermissions": [rule("tcp", 22, 22, "10.20.0.0/16")]},
    {"GroupId": "sg-range", "GroupName": "web-range", "IpPermissions": [rule("tcp", 80, 443)]},
]
found = {f["resource"].split()[0]: f["severity"] for f in r.open_to_world(sgs)}
assert "sg-alb" not in found, found          # public port 80 on purpose: fine
assert found["sg-ssh"] == "HIGH", found       # SSH from anywhere
assert found["sg-all"] == "HIGH", found       # everything from anywhere
assert found["sg-v6"] == "MEDIUM", found      # IPv6 open counts too
assert "sg-vpc" not in found, found           # internal-only rule: fine
assert found["sg-range"] == "MEDIUM", found   # 80-443 range also opens 81-442

vols = [{"VolumeId": "vol-1", "Encrypted": True, "State": "in-use", "Size": 8},
        {"VolumeId": "vol-2", "Encrypted": False, "State": "available", "Size": 8}]
assert [f["resource"] for f in r.unencrypted_volumes(vols)] == ["vol-2"]
assert [f["resource"] for f in r.unattached_volumes(vols)] == ["vol-2"]

eips = [{"PublicIp": "1.2.3.4", "AssociationId": "eipassoc-1"}, {"PublicIp": "5.6.7.8"}]
assert [f["resource"] for f in r.unused_elastic_ips(eips)] == ["5.6.7.8"]

inst = [{"InstanceId": "i-tagged", "Tags": [{"Key": "Project", "Value": "aws-cloud-homelab"}]},
        {"InstanceId": "i-untagged"}]
assert [f["resource"] for f in r.missing_project_tag(inst)] == ["i-untagged"]

md = r.render_markdown(r.open_to_world(sgs), "123456789012", "ap-southeast-2")
assert md.startswith("# Cloud health report") and "**HIGH** 2" in md, md
assert r.render_text([]) == "No findings."
assert "| - | No findings |" in r.render_markdown([], "1", "r")

print("all checks passed")
