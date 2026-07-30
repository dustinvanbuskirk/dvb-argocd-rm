output "token" {
  description = "Bearer token for the argocd-manager service account on this spoke cluster."
  value       = data.kubernetes_secret_v1.argocd_manager_token.data["token"]
  sensitive   = true
}

output "server" {
  description = "API server URL for this spoke cluster, read from its own kubeconfig."
  value       = local.matched_cluster.server
}

output "ca_certificate_data" {
  description = "Base64-encoded CA certificate for this spoke cluster, read from its own kubeconfig."
  value       = local.matched_cluster["certificate-authority-data"]
}
