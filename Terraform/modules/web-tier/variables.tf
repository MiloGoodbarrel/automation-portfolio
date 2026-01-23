variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for ALB"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for web servers"
  type        = list(string)
}

variable "web_security_group_id" {
  description = "Security group ID for web tier"
  type        = string
}

variable "alb_security_group_id" {
  description = "Security group ID for ALB"
  type        = string
}

variable "ami_id" {
  description = "AMI ID for EC2 instances"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

variable "key_name" {
  description = "SSH key pair name"
  type        = string
}

variable "min_size" {
  description = "Minimum ASG size"
  type        = number
}

variable "max_size" {
  description = "Maximum ASG size"
  type        = number
}

variable "desired_capacity" {
  description = "Desired ASG capacity"
  type        = number
}

variable "health_check_path" {
  description = "Health check path"
  type        = string
  default     = "/health"
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "ssl_certificate_arn" {
  description = "ARN of SSL certificate"
  type        = string
}
