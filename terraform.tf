provider "aws" {
}

variable "vpc_main_cidr" {
  type = string
}

variable "vpc_dmz_cidr" {
  type = string
}

variable "app_ami_sha" {
  type = string
}

# resource "aws_vpc" "main" {
#   cidr_block = var.vpc_main_cidr
# }

# output "main_vpc_id" {
#   value = aws_vpc.main.id
# }

# resource "aws_vpc" "dmz" {
#   cidr_block = var.vpc_dmz_cidr
# }

# output "dmz_vpc_id" {
#   value = aws_vpc.dmz.id
# }

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
  vpc_id      = module.vpc.vpc_id

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

module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 6.0"

  name = "app-alb"

  load_balancer_type = "application"

  vpc_id          = module.vpc.vpc_id
  subnets         = module.vpc.public_subnets
  security_groups = [aws_security_group.web_dmz.id]

  # access_logs = {
  #   bucket = "my-alb-logs"
  # }

  target_groups = [
    {
      name_prefix      = "app-"
      backend_protocol = "HTTP"
      backend_port     = 80
      target_type      = "instance"
    }
  ]

  http_tcp_listeners = [
    {
      port               = 80
      protocol           = "HTTP"
      target_group_index = 0
    }
  ]

  tags = {
    Environment = "dev"
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
    values = [var.app_ami_sha]
  }
}

resource "aws_instance" "web" {
  ami           = data.aws_ami.centos.id
  instance_type = "t2.micro"

  subnet_id                   = module.vpc.public_subnets.0
  associate_public_ip_address = "true"
  vpc_security_group_ids      = [aws_security_group.web_dmz.id]

  tags = {
    Environment    = "dev"
    Name           = "HelloWorld"
    Source_AMI     = data.aws_ami.centos.id
    Source_AMI_SHA = var.app_ami_sha
  }
}

output "aws_instance_web_public_ip" {
  value = aws_instance.web.public_ip
}

output "alb_dns_name" {
  value = module.alb.lb_dns_name
}


