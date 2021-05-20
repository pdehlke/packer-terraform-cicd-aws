provider "aws" {
}

variable "vpc_main_cidr" {
  type = "string"
}

variable "vpc_dmz_cidr" {
  type = "string"
}

# resource "aws_vpc" "main" {
#   cidr_block = "${var.vpc_main_cidr}"
# }

# output "main_vpc_id" {
#   value = "${aws_vpc.main.id}"
# }

# resource "aws_vpc" "dmz" {
#   cidr_block = "${var.vpc_dmz_cidr}"
# }

# output "dmz_vpc_id" {
#   value = "${aws_vpc.dmz.id}"
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
