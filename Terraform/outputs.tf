################################################
# Author: Luis Ramirez                         #
# Created: 10-15-2019                          #
# Updated: 11-20-2019                          #
################################################

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.networking.vpc_id
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.web_tier.alb_dns_name
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.cdn.domain_name
}

output "database_endpoint" {
  description = "RDS database endpoint"
  value       = module.database_tier.db_endpoint
  sensitive   = true
}

output "redis_endpoint" {
  description = "ElastiCache Redis endpoint for session management"
  value       = aws_elasticache_cluster.session_cache.cache_nodes[0].address
  sensitive   = true
}

output "autoscaling_group_name" {
  description = "Name of the web tier auto-scaling group"
  value       = module.web_tier.autoscaling_group_name
}

output "static_assets_bucket" {
  description = "S3 bucket for static assets"
  value       = aws_s3_bucket.static_assets.bucket
}

output "waf_web_acl_id" {
  description = "WAF Web ACL ID for DDoS protection"
  value       = aws_wafv2_web_acl.ddos_protection.id
}

output "cloudwatch_dashboard_name" {
  description = "CloudWatch dashboard for monitoring"
  value       = aws_cloudwatch_dashboard.ecommerce.dashboard_name
}
