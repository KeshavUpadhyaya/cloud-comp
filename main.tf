terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1" # Change to your desired region
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

# Elastic Load Balancer
resource "aws_lb" "flask_app_lb" {
  name               = "flask-app-lb"
  internal           = false
  load_balancer_type = "application"
  enable_deletion_protection = false

  enable_http2 = true

  enable_deletion_protection = false

  tags = {
    Name = "flask-app-lb"
  }
}

resource "aws_lb_listener" "flask_app_lb_listener" {
  load_balancer_arn = aws_lb.flask_app_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "fixed-response"
    fixed_response   = {
      content_type = "text/plain"
      status_code  = "200"
      content      = "OK"
    }
  }
}

# Auto Scaling Group
resource "aws_launch_configuration" "flask_app_launch_config" {
  name_prefix                 = "flask-app-launch-config"
  image_id                    = "ami-0261755bbcb8c4a84" # Replace with your desired AMI
  instance_type               = "t2.micro" # Replace with your desired instance type
  security_groups             = [aws_security_group.flask_app_sg.name]
  key_name                    = aws_key_pair.flask_app_keypair.key_name
  user_data                   = <<-EOF
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
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "flask_app_asg" {
  name                      = "flask-app-asg"
  max_size                  = 3 # Adjust as needed
  min_size                  = 1 # Adjust as needed
  desired_capacity          = 2 # Adjust as needed
  launch_configuration      = aws_launch_configuration.flask_app_launch_config.name
  health_check_type         = "EC2"
  health_check_grace_period = 300
  wait_for_capacity_timeout = "10m"

  target_group_arns = [aws_lb_target_group.flask_app_target_group.arn]
}

resource "aws_lb_target_group" "flask_app_target_group" {
  name     = "flask-app-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = "vpc-xxxxxx" # Replace with your VPC ID

  target_type = "instance"

  health_check {
    path                = "/health" # Adjust the path as needed
    port                = 80
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    interval            = 30
  }
}

resource "aws_lb_listener_rule" "flask_app_listener_rule" {
  listener_arn = aws_lb_listener.flask_app_lb_listener.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.flask_app_target_group.arn
  }

  condition {
    path_pattern {
      values = ["/"]
    }
  }
}

output "instance_public_ip" {
  value = aws_instance.flask_app.public_ip
}
