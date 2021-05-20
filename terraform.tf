data "aws_ami" "default" {
  most_recent = true
  filter {
    name   = "tag:SHA"
    values = ["current"]
  }
}
provider "aws" {
}

variable "vpc_main_cidr" {
  type = "string"
}

variable "vpc_dmz_cidr" {
  type = "string"
}

resource "aws_vpc" "main" {
  cidr_block = "${var.vpc_main_cidr}"
}

output "main_vpc_id" {
  value = "${aws_vpc.main.id}"
}

resource "aws_vpc" "dmz" {
  cidr_block = "${var.vpc_dmz_cidr}"
}

output "dmz_vpc_id" {
  value = "${aws_vpc.dmz.id}"
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "my-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true
  enable_vpn_gateway = true

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

resource "aws_security_group" "web_dmz" {
  name        = "Web DMZ"
  description = "Allow http and https inbound traffic"
  vpc_id      = "${module.vpc.vpc_id}"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # allow everything out
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_ami" "centos" {
  owners      = ["self"]
  most_recent = true

  filter {
    name   = "name"
    values = ["app *"]
  }

  filter {
    name   = "tag:SHA"
    values = ["${var.app_ami_sha}"]
  }
}

resource "aws_instance" "web" {
  ami           = "${data.aws_ami.centos.id}"
  instance_type = "t2.micro"

  subnet_id                   = "${aws_subnet.dmz.id}"
  associate_public_ip_address = "true"
  vpc_security_group_ids      = ["${aws_security_group.web_dmz.id}"]

  tags = {
    Name           = "HelloWorld"
    Source_AMI     = "${data.aws_ami.centos.id}"
    Source_AMI_SHA = "${var.app_ami_sha}"
  }
}

output "aws_instance_web_public_ip" {
  value = "${aws_instance.web.public_ip}"
}


