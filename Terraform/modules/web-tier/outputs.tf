output "alb_dns_name" {
  description = "DNS name of the ALB"
  value       = aws_lb.web.dns_name
}

output "alb_arn" {
  description = "ARN of the ALB"
  value       = aws_lb.web.arn
}

output "autoscaling_group_name" {
  description = "Name of the auto scaling group"
  value       = aws_autoscaling_group.web.name
}

output "target_group_arn" {
  description = "ARN of the target group"
  value       = aws_lb_target_group.web.arn
}
