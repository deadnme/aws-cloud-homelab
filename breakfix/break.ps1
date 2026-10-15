<#
.SYNOPSIS
  Injects one break-fix fault into the running lab (doc 12).

.DESCRIPTION
  SPOILER WARNING: reading this file tells you the answer. Run it, close it,
  and work the ticket from the symptoms in docs/12-break-fix-tickets.md.

  Needs: the full lab built (docs 03-08), $env:AWS_PROFILE set, AWS CLI v2.

.EXAMPLE
  .\breakfix\break.ps1 -Ticket 1
#>
param(
    [Parameter(Mandatory)][ValidateRange(1, 8)][int]$Ticket
)
$ErrorActionPreference = 'Stop'

function Invoke-Aws {
    $out = & aws @args
    if ($LASTEXITCODE -ne 0) { throw "aws $($args -join ' ') failed (exit $LASTEXITCODE)" }
    $out
}

$vpc = Invoke-Aws ec2 describe-vpcs --filters "Name=tag:Name,Values=harbor-vpc" --query 'Vpcs[0].VpcId' --output text
if ($vpc -eq 'None') { throw 'harbor-vpc not found. Build the lab first (docs 03-08).' }

function Get-SgId($name) {
    Invoke-Aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc" "Name=group-name,Values=$name" --query 'SecurityGroups[0].GroupId' --output text
}

function Get-IngressRuleId($sgId, $port) {
    Invoke-Aws ec2 describe-security-group-rules --filters "Name=group-id,Values=$sgId" --query "SecurityGroupRules[?IsEgress==``false`` && FromPort==``$port``].SecurityGroupRuleId | [0]" --output text
}

function Send-Shell($instanceId, $command) {
    # Write the parameters to a temp file: avoids PowerShell/JSON quoting problems.
    $file = New-TemporaryFile
    @{ commands = @($command) } | ConvertTo-Json | Set-Content -Path $file -Encoding ascii
    Invoke-Aws ssm send-command --instance-ids $instanceId --document-name AWS-RunShellScript --parameters "file://$file" --query 'Command.CommandId' --output text | Out-Null
    Remove-Item $file
}

switch ($Ticket) {
    1 {
        $sg = Get-SgId 'harbor-alb-sg'
        $rule = Get-IngressRuleId $sg 80
        Invoke-Aws ec2 revoke-security-group-ingress --group-id $sg --security-group-rule-ids $rule | Out-Null
    }
    2 {
        $rt = Invoke-Aws ec2 describe-route-tables --filters "Name=tag:Name,Values=harbor-public-rt" --query 'RouteTables[0].RouteTableId' --output text
        Invoke-Aws ec2 delete-route --route-table-id $rt --destination-cidr-block 0.0.0.0/0 | Out-Null
    }
    3 {
        $subnet = Invoke-Aws ec2 describe-subnets --filters "Name=tag:Name,Values=harbor-public-b" --query 'Subnets[0].SubnetId' --output text
        $assoc = Invoke-Aws ec2 describe-network-acls --filters "Name=association.subnet-id,Values=$subnet" --query "NetworkAcls[0].Associations[?SubnetId=='$subnet'].NetworkAclAssociationId | [0]" --output text
        $acl = Invoke-Aws ec2 create-network-acl --vpc-id $vpc --tag-specifications 'ResourceType=network-acl,Tags=[{Key=Name,Value=harbor-bf3},{Key=Project,Value=aws-cloud-homelab}]' --query 'NetworkAcl.NetworkAclId' --output text
        Invoke-Aws ec2 create-network-acl-entry --network-acl-id $acl --ingress --rule-number 50 --protocol tcp --port-range 'From=80,To=80' --cidr-block 0.0.0.0/0 --rule-action deny | Out-Null
        Invoke-Aws ec2 create-network-acl-entry --network-acl-id $acl --ingress --rule-number 100 --protocol -1 --cidr-block 0.0.0.0/0 --rule-action allow | Out-Null
        Invoke-Aws ec2 create-network-acl-entry --network-acl-id $acl --egress --rule-number 100 --protocol -1 --cidr-block 0.0.0.0/0 --rule-action allow | Out-Null
        Invoke-Aws ec2 replace-network-acl-association --association-id $assoc --network-acl-id $acl | Out-Null
    }
    4 {
        $tg = Invoke-Aws elbv2 describe-target-groups --names harbor-app-tg --query 'TargetGroups[0].TargetGroupArn' --output text
        Invoke-Aws elbv2 modify-target-group --target-group-arn $tg --health-check-path /healthz | Out-Null
    }
    5 {
        Invoke-Aws iam delete-role-policy --role-name harbor-app-role --policy-name harbor-backup-s3 | Out-Null
    }
    6 {
        $id = Invoke-Aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names harbor-app-asg --query 'AutoScalingGroups[0].Instances[0].InstanceId' --output text
        # Fill the root disk, leaving about 300 MB free.
        Send-Shell $id 'fallocate -l $(( $(df --output=avail -B1 / | tail -1) - 300*1024*1024 )) /var/tmp/.cache-0001'
    }
    7 {
        $sg = Get-SgId 'harbor-db-sg'
        $rule = Get-IngressRuleId $sg 5432
        Invoke-Aws ec2 revoke-security-group-ingress --group-id $sg --security-group-rule-ids $rule | Out-Null
    }
    8 {
        Invoke-Aws ssm put-parameter --name /harbor/db/password --type SecureString --overwrite --value 'NotTheRealPassword-2026' | Out-Null
    }
}

Write-Host "Ticket $Ticket is live. Open docs/12-break-fix-tickets.md and read ticket BF-$Ticket."
