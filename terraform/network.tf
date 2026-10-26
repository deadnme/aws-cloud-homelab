# Doc 03 · VPC networking
#
# 10.20.0.0/16 split into four /24 subnets across two Availability Zones:
#   public  10.20.1.0/24 (AZ a)   10.20.2.0/24 (AZ b)    route to the internet gateway
#   private 10.20.11.0/24 (AZ a)  10.20.12.0/24 (AZ b)   no route to the internet at all
#
# No NAT Gateway: it costs roughly $43/month in Sydney. Private subnets only
# hold the database, which never needs to reach the internet.

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

resource "aws_vpc" "main" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true # RDS and the ALB hand out DNS names, so this must be on

  tags = { Name = "harbor-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "harbor-igw" }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  availability_zone       = local.azs[count.index]
  cidr_block              = "10.20.${count.index + 1}.0/24"
  map_public_ip_on_launch = true # each public IPv4 costs about $0.005/hour

  tags = { Name = "harbor-public-${substr(local.azs[count.index], -1, 1)}" }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  availability_zone = local.azs[count.index]
  cidr_block        = "10.20.${count.index + 11}.0/24"

  tags = { Name = "harbor-private-${substr(local.azs[count.index], -1, 1)}" }
}

# A subnet is "public" only because its route table sends 0.0.0.0/0 to an internet gateway.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "harbor-public-rt" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private route table: only the built-in "local" route (10.20.0.0/16).
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "harbor-private-rt" }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}
