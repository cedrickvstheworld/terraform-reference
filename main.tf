terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

# variables
variable "access_key" {}
variable "secret_key" {}

# Configure the AWS Provider
provider "aws" {
  region = "ap-southeast-1"
  access_key = var.access_key
  secret_key = var.secret_key
}

# comment resource block to delete this sucker
# resource "aws_instance" "server01" {
#   ami = "ami-0750a20e9959e44ff"
#   instance_type = "t2.micro"

#   tags = {
#     Name = "server01"
#   }
# }

# 1. create VPC
resource "aws_vpc" "dev_vpc" {
  cidr_block = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "dev"
  }
}

# 2. create Internet Gateway
resource "aws_internet_gateway" "dev_gw" {
  vpc_id = aws_vpc.dev_vpc.id

  tags = {
    Name = "dev"
  }
}

# 3. create Custom Route Table
resource "aws_route_table" "dev_route_table" {
  vpc_id = aws_vpc.dev_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.dev_gw.id
  }

  route {
    ipv6_cidr_block = "::/0"
    # egress_only_gateway_id = aws_internet_gateway.dev_gw.id
    gateway_id = aws_internet_gateway.dev_gw.id
  }

  tags = {
    Name = "dev"
  }
}

# 4. create a Subnet
resource "aws_subnet" "dev_subnet1" {
  vpc_id = aws_vpc.dev_vpc.id
  cidr_block = "10.0.1.0/24"
  # availability_zone = "ap-southeast-1a"

  tags = {
    Name = "dev"
  }
}

# 5. associate subnet with Route Table
resource "aws_route_table_association" "dev_route_table_association" {
  subnet_id = aws_subnet.dev_subnet1.id
  route_table_id = aws_route_table.dev_route_table.id
}

# 6. create Security Groups
resource "aws_security_group" "dev_sg" {
  name = "dev_sg"
  description = "Allow TLS inbound traffic"
  vpc_id = aws_vpc.dev_vpc.id

  # http traffic
  ingress {
    description = "HTTPS"
    # ip range
    from_port = 443
    to_port = 443
    protocol = "tcp"
    # allowed IPs
    cidr_blocks = ["0.0.0.0/0"]
    # ipv6_cidr_blocks = [aws_vpc.main.ipv6_cidr_block]
  }

  # http traffic
  ingress {
    description = "HTTP"
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ssh
  ingress {
    description = "SSH"
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "dev_sg"
  }
}

# 7. create a network interface with an IP in the subnet that was created in step #4
resource "aws_network_interface" "dev_server" {
  subnet_id = aws_subnet.dev_subnet1.id
  private_ips = ["10.0.1.50"]
  security_groups = [aws_security_group.dev_sg.id]
}

# 8. assign an Elastic IP to the network interface created in step #7
resource "aws_eip" "dev_eip" {
  vpc = true
  network_interface = aws_network_interface.dev_server.id
  associate_with_private_ip = "10.0.1.50"
  depends_on = [
    aws_internet_gateway.dev_gw
  ]
}

# 9. create Ubuntu server and install nginx
resource "aws_instance" "server01" {
  ami = "ami-0750a20e9959e44ff"
  instance_type = "t2.micro"
  # availability_zone = "ap-southeast-1a"
  key_name = "dev-key"
  network_interface {
    device_index = 0
    network_interface_id = aws_network_interface.dev_server.id
  }

  tags = {
    Name = "server01"
  }

  # run commands on server instance up . sick bitch
  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt install nginx -y
              sudo systemctl start nginx
              EOF
}
