# Doc 02 smoke test: proves Terraform can authenticate, without creating anything.
output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "caller_arn" {
  value = data.aws_caller_identity.current.arn
}

output "region" {
  value = var.region
}
