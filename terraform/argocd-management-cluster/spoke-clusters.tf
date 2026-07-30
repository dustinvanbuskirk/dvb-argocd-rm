# Registers each non-management cluster with the ArgoCD instance installed
# by helm_release.argocd (see argocd.tf). Add this file plus the
# modules/argocd-spoke-registration/ directory to your existing Terraform
# root, and populate var.spoke_clusters (see terraform.tfvars.example).
#
# NOTE ON STRUCTURE: each spoke cluster needs its own distinct kubernetes
# provider (different kubeconfig/context), configured inside the
# argocd-spoke-registration module. Terraform disallows count/for_each/
# depends_on on any module that configures its own local provider like
# that, so each cluster gets an explicit module block below rather than
# one for_each'd block. Adding a 6th cluster means adding one more module
# block (and one more line in local.spoke_modules) -- var.spoke_clusters
# still holds the actual path/context/labels values, so tfvars is the only
# place that changes for existing clusters.

# One explicit module block per spoke cluster -- see note above on why this
# can't be for_each'd. Each instance gets its own independent kubernetes
# provider, created inside the module from that cluster's own kubeconfig.

module "spoke_development" {
  source              = "./modules/argocd-spoke-registration"
  cluster_name        = "dvb-argocd-development"
  kubeconfig_path     = var.spoke_clusters["dvb-argocd-development"].kubeconfig_path
  kubeconfig_context  = var.spoke_clusters["dvb-argocd-development"].kubeconfig_context
}

module "spoke_staging" {
  source              = "./modules/argocd-spoke-registration"
  cluster_name        = "dvb-argocd-staging"
  kubeconfig_path     = var.spoke_clusters["dvb-argocd-staging"].kubeconfig_path
  kubeconfig_context  = var.spoke_clusters["dvb-argocd-staging"].kubeconfig_context
}

module "spoke_production_east" {
  source              = "./modules/argocd-spoke-registration"
  cluster_name        = "dvb-argocd-production-east"
  kubeconfig_path     = var.spoke_clusters["dvb-argocd-production-east"].kubeconfig_path
  kubeconfig_context  = var.spoke_clusters["dvb-argocd-production-east"].kubeconfig_context
}

module "spoke_production_central" {
  source              = "./modules/argocd-spoke-registration"
  cluster_name        = "dvb-argocd-production-central"
  kubeconfig_path     = var.spoke_clusters["dvb-argocd-production-central"].kubeconfig_path
  kubeconfig_context  = var.spoke_clusters["dvb-argocd-production-central"].kubeconfig_context
}

module "spoke_production_west" {
  source              = "./modules/argocd-spoke-registration"
  cluster_name        = "dvb-argocd-production-west"
  kubeconfig_path     = var.spoke_clusters["dvb-argocd-production-west"].kubeconfig_path
  kubeconfig_context  = var.spoke_clusters["dvb-argocd-production-west"].kubeconfig_context
}

# Maps each cluster name to its module's outputs, so the secret resource
# below (an ordinary resource, not a legacy-provider module -- for_each is
# fine here) can be driven by a single loop.
locals {
  spoke_modules = {
    "dvb-argocd-development"        = module.spoke_development
    "dvb-argocd-staging"            = module.spoke_staging
    "dvb-argocd-production-east"    = module.spoke_production_east
    "dvb-argocd-production-central" = module.spoke_production_central
    "dvb-argocd-production-west"    = module.spoke_production_west
  }
}

# Standard ArgoCD cluster-registration secret format:
# https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#clusters
resource "kubernetes_secret" "argocd_cluster" {
  for_each = local.spoke_modules

  metadata {
    name      = "cluster-${each.key}"
    namespace = var.argocd_namespace
    labels = merge(
      { "argocd.argoproj.io/secret-type" = "cluster" },
      try(var.spoke_clusters[each.key].labels, {})
    )
  }

  type = "Opaque"

  data = {
    name   = each.key
    server = each.value.server
    config = jsonencode({
      bearerToken = each.value.token
      tlsClientConfig = {
        insecure = false
        caData   = each.value.ca_certificate_data
      }
    })
  }

  depends_on = [helm_release.argocd]
}

output "registered_spoke_clusters" {
  description = "Cluster names registered with ArgoCD via this config."
  value       = keys(local.spoke_modules)
}
