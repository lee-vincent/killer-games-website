terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.51.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.2.3"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.4.3"
    }
  }
}
variable "aws_region" {
  type    = string
  default = "us-east-1"
}
variable "aws_zone" {
  type    = string
  default = "a"
}
variable "workload_prefix" {
  type    = string
  default = "kg"
}
provider "aws" {
  region  = var.aws_region
  profile = "vin"
}
locals {
  tag_prefix = "${var.workload_prefix}-${var.aws_region}${var.aws_zone}"
}
resource "aws_vpc" "killer_games_vpc" {
  cidr_block           = "172.16.0.0/24"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name = join("-", [local.tag_prefix, "vpc"])
  }
}
# Networks Address Block 172.16.0.0/24
# CIDR Subnets 172.16.0.0/26
#-----------------------------------------------------------------------------------#
# Subnet ID |  Subnet Address  |      Host Address Range        | Broadcast Address |
#     1     |   172.16.0.0     |   172.16.0.1 - 172.16.0.62     |    172.16.0.63    |
#     2     |   172.16.0.64    |   172.16.0.65 - 172.16.0.126   |    172.16.0.127   |
#     3     |   172.16.0.128   |   172.16.0.129 - 172.16.0.190  |    172.16.0.191   |
#     4     |   172.16.0.192   |   172.16.0.193 - 172.16.0.254  |    172.16.0.255   |
#-----------------------------------------------------------------------------------#
resource "aws_subnet" "web" {
  vpc_id            = aws_vpc.killer_games_vpc.id
  cidr_block        = "172.16.0.0/26"
  availability_zone = format("%s%s", var.aws_region, var.aws_zone)
  tags = {
    Name = join("-", [local.tag_prefix, "snet"])
  }
}
resource "aws_internet_gateway" "killer_games" {
  vpc_id = aws_vpc.killer_games_vpc.id
  tags = {
    Name = join("-", [local.tag_prefix, "igw"])
  }
}
resource "aws_route_table" "main" {
  vpc_id = aws_vpc.killer_games_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.killer_games.id
  }
  tags = {
    Name = join("-", [local.tag_prefix, "main-rtb"])
  }
}
resource "aws_main_route_table_association" "main" {
  vpc_id         = aws_vpc.killer_games_vpc.id
  route_table_id = aws_route_table.main.id
}
resource "aws_security_group" "web" {
  name        = "killer-games-web-sg"
  description = "enable ssh port 22 and http port 80"
  vpc_id      = aws_vpc.killer_games_vpc.id
  tags = {
    Name = join("-", [local.tag_prefix, "web-sg"])
  }
  ingress {
    description = "allow ssh ipv4 in"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "allow http ipv4 in"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    description = "allow all out"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]

  }
}
data "aws_ami" "amazon_linux2" {
  owners      = ["amazon"]
  most_recent = true
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-2.0*"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}
resource "aws_key_pair" "killer_games" {
  key_name   = "killer-games"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDFnVrYaaIybA6pSt1Q0Hm7uKqzCs41XvmQ4rFvc0id3qxJakV5bOhwOiS7OsS9TtOZ8FargGAnLzjzxV0GAHrwrKuE6SL14BjCGocgJhMiAnt8WtypnRjyI/GN5gxZqxyA1SE8sqEpd18+uExvYMaVmb/c9St48QmftHJp/gDbsZLU7Rj3/LakPT+Rpmn4a1LQXZcKy660QeP65TZQ83NXgm4PCR0NE62xavbkdEwYQmVL7OAC6Kl9KKXL3LR0rUMUq2FBOB2B/XSEs9dimuIkqfhVbMm2+dqknU644s70cTmrerknOfJWywwbF45eU8WLac5vDTM2R6gd/cfDv2rqLzZAg1MS2HvbGoySPiI6xzydlKTH+bOW9Bnr/nnx0QPSEg3Eh2ofL8gTJ6uiM7Hvyp/o3Td73KnTdE/MnvV9ic3gGw68T3M81RyhKg/H3uuF2n7rjAFMX/3HwckimnHihv/NT9Y3EtLHNi28N77f2ahcw72N+YwfNvAsuI9Vrqc="
  tags = {
    Name = join("-", [local.tag_prefix, "key"])
  }
}
resource "aws_instance" "killer_games" {
  key_name                    = aws_key_pair.killer_games.key_name
  ami                         = data.aws_ami.amazon_linux2.image_id
  vpc_security_group_ids      = [aws_security_group.web.id]
  subnet_id                   = aws_subnet.web.id
  instance_type               = "t3.micro"
  associate_public_ip_address = true
  tags = {
    Name = join("-", [local.tag_prefix, "instance"])
  }
  user_data = <<-EOF1
    #!/bin/bash -xe
    yum -y update
    yum install -y httpd wget git
    cd /tmp
    git clone https://github.com/acantril/aws-sa-associate-saac02.git 
    cp ./aws-sa-associate-saac02/11-Route53/r53_zones_and_failover/01_a4lwebsite/* /var/www/html
    usermod -a -G apache ec2-user   
    chown -R ec2-user:apache /var/www
    chmod 2775 /var/www
    find /var/www -type d -exec chmod 2775 {} \;
    find /var/www -type f -exec chmod 0664 {} \;
    systemctl enable httpd
    systemctl start httpd
  EOF1
}
output "public_ip" {
  value = aws_instance.killer_games.public_ip
}