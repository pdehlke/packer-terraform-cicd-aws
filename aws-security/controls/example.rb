
content = inspec.profile.file("output.json")
params = JSON.parse(content)

vpc_id = params['main_vpc_id']['value']
alb = params['alb_arn']['value']

describe aws_vpc(vpc_id) do
  its('state') { should eq 'available' }
  # as we vary these based on the branch (master.tfvars & testing-defaults.tfvars)
  # we can't check the cidr without exporting the CIDR via output.json
  # its('cidr_block') { should eq '172.18.0.0/16' }
end

describe aws_alb(alb) do
  it { should exist }
end
# describe aws_albs do
#   its('load_balancer_arns') { should include 'arn:aws:elasticloadbalancing' }
# end
