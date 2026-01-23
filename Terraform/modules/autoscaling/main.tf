################################################
# Auto-Scaling Module - Policies and Alarms
################################################

# Scale Up Policy
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "${var.environment}-web-scale-up"
  scaling_adjustment     = var.scale_up_adjustment
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = var.asg_name
}

# Scale Down Policy
resource "aws_autoscaling_policy" "scale_down" {
  name                   = "${var.environment}-web-scale-down"
  scaling_adjustment     = var.scale_down_adjustment
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = var.asg_name
}

# CloudWatch Alarm - High CPU (Scale Up)
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.environment}-web-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = var.scale_up_cpu_threshold
  
  dimensions = {
    AutoScalingGroupName = var.asg_name
  }
  
  alarm_description = "Scale up when CPU exceeds ${var.scale_up_cpu_threshold}%"
  alarm_actions     = [aws_autoscaling_policy.scale_up.arn]
}

# CloudWatch Alarm - Low CPU (Scale Down)
resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "${var.environment}-web-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = var.scale_down_cpu_threshold
  
  dimensions = {
    AutoScalingGroupName = var.asg_name
  }
  
  alarm_description = "Scale down when CPU is below ${var.scale_down_cpu_threshold}%"
  alarm_actions     = [aws_autoscaling_policy.scale_down.arn]
}

# Target Tracking Scaling Policy (additional safety)
resource "aws_autoscaling_policy" "target_tracking" {
  name                   = "${var.environment}-web-target-tracking"
  autoscaling_group_name = var.asg_name
  policy_type            = "TargetTrackingScaling"
  
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    
    target_value = 65.0
  }
}

# Scheduled Scaling for Black Friday
resource "aws_autoscaling_schedule" "black_friday_scale_up" {
  scheduled_action_name  = "${var.environment}-black-friday-scale-up"
  min_size               = var.min_size * 3
  max_size               = var.max_size
  desired_capacity       = var.min_size * 3
  recurrence             = "0 6 * * 5"  # Every Friday at 6 AM
  autoscaling_group_name = var.asg_name
}

resource "aws_autoscaling_schedule" "black_friday_scale_down" {
  scheduled_action_name  = "${var.environment}-black-friday-scale-down"
  min_size               = var.min_size
  max_size               = var.max_size
  desired_capacity       = var.min_size
  recurrence             = "0 2 * * 6"  # Every Saturday at 2 AM
  autoscaling_group_name = var.asg_name
}
