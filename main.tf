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

output "instance_public_ip" {
  value = aws_instance.flask_app.public_ip
}
