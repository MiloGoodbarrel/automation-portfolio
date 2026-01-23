################################################
# Web Tier Module - ALB and Auto Scaling
################################################

# Application Load Balancer
resource "aws_lb" "web" {
  name               = "${var.environment}-web-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids
  
  enable_deletion_protection = true
  enable_http2              = true
  enable_cross_zone_load_balancing = true
  
  tags = {
    Name = "${var.environment}-web-alb"
  }
}

# Target Group
resource "aws_lb_target_group" "web" {
  name     = "${var.environment}-web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id
  
  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = var.health_check_path
    matcher             = "200"
  }
  
  deregistration_delay = 30
  
  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400
    enabled         = true
  }
  
  tags = {
    Name = "${var.environment}-web-tg"
  }
}

# HTTP Listener (redirect to HTTPS)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web.arn
  port              = "80"
  protocol          = "HTTP"
  
  default_action {
    type = "redirect"
    
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# HTTPS Listener
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.web.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = var.ssl_certificate_arn
  
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

# Launch Template
resource "aws_launch_template" "web" {
  name_prefix   = "${var.environment}-web-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name
  
  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [var.web_security_group_id]
    delete_on_termination       = true
  }
  
  iam_instance_profile {
    name = aws_iam_instance_profile.web.name
  }
  
  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    environment = var.environment
  }))
  
  monitoring {
    enabled = true
  }
  
  tag_specifications {
    resource_type = "instance"
    
    tags = {
      Name = "${var.environment}-web-server"
    }
  }
  
  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "web" {
  name                = "${var.environment}-web-asg"
  vpc_zone_identifier = var.private_subnet_ids
  target_group_arns   = [aws_lb_target_group.web.arn]
  health_check_type   = "ELB"
  health_check_grace_period = 300
  
  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity
  
  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }
  
  enabled_metrics = [
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupMaxSize",
    "GroupMinSize",
    "GroupPendingInstances",
    "GroupStandbyInstances",
    "GroupTerminatingInstances",
    "GroupTotalInstances"
  ]
  
  tag {
    key                 = "Name"
    value               = "${var.environment}-web-server"
    propagate_at_launch = true
  }
  
  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }
  
  lifecycle {
    create_before_destroy = true
  }
}

# IAM Role for EC2 Instances
resource "aws_iam_role" "web" {
  name = "${var.environment}-web-instance-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "web" {
  name = "${var.environment}-web-instance-profile"
  role = aws_iam_role.web.name
}

# Attach policies for CloudWatch, SSM, S3
resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.web.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.web.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Custom policy for S3 static assets
resource "aws_iam_role_policy" "s3_static" {
  name = "${var.environment}-web-s3-policy"
  role = aws_iam_role.web.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.environment}-ecommerce-static-assets",
          "arn:aws:s3:::${var.environment}-ecommerce-static-assets/*"
        ]
      }
    ]
  })
}
