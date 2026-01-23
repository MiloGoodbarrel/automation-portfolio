################################################
# Database Tier Module - RDS MySQL
################################################

# DB Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "${var.environment}-db-subnet-group"
  subnet_ids = var.database_subnet_ids
  
  tags = {
    Name = "${var.environment}-db-subnet-group"
  }
}

# DB Parameter Group
resource "aws_db_parameter_group" "main" {
  name   = "${var.environment}-mysql-params"
  family = "mysql8.0"
  
  parameter {
    name  = "max_connections"
    value = "500"
  }
  
  parameter {
    name  = "slow_query_log"
    value = "1"
  }
  
  parameter {
    name  = "long_query_time"
    value = "2"
  }
  
  tags = {
    Name = "${var.environment}-mysql-params"
  }
}

# RDS Instance
resource "aws_db_instance" "main" {
  identifier     = "${var.environment}-ecommerce-db"
  engine         = "mysql"
  engine_version = "8.0"
  
  instance_class    = var.db_instance_class
  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true
  
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password
  
  multi_az               = var.multi_az
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.database_security_group_id]
  parameter_group_name   = aws_db_parameter_group.main.name
  
  backup_retention_period = var.backup_retention_period
  backup_window           = "03:00-04:00"
  maintenance_window      = "mon:04:00-mon:05:00"
  
  enabled_cloudwatch_logs_exports = ["error", "general", "slowquery"]
  
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.environment}-ecommerce-db-final-snapshot"
  
  performance_insights_enabled = true
  
  tags = {
    Name = "${var.environment}-ecommerce-db"
  }
}

# Read Replica for reporting queries
resource "aws_db_instance" "read_replica" {
  identifier             = "${var.environment}-ecommerce-db-replica"
  replicate_source_db    = aws_db_instance.main.identifier
  instance_class         = var.db_instance_class
  publicly_accessible    = false
  skip_final_snapshot    = true
  
  performance_insights_enabled = true
  
  tags = {
    Name = "${var.environment}-ecommerce-db-replica"
    Role = "ReadReplica"
  }
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "database_cpu" {
  alarm_name          = "${var.environment}-database-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "Database CPU utilization is too high"
  
  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }
}

resource "aws_cloudwatch_metric_alarm" "database_connections" {
  alarm_name          = "${var.environment}-database-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "450"
  alarm_description   = "Database connection count is approaching limit"
  
  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }
}
