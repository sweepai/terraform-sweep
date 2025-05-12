output "backend_url" {
  description = "Backend API URL"
  value       = "http://${module.backend_instance.public_dns}:8080"
}

output "gpu_instance_url" {
  description = "GPU instance URL"
  value       = "http://${module.gpu_instance.public_dns}"
}

output "autocomplete_instance_url" {
  description = "Autocomplete instance URL"
  value       = "http://${module.autocomplete_instance.public_dns}"
}