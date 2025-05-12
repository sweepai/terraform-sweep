variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

locals {
  region_amis = {
    "us-east-1" = {
      "ami"    = "ami-00d321eaa8a8a4640"
      "gpuami" = "ami-049682606efa7fe65"
    }
    "us-east-2" = {
      "ami"    = "ami-05fb0b8c1424f266b"
      "gpuami" = "ami-05b39bee221db6e13"
    }
    "us-west-1" = {
      "ami"    = "ami-04669a22aad391419"
      "gpuami" = "ami-075cee103485d3d88"
    }
    "us-west-2" = {
      "ami"    = "ami-0530ca8899fac469f"
      "gpuami" = "ami-07ff6e2759e9465cd"
    }
    "eu-west-1" = {
      "ami"    = "ami-0694d931cee176e7d"
      "gpuami" = "ami-01a3905d0d0e52ec9"
    }
  }
}

output "standard_ami" {
  value = local.region_amis[var.aws_region]["ami"]
}

output "gpu_ami" {
  value = local.region_amis[var.aws_region]["gpuami"]
}