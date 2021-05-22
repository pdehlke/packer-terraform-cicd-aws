locals {
  name = "jenkins-testing"
  tags = [
    {
      key                 = "Source_AMI"
      value               = data.aws_ami.centos.id
      propagate_at_launch = true
    },
    {
      key                 = "Source_AMI_SHA"
      value               = var.app_ami_sha
      propagate_at_launch = true
    },
  ]
  tags_as_map = {
    Owner       = "pde"
    Environment = "dev-testing-jenkins"
    Terraform   = "true"
    Jenkins     = "true"
  }
}

provider "aws" {
  # Make it faster by skipping a few checks
  skip_get_ec2_platforms      = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  skip_credentials_validation = true
  skip_requesting_account_id  = true
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

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "my-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true
  enable_vpn_gateway = true

  tags = local.tags_as_map
}

resource "aws_security_group" "web_dmz" {
  name        = "Web DMZ"
  description = "Allow http and https inbound traffic"
  vpc_id      = module.vpc.vpc_id
  tags        = local.tags_as_map

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

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

module "alb_http_sg" {
  source  = "terraform-aws-modules/security-group/aws//modules/http-80"
  version = "~> 4.0"

  name        = "${local.name}-alb-http"
  vpc_id      = module.vpc.vpc_id
  description = "Security group for ${local.name}"

  ingress_cidr_blocks = ["0.0.0.0/0"]

  tags = local.tags_as_map
}

module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 6.0"

  name = local.name

  vpc_id          = module.vpc.vpc_id
  subnets         = module.vpc.public_subnets
  security_groups = [module.alb_http_sg.security_group_id]

  http_tcp_listeners = [
    {
      port               = 80
      protocol           = "HTTP"
      target_group_index = 0
    }
  ]

  target_groups = [
    {
      name             = local.name
      backend_protocol = "HTTP"
      backend_port     = 80
      target_type      = "instance"
    },
  ]

  tags = local.tags_as_map
}

module "asg_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 4.0"

  name        = local.name
  description = "ASG security group for ${local.name}"
  vpc_id      = module.vpc.vpc_id

  computed_ingress_with_source_security_group_id = [
    {
      rule                     = "http-80-tcp"
      source_security_group_id = module.alb_http_sg.security_group_id
    }
  ]
  number_of_computed_ingress_with_source_security_group_id = 1

  egress_rules = ["all-all"]

  tags = local.tags_as_map
}

module "asg" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "~> 4.0"

  # Autoscaling group
  name = "mixed-instance-${local.name}"

  vpc_zone_identifier = module.vpc.private_subnets
  min_size            = 0
  max_size            = 5
  desired_capacity    = 0

  image_id           = data.aws_ami.centos.id
  instance_type      = "t3.micro"
  capacity_rebalance = true
  target_group_arns  = module.alb.target_group_arns
  security_groups    = [module.asg_sg.security_group_id]

  initial_lifecycle_hooks = [
    {
      name                 = "ExampleStartupLifeCycleHook"
      default_result       = "CONTINUE"
      heartbeat_timeout    = 60
      lifecycle_transition = "autoscaling:EC2_INSTANCE_LAUNCHING"
      # This could be a rendered data resource
      notification_metadata = jsonencode({ "hello" = "world" })
    },
    {
      name                 = "ExampleTerminationLifeCycleHook"
      default_result       = "CONTINUE"
      heartbeat_timeout    = 180
      lifecycle_transition = "autoscaling:EC2_INSTANCE_TERMINATING"
      # This could be a rendered data resource
      notification_metadata = jsonencode({ "goodbye" = "world" })
    }
  ]

  instance_refresh = {
    strategy = "Rolling"
    preferences = {
      min_healthy_percentage = 50
    }
    triggers = ["tag"]
  }

  # Launch template
  create_lt              = true
  update_default_version = true

  # Mixed instances
  use_mixed_instances_policy = true
  mixed_instances_policy = {
    instances_distribution = {
      on_demand_base_capacity                  = 0
      on_demand_percentage_above_base_capacity = 10
      spot_allocation_strategy                 = "capacity-optimized"
    }

    override = [
      {
        instance_type     = "t3.nano"
        weighted_capacity = "2"
      },
      {
        instance_type     = "t3.medium"
        weighted_capacity = "1"
      },
    ]
  }

  tags        = local.tags
  tags_as_map = local.tags_as_map
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

output "alb_dns_name" {
  value = module.alb.lb_dns_name
}


