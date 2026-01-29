#!/bin/bash
################################################
# Author: Luis Ramirez
# Web Server Bootstrap Script
# Installs web application and dependencies
################################################

# Update system
yum update -y

# Install Apache and PHP
yum install -y httpd php php-mysqlnd php-redis

# Install CloudWatch agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
rpm -U ./amazon-cloudwatch-agent.rpm

# Configure application
cat > /var/www/html/health <<EOF
OK
EOF

# Start services
systemctl enable httpd
systemctl start httpd

# Configure CloudWatch logs
cat > /opt/aws/amazon-cloudwatch-agent/etc/config.json <<EOF
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/httpd/access_log",
            "log_group_name": "/aws/ec2/${environment}/httpd/access",
            "log_stream_name": "{instance_id}"
          },
          {
            "file_path": "/var/log/httpd/error_log",
            "log_group_name": "/aws/ec2/${environment}/httpd/error",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
EOF

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json \
  -s

# Application deployment would happen here
# In production: pull from S3, CodeDeploy, etc.
