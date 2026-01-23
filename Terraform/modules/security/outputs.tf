output "alb_security_group_id" {
  description = "Security group ID for ALB"
  value       = aws_security_group.alb.id
}

output "web_security_group_id" {
  description = "Security group ID for web tier"
  value       = aws_security_group.web.id
}

output "database_security_group_id" {
  description = "Security group ID for database"
  value       = aws_security_group.database.id
}

output "cache_security_group_id" {
  description = "Security group ID for ElastiCache"
  value       = aws_security_group.cache.id
}
