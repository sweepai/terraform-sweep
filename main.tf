provider "aws" {
  region = var.aws_region
}

module "networking" {
  source = "./modules/networking"
}

module "iam" {
  source = "./modules/iam"
}

module "scripts" {
  source = "./modules/scripts"
}

module "ami" {
  source     = "./modules/ami"
  aws_region = var.aws_region
}

module "gpu_instance" {
  source                     = "./modules/gpu_instance"
  ami_id                     = module.ami.gpu_ami
  security_group_id          = module.networking.security_group_id
  continuous_deployment_script = module.scripts.continuous_deployment_script
  docker_image               = "kevinlu1248/inference"
  release_tag                = "APPLY_RELEASE"
  container_name             = "sweep-apply"
  instance_name              = "sweep-gpu-instance"
}

module "autocomplete_instance" {
  source                     = "./modules/gpu_instance"
  ami_id                     = module.ami.gpu_ami
  security_group_id          = module.networking.security_group_id
  continuous_deployment_script = module.scripts.continuous_deployment_script
  docker_image               = "kevinlu1248/autocomplete"
  release_tag                = "AUTOCOMPLETE_RELEASE"
  container_name             = "sweep-autocomplete"
  instance_name              = "sweep-autocomplete-instance"
}

module "backend_instance" {
  source                     = "./modules/backend_instance"
  ami_id                     = module.ami.standard_ami
  security_group_id          = module.networking.security_group_id
  instance_profile_name      = module.iam.instance_profile_name
  continuous_deployment_script = module.scripts.continuous_deployment_script
  gpu_instance_dns           = module.gpu_instance.public_dns
  autocomplete_instance_dns  = module.autocomplete_instance.public_dns
  aws_region                 = var.aws_region
  depends_on                 = [module.gpu_instance, module.autocomplete_instance]
}

module "frontend_instance" {
  source                     = "./modules/frontend_instance"
  ami_id                     = module.ami.standard_ami
  security_group_id          = module.networking.security_group_id
  backend_instance_dns       = module.backend_instance.public_dns
  continuous_deployment_script = module.scripts.continuous_deployment_script
  depends_on                 = [module.backend_instance]
}

output "sweep_url" {
  description = "Visit this to setup Sweep. Your trial will expire in 28 days."
  value       = "http://${module.frontend_instance.public_dns}/plugin"
}