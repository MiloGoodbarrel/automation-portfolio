################################################
# Author: Luis Ramirez                         #
# Created: 10-15-2019                          #
# Updated: 11-20-2019                          #
################################################

# General Variables
variable "aws_region" {
  description = "AWS region for infrastructure deployment"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (production, staging, development)"
  type        = string
  default     = "production"
}

# Network Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (web tier)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
}

variable "database_subnet_cidrs" {
  description = "CIDR blocks for database subnets"
  type        = list(string)
  default     = ["10.0.21.0/24", "10.0.22.0/24", "10.0.23.0/24"]
}

# Web Tier Configuration
variable "web_instance_type" {
  description = "EC2 instance type for web servers"
  type        = string
  default     = "t3.medium"
}

variable "ssh_key_name" {
  description = "SSH key pair name for EC2 instances"
  type        = string
}

variable "web_asg_min_size" {
  description = "Minimum number of web servers"
  type        = number
  default     = 4
}

variable "web_asg_max_size" {
  description = "Maximum number of web servers (Black Friday capacity)"
  type        = number
  default     = 50
}

variable "web_asg_desired_capacity" {
  description = "Desired number of web servers at baseline"
  type        = number
  default     = 6
}

# Auto-Scaling Thresholds
variable "scale_up_cpu_threshold" {
  description = "CPU threshold to trigger scale up"
  type        = number
  default     = 70
}

variable "scale_down_cpu_threshold" {
  description = "CPU threshold to trigger scale down"
  type        = number
  default     = 30
}

variable "scale_up_adjustment" {
  description = "Number of instances to add during scale up"
  type        = number
  default     = 5
}

variable "scale_down_adjustment" {
  description = "Number of instances to remove during scale down"
  type        = number
  default     = -2
}

# Database Configuration
variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.r5.xlarge"
}

variable "db_allocated_storage" {
  description = "Allocated storage for RDS in GB"
  type        = number
  default     = 500
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "ecommerce"
}

variable "db_username" {
  description = "Database master username"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "Database master password"
  type        = string
  sensitive   = true
}

variable "db_multi_az" {
  description = "Enable Multi-AZ deployment for high availability"
  type        = bool
  default     = true
}

variable "db_backup_retention_period" {
  description = "Number of days to retain automated backups"
  type        = number
  default     = 7
}

# ElastiCache Configuration
variable "cache_node_type" {
  description = "ElastiCache node type for session management"
  type        = string
  default     = "cache.r5.large"
}

# SSL Configuration
variable "ssl_certificate_arn" {
  description = "ARN of SSL certificate for HTTPS"
  type        = string
}
