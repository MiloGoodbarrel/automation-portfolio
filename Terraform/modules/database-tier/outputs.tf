output "db_endpoint" {
  description = "Database endpoint"
  value       = aws_db_instance.main.endpoint
  sensitive   = true
}

output "db_replica_endpoint" {
  description = "Read replica endpoint"
  value       = aws_db_instance.read_replica.endpoint
  sensitive   = true
}

output "db_instance_id" {
  description = "Database instance ID"
  value       = aws_db_instance.main.id
}
