################################################
# Author: Luis Ramirez                         #
# Created: 10-15-2019                          #
# Updated: 11-20-2019                          #
################################################
# 
# Black Friday E-Commerce Infrastructure
# Multi-tier scalable architecture for high-traffic events
# 
# Components:
# - VPC with public/private subnets across 3 AZs
# - Auto-scaling web tier (ALB + EC2)
# - Database tier (RDS Multi-AZ)
# - ElastiCache for session management
# - CloudFront CDN for static assets
# - WAF for DDoS protection
# - CloudWatch monitoring and alarms
#

terraform {
  required_version = ">= 0.12"
  
  backend "s3" {
    bucket         = "company-terraform-state"
    key            = "ecommerce/production/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Environment = var.environment
      Project     = "BlackFriday-Ecommerce"
      ManagedBy   = "Terraform"
      Owner       = "Infrastructure-Team"
    }
  }
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# Networking Module
module "networking" {
  source = "./modules/networking"

  vpc_cidr             = var.vpc_cidr
  environment          = var.environment
  availability_zones   = data.aws_availability_zones.available.names
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  database_subnet_cidrs = var.database_subnet_cidrs
}

# Security Module
module "security" {
  source = "./modules/security"

  vpc_id      = module.networking.vpc_id
  environment = var.environment
}

# Web Tier Module
module "web_tier" {
  source = "./modules/web-tier"

  vpc_id                = module.networking.vpc_id
  public_subnet_ids     = module.networking.public_subnet_ids
  private_subnet_ids    = module.networking.private_subnet_ids
  web_security_group_id = module.security.web_security_group_id
  alb_security_group_id = module.security.alb_security_group_id
  
  ami_id               = data.aws_ami.amazon_linux_2.id
  instance_type        = var.web_instance_type
  key_name             = var.ssh_key_name
  
  min_size             = var.web_asg_min_size
  max_size             = var.web_asg_max_size
  desired_capacity     = var.web_asg_desired_capacity
  
  health_check_path    = "/health"
  environment          = var.environment
  
  ssl_certificate_arn  = var.ssl_certificate_arn
}

# Database Tier Module
module "database_tier" {
  source = "./modules/database-tier"

  vpc_id                   = module.networking.vpc_id
  database_subnet_ids      = module.networking.database_subnet_ids
  database_security_group_id = module.security.database_security_group_id
  
  db_instance_class        = var.db_instance_class
  db_allocated_storage     = var.db_allocated_storage
  db_name                  = var.db_name
  db_username              = var.db_username
  db_password              = var.db_password
  
  multi_az                 = var.db_multi_az
  backup_retention_period  = var.db_backup_retention_period
  
  environment              = var.environment
}

# Auto-Scaling Configuration
module "autoscaling" {
  source = "./modules/autoscaling"

  asg_name                = module.web_tier.autoscaling_group_name
  min_size                = var.web_asg_min_size
  max_size                = var.web_asg_max_size
  
  scale_up_cpu_threshold   = var.scale_up_cpu_threshold
  scale_down_cpu_threshold = var.scale_down_cpu_threshold
  
  scale_up_adjustment      = var.scale_up_adjustment
  scale_down_adjustment    = var.scale_down_adjustment
  
  environment              = var.environment
}

# ElastiCache for session management
resource "aws_elasticache_subnet_group" "session_cache" {
  name       = "${var.environment}-session-cache-subnet"
  subnet_ids = module.networking.private_subnet_ids
}

resource "aws_elasticache_cluster" "session_cache" {
  cluster_id           = "${var.environment}-session-cache"
  engine               = "redis"
  node_type            = var.cache_node_type
  num_cache_nodes      = 1
  parameter_group_name = "default.redis6.x"
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.session_cache.name
  security_group_ids   = [module.security.cache_security_group_id]
  
  tags = {
    Name = "${var.environment}-session-cache"
  }
}

# CloudFront Distribution for CDN
resource "aws_cloudfront_distribution" "cdn" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.environment} E-Commerce CDN"
  default_root_object = "index.html"
  price_class         = "PriceClass_100"  # US, Canada, Europe
  
  origin {
    domain_name = module.web_tier.alb_dns_name
    origin_id   = "ALB"
    
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }
  
  # S3 bucket for static assets
  origin {
    domain_name = aws_s3_bucket.static_assets.bucket_regional_domain_name
    origin_id   = "S3-Static-Assets"
    
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.oai.cloudfront_access_identity_path
    }
  }
  
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "ALB"
    
    forwarded_values {
      query_string = true
      headers      = ["Host", "CloudFront-Forwarded-Proto"]
      
      cookies {
        forward = "all"
      }
    }
    
    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
  }
  
  # Cache behavior for static assets
  ordered_cache_behavior {
    path_pattern     = "/static/*"
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-Static-Assets"
    
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    
    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
  }
  
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  
  viewer_certificate {
    cloudfront_default_certificate = true
  }
  
  web_acl_id = aws_wafv2_web_acl.ddos_protection.arn
  
  tags = {
    Name = "${var.environment}-ecommerce-cdn"
  }
}

resource "aws_cloudfront_origin_access_identity" "oai" {
  comment = "OAI for static assets bucket"
}

# S3 Bucket for static assets
resource "aws_s3_bucket" "static_assets" {
  bucket = "${var.environment}-ecommerce-static-assets"
  
  tags = {
    Name = "${var.environment}-static-assets"
  }
}

resource "aws_s3_bucket_policy" "static_assets" {
  bucket = aws_s3_bucket.static_assets.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = aws_cloudfront_origin_access_identity.oai.iam_arn
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.static_assets.arn}/*"
      }
    ]
  })
}

# WAF for DDoS protection
resource "aws_wafv2_web_acl" "ddos_protection" {
  name  = "${var.environment}-ddos-protection"
  scope = "CLOUDFRONT"
  
  default_action {
    allow {}
  }
  
  # Rate limiting rule
  rule {
    name     = "RateLimitRule"
    priority = 1
    
    action {
      block {}
    }
    
    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }
    
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitRule"
      sampled_requests_enabled   = true
    }
  }
  
  # AWS Managed Rules - Common Rule Set
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 2
    
    override_action {
      none {}
    }
    
    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }
    
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }
  
  # Known Bad Inputs
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 3
    
    override_action {
      none {}
    }
    
    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
      }
    }
    
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesKnownBadInputsRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }
  
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "DDosProtectionWebACL"
    sampled_requests_enabled   = true
  }
  
  tags = {
    Name = "${var.environment}-ddos-protection"
  }
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "ecommerce" {
  dashboard_name = "${var.environment}-ecommerce-dashboard"
  
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", { stat = "Average" }],
            [".", "RequestCount", { stat = "Sum" }],
            [".", "HTTPCode_Target_5XX_Count", { stat = "Sum" }]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Application Load Balancer Metrics"
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/RDS", "CPUUtilization", { stat = "Average" }],
            [".", "DatabaseConnections", { stat = "Sum" }],
            [".", "ReadLatency", { stat = "Average" }],
            [".", "WriteLatency", { stat = "Average" }]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "RDS Database Metrics"
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/EC2", "CPUUtilization", { stat = "Average" }],
            ["AWS/AutoScaling", "GroupDesiredCapacity", { stat = "Average" }],
            [".", "GroupInServiceInstances", { stat = "Average" }]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Auto Scaling Group Metrics"
        }
      }
    ]
  })
}
