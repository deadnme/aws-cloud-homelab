# Doc 06 · RDS PostgreSQL
#
# Single-AZ db.t4g.micro in the private subnets. Only the app security group
# can reach port 5432. The password is generated here, stored in Parameter
# Store as a SecureString, and read by the app at run time.

resource "aws_security_group" "db" {
  name        = "harbor-db-sg"
  description = "Database. PostgreSQL from the app instances only."
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "harbor-db-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  description                  = "PostgreSQL from the app instances"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.app.id
}

resource "aws_db_subnet_group" "main" {
  name       = "harbor-db-subnets"
  subnet_ids = aws_subnet.private[*].id
}

# RDS rejects / @ " and spaces in master passwords, so limit the specials.
resource "random_password" "db" {
  length           = 24
  special          = true
  override_special = "!#%^*-_=+"
}

resource "aws_db_instance" "main" {
  identifier        = "harbor-db"
  engine            = "postgres"
  engine_version    = "16" # major version only: RDS picks the current minor
  instance_class    = "db.t4g.micro"
  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = "harbor"
  username = "harboradmin"
  password = random_password.db.result # lab only: this ends up in terraform.tfstate

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  multi_az               = false # production: true (a standby in the other AZ)

  backup_retention_period = 1
  skip_final_snapshot     = true # lab only: production keeps a final snapshot
  deletion_protection     = false
  apply_immediately       = true
}

# Connection settings for the app and the backup script (/harbor/* is all the
# instance role may read).
resource "aws_ssm_parameter" "db" {
  for_each = {
    host = aws_db_instance.main.address
    name = aws_db_instance.main.db_name
    user = aws_db_instance.main.username
  }
  name  = "/harbor/db/${each.key}"
  type  = "String"
  value = each.value
}

resource "aws_ssm_parameter" "db_password" {
  name  = "/harbor/db/password"
  type  = "SecureString" # encrypted with the AWS-managed aws/ssm KMS key
  value = random_password.db.result
}

output "db_endpoint" {
  value = aws_db_instance.main.address
}
