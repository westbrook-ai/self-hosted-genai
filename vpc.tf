# Builds an AWS VPC with public and private subnets to host Ollama infra
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "ollama-vpc"
  cidr = "10.10.0.0/16"

  azs             = ["${local.region}a", "${local.region}b", "${local.region}c"]
  private_subnets = ["10.10.1.0/24", "10.10.2.0/24", "10.10.3.0/24"]
  public_subnets  = ["10.10.101.0/24", "10.10.102.0/24", "10.10.103.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  # These tags enable the ALB ingress controller to use the public subnets to build an ALB

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# Security group to allow access to Open WebUI 
resource "aws_security_group" "open-webui-ingress-sg" {
  name   = "open-webui-ingress-sg"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

# Creates an ACM cert for use on the ALB (Ingress)
data "aws_route53_zone" "webui" {
  name         = local.domain_name
  private_zone = false
}

resource "aws_acm_certificate" "webui" {
  domain_name       = local.gateway_fqdn
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# This resource creates the required record for the ACM cert validation in your selected domain
resource "aws_route53_record" "webui-validation" {
  for_each = {
    for dvo in aws_acm_certificate.webui.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.webui.zone_id
}

# Creates an ACM cert for Gateway API testing
resource "aws_acm_certificate" "gateway" {
  domain_name       = local.gateway_fqdn
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "gateway-validation" {
  for_each = {
    for dvo in aws_acm_certificate.gateway.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.webui.zone_id
}

resource "aws_acm_certificate_validation" "gateway" {
  certificate_arn         = aws_acm_certificate.gateway.arn
  validation_record_fqdns = [for record in aws_route53_record.gateway-validation : record.fqdn]
}
