variable "ami_id" {
  description = "AMI ID for the backend instance"
  type        = string
}

variable "security_group_id" {
  description = "Security group ID for the backend instance"
  type        = string
}

variable "instance_profile_name" {
  description = "Instance profile name for IAM role"
  type        = string
}

variable "continuous_deployment_script" {
  description = "Script for continuous deployment"
  type        = string
}

variable "gpu_instance_dns" {
  description = "Public DNS of the GPU instance"
  type        = string
}

variable "autocomplete_instance_dns" {
  description = "Public DNS of the autocomplete instance"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

resource "aws_ebs_volume" "backend_data" {
  availability_zone = aws_instance.backend_instance.availability_zone
  size              = 1000
  type              = "gp3"
  tags = {
    Name = "sweep-backend-data"
  }

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_volume_attachment" "backend_data_attachment" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.backend_data.id
  instance_id = aws_instance.backend_instance.id
}

resource "aws_instance" "backend_instance" {
  ami                    = var.ami_id
  instance_type          = "c5.4xlarge"
  vpc_security_group_ids = [var.security_group_id]
  iam_instance_profile   = var.instance_profile_name

  root_block_device {
    volume_size = 1000
    volume_type = "gp3"
  }

  user_data = <<-EOF
    #!/bin/bash
    sudo su -

    # Update package index
    sudo apt-get update

    # Install EC2 Instance Connect
    sudo apt-get install -y ec2-instance-connect

    # Install Docker dependencies
    sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common iptables

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
    sudo mkdir -p /mnt/caches

    # Mount the EBS volume
    if ! blkid /dev/sdf; then
      sudo mkfs -t ext4 /dev/sdf
    fi
    sudo mount /dev/sdf /mnt/caches

    # Add entry to fstab to ensure volume is mounted after reboot
    if ! grep -q "/dev/sdf" /etc/fstab; then
      echo "/dev/sdf /mnt/caches ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab
    fi

    # Set proper permissions
    sudo chown -R 1000:1000 /mnt/caches

    # Generate a persistent JWT secret key
    JWT_SECRET=$(openssl rand -hex 32)

    # Create .env file
    cat > /root/.env << 'ENVFILE'
    OPENAI_API_KEY=None
    IS_TRIAL=true
    AWS_REGION=us-east-1
    USE_JWT_AUTH=true
    ENVFILE

    # Add the JWT secret key to .env
    echo "JWT_SECRET_KEY=$JWT_SECRET" >> /root/.env
    echo "TRIAL_END_DATE=$(date -d "+28 days" +%Y-%m-%d)" >> /root/.env
    echo "FAST_APPLY_ENDPOINT=http://${var.gpu_instance_dns}/edit" >> /root/.env
    echo "NEXT_EDIT_AUTOCOMPLETE_ENDPOINT=http://${var.autocomplete_instance_dns}/generate" >> /root/.env
    echo "AWS_REGION=${var.aws_region}" >> /root/.env

    # Use the instance's own hostname instead of referencing itself
    BACKEND_HOST=$(curl -s http://169.254.169.254/latest/meta-data/public-hostname)
    echo "BACKEND_URL=http://$BACKEND_HOST:8080" >> /root/.env

    # Run the Sweep backend server container
    DOCKER_ARGS="-d --env-file /root/.env -v /mnt/caches:/mnt/caches --restart unless-stopped"

    # Create update script for pulling latest Docker image
    cat > /root/update-sweep.sh << 'SCRIPTFILE'
    ${var.continuous_deployment_script}
    SCRIPTFILE

    # Make the script executable
    sudo chmod +x /root/update-sweep.sh

    /root/update-sweep.sh "$DOCKER_ARGS" sweepai/sweep 8080 BACKEND_RELEASE sweep-backend true

    # Run every 5 minutes to check for updates
    sudo sh -c "(crontab -l 2>/dev/null; echo \"*/5 * * * * /root/update-sweep.sh \\\"$DOCKER_ARGS\\\" sweepai/sweep 8080 BACKEND_RELEASE sweep-backend true\") | crontab -"

    # Signal completion
    echo "Sweep Backend deployment complete" | sudo tee /var/log/sweep-backend-deploy.log
  EOF

  tags = {
    Name = "sweep-backend-instance"
  }
}

output "instance_id" {
  value = aws_instance.backend_instance.id
}

output "public_dns" {
  value = aws_instance.backend_instance.public_dns
}