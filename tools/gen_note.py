"""Rebuild the Obsidian 'Full Step-by-Step Guide' note from the aws-cloud-homelab repo.

Usage: python -I tools/gen_note.py <repo_dir> <out_file> [git-rev]
With git-rev, files are read from that commit (used to check the generator
against the existing note); without it, from the working tree.
"""
import re
import subprocess
import sys
from pathlib import Path

repo, out = Path(sys.argv[1]), Path(sys.argv[2])
rev = sys.argv[3] if len(sys.argv) > 3 else None


def read(rel):
    if rev:
        return subprocess.run(["git", "-C", str(repo), "show", f"{rev}:{rel}"],
                              capture_output=True, check=True).stdout.decode("utf-8")
    return (repo / rel).read_text(encoding="utf-8")


DOCS = ["00-what-is-aws", "01-account-setup-and-hardening", "02-workstation-tooling",
        "03-vpc-networking", "04-linux-on-ec2", "05-load-balancer-and-auto-scaling",
        "06-rds-postgresql", "07-s3-and-iam-roles", "08-cloudwatch-monitoring",
        "09-automation-cloud-health-report", "10-docker", "11-troubleshooting-and-lessons",
        "12-break-fix-tickets", "13-teardown-and-cost-report"]
CODE = [("terraform/providers.tf", "hcl"), ("terraform/variables.tf", "hcl"),
        ("terraform/outputs.tf", "hcl"), ("terraform/network.tf", "hcl"),
        ("terraform/compute.tf", "hcl"), ("terraform/alb.tf", "hcl"),
        ("terraform/rds.tf", "hcl"), ("terraform/s3.tf", "hcl"),
        ("terraform/monitoring.tf", "hcl"), ("scripts/user-data.sh.tftpl", "bash"),
        ("app/app.py", "python"), ("app/Dockerfile", "dockerfile"),
        ("scripts/cloud_health_report.py", "python"),
        ("scripts/test_cloud_health_report.py", "python"), (".gitignore", "gitignore"),
        (".github/workflows/terraform.yml", "yaml")]
BREAKFIX = [("breakfix/break.ps1", "powershell"), ("breakfix/restore.ps1", "powershell")]

LINK = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")


def links(line):
    # External links stay; relative and in-page links become their text.
    return LINK.sub(lambda m: m.group(0) if m.group(2).startswith("http") else m.group(1), line)


def transform(text):
    """Shift headings down one level, flatten local links, turn the nav footer
    and <details> hints into note syntax. Code blocks are left untouched."""
    out, fence = [], False
    for line in text.rstrip("\n").split("\n"):
        if line.startswith("```"):
            fence = not fence
            out.append(line)
            continue
        if fence:
            out.append(line)
            continue
        if line.startswith(("⬅️", "➡️")):
            out.append("---")
            continue
        m = re.fullmatch(r"<details><summary>(.*?)</summary>(.*)</details>", line)
        if m:
            out += [f"> [!tip]- {m.group(1)}", f"> {links(m.group(2))}"]
            continue
        if line.startswith("#"):
            line = "#" + line
        out.append(links(line))
    return "\n".join(out)


def callout(title, body, kind="example"):
    lines = [f"> [!{kind}]- {title}"]
    lines += [("> " + l) if l else ">" for l in body.strip("\n").split("\n")]
    return "\n".join(lines)


def split_spoilers(doc12):
    """Return doc 12 without its answers section, and the answers as callouts."""
    head, rest = doc12.split("## ⚠️ Spoilers: answers", 1)
    nav = rest[rest.index("⬅️"):]
    answers = re.findall(r"<details><summary>(.*?)</summary>\n(.*?)</details>", rest, re.S)
    return head + nav, [callout(t, b) for t, b in answers]


def main():
    readme = read("README.md")
    mermaid = readme[readme.index("```mermaid"):]
    mermaid = mermaid[:mermaid.index("\n\nWhy each part")]
    titles, sections, spoilers = [], [], []
    for name in DOCS:
        text = read(f"docs/{name}.md")
        if name.startswith("12-"):
            text, spoilers = split_spoilers(text)
        titles.append(text.split("\n", 1)[0][2:])
        sections.append(transform(text))

    dd = read("docs/design-decisions.md")
    a = dd.index("## Architecture\n")
    b = dd.index("## Index")
    dd = dd[:a] + "## Architecture\n\n" + mermaid + "\n\n" + dd[b:]
    dd = transform(dd)

    gloss = read("docs/glossary.md")
    gloss = gloss[gloss.index("| Term"):].rstrip("\n")

    code = ["## Appendix A - All code, in full", "",
            "Every file the docs refer to. In the lab you copy the Terraform files into `lab/` one per phase.", ""]
    for rel, lang in CODE:
        code += [f"### `{rel}`", "", f"```{lang}", read(rel).rstrip("\n"), "```", ""]

    bf = [callout(f"`{rel}`", f"```{lang}\n{read(rel).rstrip()}\n```") for rel, lang in BREAKFIX]

    toc = [f"- [[#{t}]]" for t in titles + ["Design decisions", "Appendix A - All code, in full",
                                              "Appendix B - Glossary", "Spoilers - break-fix answers"]]
    header = f"""---
tags:
  - aws-cloud-homelab
---

# AWS Cloud Homelab - Full Step-by-Step Guide

The whole **Harbor Point client portal** AWS lab in one note: every doc in order, then every file of code in full, then the break-fix answers. Repo: `C:\\Users\\seano\\aws-cloud-homelab` (also linked under `Projects/AWS Cloud Homelab`), GitHub: https://github.com/deadnme/aws-cloud-homelab

> [!note] How this guide is built
> {NOTE}

> [!warning] Cost and the Free Plan
> {WARN}

## Table of contents

""" + "\n".join(toc)

    body = [header] + sections + [dd, "\n".join(code).rstrip("\n"),
                                  "## Appendix B - Glossary\n" + gloss + "\n\n---",
                                  "## Spoilers - break-fix answers\n\n> [!warning] Spoilers\n"
                                  "> Open an answer only after you've solved the ticket or given up. "
                                  "The break scripts are here too, collapsed, because reading them gives the answer away.",
                                  ] + spoilers + bf
    out.write_text("\n\n".join(body) + "\n", encoding="utf-8", newline="\n")


NOTE = ("Generated from the repo's docs and code. Regenerated 2026-10-26 for the new AWS experience "
        "(Region `ap-southeast-2` Sydney, `aws login` through the project's managed role, current console "
        "names). Nothing in it has been run against a real AWS account yet: \"Expected\" lines are what "
        "should happen, not observed output. If the repo changes, the repo wins.")
WARN = ("Set up the budget alert (Phase 01) before building anything, run `terraform destroy` at the end of "
        "every session, and don't upgrade the plan or activate advanced AWS features (Organizations, IAM "
        "Identity Center): the upgrade can't be undone, and nothing in this lab needs them.")
if rev:  # reproduce the old header text so the check diff stays clean
    NOTE = ("Generated from the repo's docs and code on the day the lab was written. Updated 2026-10-16 with "
            "the design decisions and architecture diagram. Nothing in it has been run against a real AWS "
            "account yet: \"Expected\" lines are what should happen, not observed output. If the repo changes, "
            "the repo wins.")
    WARN = ("Set up the budget alert (Phase 01) before building anything, run `terraform destroy` at the end "
            "of every session, and never enable IAM Identity Center or AWS Organizations: that ends the Free "
            "Plan and its credits.")
main()
