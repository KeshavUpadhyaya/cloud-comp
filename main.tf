terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = "us-east-1" # Change to your desired region
}

resource "aws_key_pair" "flask_app_keypair" {
  key_name = "flask-app-keypair"
}

resource "aws_security_group" "flask_app_sg" {
  name_prefix = "flask-app-sg"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Add more rules if necessary
}

resource "aws_instance" "flask_app" {
  ami           = "ami-08a52ddb321b32a8c" # Amazon Linux 2 AMI, update to the appropriate AMI for your region
  instance_type = "t2.micro"
  key_name      = aws_key_pair.flask_app_keypair.key_name

  vpc_security_group_ids = [aws_security_group.flask_app_sg.id]

  tags = {
    Name = "FlaskAppInstance"
  }

  user_data = <<-EOF
              #!/bin/bash
              apk update
              apk add docker
              service docker start
              addgroup ec2-user docker

              # Fetch your Flask app code
              git clone https://github.com/KeshavUpadhyaya/cloud-comp.git /home/ec2-user/flask-app

              # Build and run the Flask app Docker container
              cd /home/ec2-user/flask-app
              docker build -t flask-app .
              docker run -d -p 80:80 flask-app
              EOF
}

output "instance_public_ip" {
  value = aws_instance.flask_app.public_ip
}

output "ssh_private_key" {
  value = aws_key_pair.flask_app_keypair.private_key
}
