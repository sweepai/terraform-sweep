# VPC and subnet configuration
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Security group for Sweep instances
resource "aws_security_group" "sweep_security_group" {
  name        = "sweep-security-group-${formatdate("YYYYMMDD-hhmmss", timestamp())}"
  description = "Enable HTTP, HTTPS, and SSH access for Sweep"
  vpc_id      = data.aws_vpc.default.id

  # HTTP access
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Backend API access
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Frontend port access
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH access for EC2 Instance Connect
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [
      "18.206.107.24/29",  # EC2 Instance Connect IPs for us-east-1
      "3.16.146.0/29",     # EC2 Instance Connect IPs for us-east-2
      "13.52.6.112/29",    # EC2 Instance Connect IPs for us-west-1
      "18.237.140.160/29"  # EC2 Instance Connect IPs for us-west-2
    ]
  }

  # Outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

output "vpc_id" {
  value = data.aws_vpc.default.id
}

output "subnet_ids" {
  value = data.aws_subnets.default.ids
}

output "security_group_id" {
  value = aws_security_group.sweep_security_group.id
}