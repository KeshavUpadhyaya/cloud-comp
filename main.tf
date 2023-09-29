
#Viren test
#Find a way to create VPC ID and use it in code
#Figure out how our auto scaling is working
#Add a new feature
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1" 
}

resource "tls_private_key" "flask_app_keypair" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "flask_app_keypair" {
  key_name   = "flask-app-keypair"
  public_key = tls_private_key.flask_app_keypair.public_key_openssh
  provisioner "local-exec" {
    command = <<-EOT
      echo '${tls_private_key.flask_app_keypair.private_key_pem}' > aws_key.pem
      chmod 400 aws_key.pem
    EOT
  }
}

resource "aws_security_group" "flask_app_sg" {
  name_prefix = "flask-app-sg"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound rules
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # All protocols
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "flask_app" {
  ami           = "ami-0261755bbcb8c4a84" # Ubuntu 20.04 LTS image in us-east-1
  instance_type = "t2.micro"
  key_name      = aws_key_pair.flask_app_keypair.key_name

  vpc_security_group_ids = [aws_security_group.flask_app_sg.id]

  tags = {
    Name = "FlaskAppInstance"
  }

  user_data = <<-EOF
              #!/bin/bash
              apt update
              apt install -y docker.io
              service docker start
              usermod -aG docker ubuntu

              # Fetch your Flask app code
              git clone https://github.com/KeshavUpadhyaya/cloud-comp.git /home/ubuntu/flask-app

              # Build and run the Flask app Docker container
              cd /home/ubuntu/flask-app
              docker build -t flask-app .
              docker run -d -p 80:80 flask-app
              EOF
}

# Define an Auto Scaling Group with a default launch configuration.
resource "aws_autoscaling_group" "flask_app_asg" {
  name                      = "flask-app-asg"
  min_size                  = 2
  max_size                  = 5
  desired_capacity          = 2
  availability_zones        = ["us-east-1a", "us-east-1b"]
  launch_configuration      = aws_launch_configuration.flask_app.name
  target_group_arns         = [aws_lb_target_group.flask_app.arn]
  health_check_type         = "ELB"

  lifecycle { 
    ignore_changes = [desired_capacity, target_group_arns]
  }

}

# Define a launch configuration for the Auto Scaling Group.
resource "aws_launch_configuration" "flask_app" {
  name_prefix = "flask-app-"
  image_id    = "ami-0261755bbcb8c4a84"
  instance_type            = "t2.micro"
  key_name                 = aws_key_pair.flask_app_keypair.key_name
  associate_public_ip_address = true
  security_groups          = [aws_security_group.flask_app_sg.id]
  user_data = <<-EOF
              #!/bin/bash
              apt update
              apt install -y docker.io
              service docker start
              usermod -aG docker ubuntu

              # Fetch your Flask app code
              git clone https://github.com/KeshavUpadhyaya/cloud-comp.git /home/ubuntu/flask-app

              # Build and run the Flask app Docker container
              cd /home/ubuntu/flask-app
              docker build -t flask-app .
              docker run -d -p 80:80 flask-app
              EOF
}

# Define a load balancer.
resource "aws_lb" "flask_app_lb" {
  name               = "flask-app-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.flask_app_sg.id]
  enable_deletion_protection = false
  subnets            = ["subnet-01c0e4cc8c8806e8d", "subnet-0df47cb0d3a3bbcd9", "subnet-03b648c363c78399d", "subnet-025f3f34dd217af6c"] # Replace with your subnet IDs
}

# Define a target group for the load balancer.
resource "aws_lb_target_group" "flask_app" {
  name        = "flask-app-target-group"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = "vpc-0a75fdd8125eccd02" # Replace with your VPC ID
}

# Create a listener for the load balancer.
resource "aws_lb_listener" "flask_app" {
  load_balancer_arn = aws_lb.flask_app_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      status_code  = "200"
    }
  }
}

resource "aws_lb_listener_rule" "flask_app" {
  listener_arn = aws_lb_listener.flask_app.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.flask_app.arn
  }

  condition {
    path_pattern {
      values = ["/", "/api/v1/users", "/api/v1/users/*"]
    }
  }
}

output "load_balancer_public_ip" {
  value = aws_lb.flask_app_lb.dns_name
}


resource "aws_autoscaling_attachment" "flask_app" {
  autoscaling_group_name = aws_autoscaling_group.flask_app_asg.id
  lb_target_group_arn   = aws_lb_target_group.flask_app.id
}


resource "aws_autoscaling_policy" "scale_up" {
  name                   = "flask_app_scale_up"
  autoscaling_group_name = aws_autoscaling_group.flask_app_asg.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 120
}

resource "aws_cloudwatch_metric_alarm" "scale_up" {
  alarm_description   = "Monitors CPU utilization for Terramino ASG"
  alarm_actions       = [aws_autoscaling_policy.scale_up.arn]
  alarm_name          = "flask_app_alarm_scale_up"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  threshold           = "10"
  evaluation_periods  = "2"
  period              = "120"
  statistic           = "Average"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.flask_app_asg.name
  }
}


