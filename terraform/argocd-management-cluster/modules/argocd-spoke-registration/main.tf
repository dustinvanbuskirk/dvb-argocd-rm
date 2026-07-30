terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    local = {
      source = "hashicorp/local"
    }
    time = {
      source = "hashicorp/time"
    }
  }
}

# Each instance of this module gets its own independent kubernetes provider,
# scoped to whichever spoke cluster's kubeconfig/context was passed in. This
# is what lets the root module use for_each over one module block instead of
# needing a separate aliased provider per cluster.
provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kubeconfig_context
}

# Read the spoke cluster's own kubeconfig so the server URL and CA cert used
# in the ArgoCD registration secret always come from the same file the
# provider itself authenticates with -- no separate IP/CA vars to keep in sync.
data "local_file" "kubeconfig" {
  filename = var.kubeconfig_path
}

locals {
  kubeconfig_parsed = yamldecode(data.local_file.kubeconfig.content)

  matched_cluster = [
    for c in local.kubeconfig_parsed.clusters : c.cluster
    if c.name == var.cluster_name
  ][0]
}

resource "kubernetes_service_account_v1" "argocd_manager" {
  metadata {
    name      = "argocd-manager"
    namespace = var.service_account_namespace
  }
}

# ArgoCD needs broad rights on a cluster it manages. cluster-admin is the
# standard ArgoCD pattern; narrow this if you want per-namespace scoping.
resource "kubernetes_cluster_role_binding_v1" "argocd_manager" {
  metadata {
    name = "argocd-manager-role-binding"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.argocd_manager.metadata[0].name
    namespace = var.service_account_namespace
  }

  depends_on = [kubernetes_service_account_v1.argocd_manager]
}

# Kubernetes 1.24+ no longer auto-creates a token Secret for a ServiceAccount,
# so this creates one explicitly. The API server populates data.token
# asynchronously after creation.
resource "kubernetes_secret_v1" "argocd_manager_token" {
  metadata {
    name      = "argocd-manager-token"
    namespace = var.service_account_namespace
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account_v1.argocd_manager.metadata[0].name
    }
  }

  type = "kubernetes.io/service-account-token"

  depends_on = [kubernetes_cluster_role_binding_v1.argocd_manager]
}

# Same "create, then re-read" pattern used elsewhere in this project for the
# argocd-initial-admin-secret: give the token controller a moment before
# reading the populated secret back out.
resource "time_sleep" "wait_for_token" {
  depends_on      = [kubernetes_secret_v1.argocd_manager_token]
  create_duration = "10s"
}

data "kubernetes_secret_v1" "argocd_manager_token" {
  metadata {
    name      = kubernetes_secret_v1.argocd_manager_token.metadata[0].name
    namespace = var.service_account_namespace
  }

  depends_on = [time_sleep.wait_for_token]
}
