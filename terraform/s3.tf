# Doc 07 · S3 backups and a least-privilege instance role policy

resource "aws_s3_bucket" "backups" {
  # Bucket names are global across all AWS accounts, so add the account ID.
  bucket = "harbor-backups-${data.aws_caller_identity.current.account_id}"

  # Lab only: lets `terraform destroy` delete a bucket that still holds
  # backups (and old versions). Production buckets never set this.
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket                  = aws_s3_bucket.backups.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "expire-old-backups"
    status = "Enabled"
    filter {}

    expiration {
      days = 30
    }
    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

# Refuse any request that isn't over HTTPS.
resource "aws_s3_bucket_policy" "backups" {
  bucket = aws_s3_bucket.backups.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.backups.arn, "${aws_s3_bucket.backups.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.backups]
}

# The backup script finds the bucket name here instead of hard-coding it.
resource "aws_ssm_parameter" "backup_bucket" {
  name  = "/harbor/backup/bucket"
  type  = "String"
  value = aws_s3_bucket.backups.bucket
}

# Least privilege: the servers may list the bucket and write or read backups
# under db/. They may NOT delete anything, so a compromised server can't wipe
# the backups (and versioning keeps overwritten copies).
resource "aws_iam_role_policy" "app_backup" {
  name = "harbor-backup-s3"
  role = aws_iam_role.app.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Action    = "s3:ListBucket"
        Resource  = aws_s3_bucket.backups.arn
        Condition = { StringLike = { "s3:prefix" = ["db/*", "db/"] } }
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject"]
        Resource = "${aws_s3_bucket.backups.arn}/db/*"
      }
    ]
  })
}

output "backup_bucket" {
  value = aws_s3_bucket.backups.bucket
}
