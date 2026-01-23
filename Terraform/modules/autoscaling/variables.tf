variable "asg_name" {
  description = "Auto Scaling Group name"
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

variable "scale_up_cpu_threshold" {
  description = "CPU threshold to trigger scale up"
  type        = number
}

variable "scale_down_cpu_threshold" {
  description = "CPU threshold to trigger scale down"
  type        = number
}

variable "scale_up_adjustment" {
  description = "Number of instances to add during scale up"
  type        = number
}

variable "scale_down_adjustment" {
  description = "Number of instances to remove during scale down"
  type        = number
}

variable "environment" {
  description = "Environment name"
  type        = string
}
