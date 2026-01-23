variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "database_subnet_ids" {
  description = "Database subnet IDs"
  type        = list(string)
}

variable "database_security_group_id" {
  description = "Security group ID for database"
  type        = string
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
}

variable "db_allocated_storage" {
  description = "Allocated storage in GB"
  type        = number
}

variable "db_name" {
  description = "Database name"
  type        = string
}

variable "db_username" {
  description = "Database username"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

variable "multi_az" {
  description = "Enable Multi-AZ"
  type        = bool
}

variable "backup_retention_period" {
  description = "Backup retention period in days"
  type        = number
}

variable "environment" {
  description = "Environment name"
  type        = string
}
