output "scale_up_policy_arn" {
  description = "ARN of scale up policy"
  value       = aws_autoscaling_policy.scale_up.arn
}

output "scale_down_policy_arn" {
  description = "ARN of scale down policy"
  value       = aws_autoscaling_policy.scale_down.arn
}
