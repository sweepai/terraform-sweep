variable "ami_id" {
  description = "AMI ID for the GPU instance"
  type        = string
}

variable "security_group_id" {
  description = "Security group ID for the GPU instance"
  type        = string
}

variable "continuous_deployment_script" {
  description = "Script for continuous deployment"
  type        = string
}

variable "instance_name" {
  description = "Name of the instance"
  type        = string
  default     = "sweep-gpu-instance"
}

variable "docker_image" {
  description = "Docker image to deploy"
  type        = string
}

variable "release_tag" {
  description = "Release tag to track for updates"
  type        = string
}

variable "container_name" {
  description = "Name for the container"
  type        = string
}

resource "aws_instance" "gpu_instance" {
  ami                    = var.ami_id
  instance_type          = "g6e.xlarge"
  vpc_security_group_ids = [var.security_group_id]

  root_block_device {
    volume_size = 200
    volume_type = "gp3"
  }

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

    # Install NVIDIA Container Toolkit
    distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
    curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
    curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list
    sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
    sudo DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::="--force-confnew" install nvidia-docker2
    sudo systemctl restart docker

    # Configure Docker default runtime to NVIDIA
    sudo tee /etc/docker/daemon.json <<DOCKERCONFIG
    {
        "default-runtime": "nvidia",
        "runtimes": {
            "nvidia": {
                "path": "nvidia-container-runtime",
                "runtimeArgs": []
            }
        },
        "exec-opts": ["native.cgroupdriver=systemd"]
    }
    DOCKERCONFIG

    # Restart Docker to apply changes
    sudo systemctl restart docker

    # Start and enable Docker
    sudo systemctl start docker
    sudo systemctl enable docker

    # Run the Sweep backend server container
    DOCKER_ARGS="--rm --runtime=nvidia --gpus all -d --privileged --env NVIDIA_VISIBLE_DEVICES=all --env NVIDIA_DRIVER_CAPABILITIES=compute,utility --env TOKENIZERS_PARALLELISM=false --ipc=host"

    # Create update script for pulling latest Docker image
    cat > /root/update-sweep.sh << 'SCRIPTFILE'
    ${var.continuous_deployment_script}
    SCRIPTFILE

    # Make the script executable
    sudo chmod +x /root/update-sweep.sh

    /root/update-sweep.sh "$DOCKER_ARGS" ${var.docker_image} 8000 ${var.release_tag} ${var.container_name} false

    # Run every 5 minutes to check for updates
    sudo sh -c "(crontab -l 2>/dev/null; echo \"*/5 * * * * /root/update-sweep.sh \\\"$DOCKER_ARGS\\\" ${var.docker_image} 8000 ${var.release_tag} ${var.container_name} false\") | crontab -"

    # Signal completion
    echo "GPU Inference deployment complete" | sudo tee /var/log/gpu-inference-deploy.log
  EOF

  tags = {
    Name = var.instance_name
  }
}

output "instance_id" {
  value = aws_instance.gpu_instance.id
}

output "public_dns" {
  value = aws_instance.gpu_instance.public_dns
}