variable "ami_id" {
  description = "AMI ID for the frontend instance"
  type        = string
}

variable "security_group_id" {
  description = "Security group ID for the frontend instance"
  type        = string
}

variable "backend_instance_dns" {
  description = "Public DNS of the backend instance"
  type        = string
}

variable "continuous_deployment_script" {
  description = "Script for continuous deployment"
  type        = string
}

resource "aws_instance" "frontend_instance" {
  ami                    = var.ami_id
  instance_type          = "t3.medium"
  vpc_security_group_ids = [var.security_group_id]

  user_data = <<-EOF
    #!/bin/bash
    set -e

    # Update package index
    sudo apt-get update

    # Install EC2 Instance Connect
    sudo apt-get install -y ec2-instance-connect

    # Install Docker dependencies
    sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common

    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

    # Add Docker repository
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

    # Update package index again
    sudo apt-get update

    # Install Docker
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io

    # Start and enable Docker
    sudo systemctl start docker
    sudo systemctl enable docker

    # Create directory for caches
    sudo mkdir -p /root/caches

    # Create .env file
    touch /root/.env

    # Get the backend URL using the backend instance's public DNS
    BACKEND_URL="http://${var.backend_instance_dns}:8080"

    # Add the backend URL to the .env file
    echo "BACKEND_URL=$BACKEND_URL" >> /root/.env
    echo "NEXT_PUBLIC_BACKEND_URL=$BACKEND_URL" >> /root/.env
    echo "NEXT_PUBLIC_ENABLE_JWT_LOGIN=true" >> /root/.env

    # Run the Sweep backend server container
    DOCKER_ARGS="-d --env-file /root/.env"

    # Create update script for pulling latest Docker image
    cat > /root/update-sweep.sh << 'SCRIPTFILE'
    ${var.continuous_deployment_script}
    SCRIPTFILE

    # Make the script executable
    sudo chmod +x /root/update-sweep.sh

    /root/update-sweep.sh "$DOCKER_ARGS" sweepai/sweep-chat 3000 FRONTEND_RELEASE sweep-frontend false

    # Run every 5 minutes to check for updates
    sudo sh -c "(crontab -l 2>/dev/null; echo \"*/5 * * * * /root/update-sweep.sh \\\"$DOCKER_ARGS\\\" sweepai/sweep-chat 3000 FRONTEND_RELEASE sweep-frontend false\") | crontab -"

    # Signal completion
    echo "Sweep Frontend deployment complete" | sudo tee /var/log/sweep-frontend-deploy.log
  EOF

  tags = {
    Name = "sweep-frontend-instance"
  }
}

output "instance_id" {
  value = aws_instance.frontend_instance.id
}

output "public_dns" {
  value = aws_instance.frontend_instance.public_dns
}