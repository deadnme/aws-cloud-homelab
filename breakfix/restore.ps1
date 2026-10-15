<#
.SYNOPSIS
  Undoes a break-fix fault if you gave up, or cleans up after you fixed it (doc 12).

.DESCRIPTION
  Most faults are "drift": someone changed a resource that Terraform manages.
  `terraform apply` puts those back, and `terraform plan` first shows you what
  drifted (a good habit). Tickets 3 and 6 touch things Terraform doesn't manage,
  so this script undoes them directly.

.EXAMPLE
  .\breakfix\restore.ps1 -Ticket 3
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

switch ($Ticket) {
    3 {
        $vpc = Invoke-Aws ec2 describe-vpcs --filters "Name=tag:Name,Values=harbor-vpc" --query 'Vpcs[0].VpcId' --output text
        $subnet = Invoke-Aws ec2 describe-subnets --filters "Name=tag:Name,Values=harbor-public-b" --query 'Subnets[0].SubnetId' --output text
        $default = Invoke-Aws ec2 describe-network-acls --filters "Name=vpc-id,Values=$vpc" "Name=default,Values=true" --query 'NetworkAcls[0].NetworkAclId' --output text
        $assoc = Invoke-Aws ec2 describe-network-acls --filters "Name=association.subnet-id,Values=$subnet" --query "NetworkAcls[0].Associations[?SubnetId=='$subnet'].NetworkAclAssociationId | [0]" --output text
        Invoke-Aws ec2 replace-network-acl-association --association-id $assoc --network-acl-id $default | Out-Null
        $bad = Invoke-Aws ec2 describe-network-acls --filters "Name=tag:Name,Values=harbor-bf3" --query 'NetworkAcls[].NetworkAclId' --output text
        foreach ($acl in ($bad -split '\s+' | Where-Object { $_ })) {
            Invoke-Aws ec2 delete-network-acl --network-acl-id $acl | Out-Null
        }
        Write-Host 'Subnet harbor-public-b is back on the default network ACL, and harbor-bf3 is deleted.'
    }
    6 {
        $file = New-TemporaryFile
        @{ commands = @('rm -f /var/tmp/.cache-0001; df -h /') } | ConvertTo-Json | Set-Content -Path $file -Encoding ascii
        Invoke-Aws ssm send-command --targets 'Key=tag:aws:autoscaling:groupName,Values=harbor-app-asg' --document-name AWS-RunShellScript --parameters "file://$file" --query 'Command.CommandId' --output text | Out-Null
        Remove-Item $file
        Write-Host 'Removed the filler file on every app server. The disk alarm returns to OK within about 5 minutes.'
    }
    default {
        Write-Host 'This fault is drift on a Terraform-managed resource. From your Terraform folder run:'
        Write-Host '  terraform plan    # read what drifted'
        Write-Host '  terraform apply   # put it back'
    }
}
