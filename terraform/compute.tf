# Doc 04 · Linux app servers (EC2 + Auto Scaling + Session Manager)
#
# Two Amazon Linux 2023 instances, one per AZ, in the public subnets.
# There is NO SSH key and NO port 22. Shell access goes through
# SSM Session Manager, which is authenticated by IAM and logged by CloudTrail.

# ---------------------------------------------------------------- security group
# The app accepts nothing from the internet. The load balancer gets an
# inbound rule in alb.tf (doc 05). Until then the app is reachable only from
# inside the instance (curl localhost) via Session Manager.
resource "aws_security_group" "app" {
  name        = "harbor-app-sg"
  description = "App instances. HTTP from the load balancer only. No SSH."
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "harbor-app-sg" }
}

resource "aws_vpc_security_group_egress_rule" "app_all" {
  security_group_id = aws_security_group.app.id
  description       = "dnf, pip, SSM, S3 and CloudWatch over the internet gateway"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ---------------------------------------------------------------- IAM role
# The instance role is how code on the server gets AWS permissions without
# any access keys: the instance metadata service hands out short-lived
# credentials for this role.
resource "aws_iam_role" "app" {
  name = "harbor-app-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Lets the SSM agent register the instance, so Session Manager works.
resource "aws_iam_role_policy_attachment" "app_ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# The app and the backup script read their settings (database host, password,
# bucket name) from Parameter Store under /harbor/. Nothing else.
resource "aws_iam_role_policy" "app_read_params" {
  name = "harbor-read-params"
  role = aws_iam_role.app.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameter", "ssm:GetParameters"]
      Resource = "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/harbor/*"
    }]
  })
}

resource "aws_iam_instance_profile" "app" {
  name = "harbor-app-profile"
  role = aws_iam_role.app.name
}

# ---------------------------------------------------------------- launch template
# AWS publishes the latest Amazon Linux 2023 AMI ID as a public SSM parameter,
# so there is no hard-coded AMI ID to go stale.
data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

locals {
  instance_tags = {
    Name      = "harbor-app"
    Project   = "aws-cloud-homelab"
    ManagedBy = "terraform"
  }
}

resource "aws_launch_template" "app" {
  name_prefix            = "harbor-app-"
  image_id               = data.aws_ssm_parameter.al2023_arm64.insecure_value
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.app.id]
  update_default_version = true

  iam_instance_profile {
    name = aws_iam_instance_profile.app.name
  }

  # First-boot script: installs nginx, the app, the backup script and the
  # CloudWatch agent. Read it: ../scripts/user-data.sh.tftpl
  # replace() strips Windows line endings, which would break "#!/bin/bash".
  user_data = base64encode(replace(templatefile("${path.module}/../scripts/user-data.sh.tftpl", {
    region     = var.region
    app_py     = file("${path.module}/../app/app.py")
    dockerfile = file("${path.module}/../app/Dockerfile")
  }), "\r", ""))

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # IMDSv2 only: blocks the classic SSRF credential theft
    # 2 hops so a Docker container on the instance can still reach the
    # metadata service (doc 10). 1 is stricter if you never run containers.
    http_put_response_hop_limit = 2
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  # default_tags do not reach instances launched by an Auto Scaling group,
  # so tag them here. Doc 13's leftover check depends on the Project tag.
  tag_specifications {
    resource_type = "instance"
    tags          = local.instance_tags
  }

  tag_specifications {
    resource_type = "volume"
    tags          = local.instance_tags
  }
}

# ---------------------------------------------------------------- auto scaling group
resource "aws_autoscaling_group" "app" {
  name                = "harbor-app-asg"
  min_size            = 2
  max_size            = 3
  desired_capacity    = 2
  vpc_zone_identifier = aws_subnet.public[*].id

  # "ELB" = also replace instances the load balancer marks unhealthy (doc 05).
  # The grace period gives first boot time to finish installing.
  health_check_type         = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.app.id
    version = aws_launch_template.app.latest_version
  }

  # A new launch template version (e.g. a changed user data script) replaces
  # instances one at a time, keeping at least half of them in service.
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  # The load balancer is attached in alb.tf with aws_autoscaling_attachment.
  lifecycle {
    ignore_changes = [load_balancers, target_group_arns]
  }
}

output "asg_name" {
  value = aws_autoscaling_group.app.name
}
