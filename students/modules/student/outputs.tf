output "namespace" {
  description = "Kubernetes namespace"
  value       = kubernetes_namespace.student.metadata[0].name
}

output "hq_url" {
  description = "Lenses HQ URL"
  value       = "https://${local.hq_hostname}"
}

output "admin_username" {
  description = "Admin username"
  value       = "admin"
}

output "admin_password" {
  description = "Admin password"
  value       = local.student_password
  sensitive   = true
}
