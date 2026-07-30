resource "kubernetes_namespace" "octopus_workers" {
  metadata {
    name   = "octopus-workers"
    labels = { name = "octopus-workers" }
  }
}

# No IRSA on Vagrant — plain service account, no AWS annotations
resource "kubernetes_service_account" "octopus_worker" {
  metadata {
    name      = "octopus-worker"
    namespace = kubernetes_namespace.octopus_workers.metadata[0].name
  }
}

resource "kubernetes_namespace" "argocd" {
  count = var.install_argocd ? 1 : 0
  metadata {
    name   = var.argocd_namespace
    labels = { name = var.argocd_namespace }
  }
}

resource "kubernetes_namespace" "argo_rollouts" {
  count = var.install_argo_rollouts ? 1 : 0
  metadata {
    name   = "argo-rollouts"
    labels = { name = "argo-rollouts" }
  }
}
