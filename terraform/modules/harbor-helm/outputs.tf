# Outputs for Harbor Helm Module

output "namespace" {
  description = "Kubernetes namespace where Harbor is deployed"
  value       = kubernetes_namespace.harbor.metadata[0].name
}

output "service_account_name" {
  description = "Name of the Kubernetes service account"
  value       = kubernetes_service_account.harbor.metadata[0].name
}

output "release_name" {
  description = "Name of the Helm release"
  value       = helm_release.harbor.name
}

output "release_status" {
  description = "Status of the Helm release"
  value       = helm_release.harbor.status
}

output "release_version" {
  description = "Version of the Helm release"
  value       = helm_release.harbor.version
}

output "chart_version" {
  description = "Version of the Harbor Helm chart"
  value       = helm_release.harbor.metadata[0].version
}
