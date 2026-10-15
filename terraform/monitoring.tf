# Doc 08 · CloudWatch monitoring and alerting
#
# CloudWatch agent (memory, disk, nginx logs) -> metrics and log groups
# Alarms -> SNS topic -> email

variable "alert_email" {
  description = "Where alarm emails go. Set it in terraform.tfvars (git-ignored)."
  type        = string
}

resource "aws_sns_topic" "alerts" {
  name = "harbor-alerts"
}

# AWS emails a confirmation link. Alarms reach you only after you click it.
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ---------------------------------------------------------------- CloudWatch agent
# Created here (not by the agent) so they get a retention period and are
# deleted by `terraform destroy`.
resource "aws_cloudwatch_log_group" "nginx" {
  for_each          = toset(["access", "error"])
  name              = "/harbor/nginx/${each.key}"
  retention_in_days = 7
}

# What the agent needs, and no more. This is the AWS-managed
# CloudWatchAgentServerPolicy minus logs:CreateLogGroup: Terraform owns the
# log groups, so a still-running agent can't recreate them during
# `terraform destroy` (which would break the next apply with
# ResourceAlreadyExistsException).
resource "aws_iam_role_policy" "app_cloudwatch" {
  name = "harbor-cloudwatch-agent"
  role = aws_iam_role.app.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData", "ec2:DescribeTags", "ec2:DescribeVolumes", "logs:DescribeLogGroups"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
        Resource = flatten([for g in aws_cloudwatch_log_group.nginx : [g.arn, "${g.arn}:*"]])
      },
      {
        Effect   = "Allow"
        Action   = "ssm:GetParameter"
        Resource = "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/AmazonCloudWatch-*"
      }
    ]
  })
}

# The agent reads its config from this parameter at boot (see user data).
# The agent policy above only allows parameters named AmazonCloudWatch-*
# (the same convention as AWS's managed CloudWatchAgentServerPolicy).
resource "aws_ssm_parameter" "cloudwatch_agent" {
  name = "AmazonCloudWatch-harbor"
  type = "String"
  value = jsonencode({
    agent = { metrics_collection_interval = 60, run_as_user = "root" }
    metrics = {
      namespace = "CWAgent"
      append_dimensions = {
        AutoScalingGroupName = "$${aws:AutoScalingGroupName}"
        InstanceId           = "$${aws:InstanceId}"
      }
      # Also publish one combined series per Auto Scaling group, so alarms
      # keep working when instances are replaced.
      aggregation_dimensions = [["AutoScalingGroupName"]]
      metrics_collected = {
        mem  = { measurement = ["mem_used_percent"] }
        disk = { measurement = ["used_percent"], resources = ["/"], drop_device = true }
      }
    }
    logs = {
      logs_collected = {
        files = {
          collect_list = [
            for k in ["access", "error"] : {
              file_path       = "/var/log/nginx/${k}.log"
              log_group_name  = "/harbor/nginx/${k}"
              log_stream_name = "{instance_id}"
            }
          ]
        }
      }
    }
  })
}

# ---------------------------------------------------------------- alarms
locals {
  alarm_actions = [aws_sns_topic.alerts.arn]
  alb_dims = {
    LoadBalancer = aws_lb.app.arn_suffix
    TargetGroup  = aws_lb_target_group.app.arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "harbor-cpu-high"
  alarm_description   = "Average CPU across the app servers above 70% for 10 minutes"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  dimensions          = { AutoScalingGroupName = aws_autoscaling_group.app.name }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 70
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_targets" {
  alarm_name          = "harbor-unhealthy-targets"
  alarm_description   = "At least one app server is failing the load balancer health check"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  dimensions          = local.alb_dims
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "harbor-alb-5xx"
  alarm_description   = "The load balancer itself returned 5 or more 5xx errors in 5 minutes (e.g. 503: no registered targets, 502: bad target response)"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_ELB_5XX_Count"
  dimensions          = { LoadBalancer = aws_lb.app.arn_suffix }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "disk_high" {
  alarm_name          = "harbor-disk-high"
  alarm_description   = "Root disk on an app server is more than 80% full"
  namespace           = "CWAgent"
  metric_name         = "disk_used_percent"
  dimensions          = { AutoScalingGroupName = aws_autoscaling_group.app.name }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# ---------------------------------------------------------------- dashboard
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "harbor-portal"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title = "Requests and 5xx errors", region = var.region, stat = "Sum", period = 60
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.app.arn_suffix],
            [".", "HTTPCode_ELB_5XX_Count", ".", "."],
            [".", "HTTPCode_Target_5XX_Count", ".", "."]
          ]
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          title = "Healthy / unhealthy app servers", region = var.region, stat = "Maximum", period = 60
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "LoadBalancer", aws_lb.app.arn_suffix, "TargetGroup", aws_lb_target_group.app.arn_suffix],
            [".", "UnHealthyHostCount", ".", ".", ".", "."]
          ]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6
        properties = {
          title = "App servers: CPU, memory, disk (%)", region = var.region, stat = "Maximum", period = 300
          metrics = [
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", aws_autoscaling_group.app.name],
            ["CWAgent", "mem_used_percent", "AutoScalingGroupName", aws_autoscaling_group.app.name],
            [".", "disk_used_percent", ".", "."]
          ]
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6
        properties = {
          title = "Database", region = var.region, stat = "Average", period = 300
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", aws_db_instance.main.identifier],
            [".", "DatabaseConnections", ".", "."]
          ]
        }
      }
    ]
  })
}

output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "dashboard_url" {
  value = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards/dashboard/${aws_cloudwatch_dashboard.main.dashboard_name}"
}
