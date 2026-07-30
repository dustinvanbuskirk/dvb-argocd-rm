# ── Worker Pool ───────────────────────────────────────────────────────────────

data "octopusdeploy_spaces" "target" {
  partial_name = var.octopus_space_name
  take         = 1
}

locals {
  space_id = data.octopusdeploy_spaces.target.spaces[0].id
}

resource "octopusdeploy_static_worker_pool" "vagrant" {
  count       = var.create_worker_pool ? 1 : 0
  name        = var.octopus_worker_pool_name
  description = "Vagrant Kubernetes workers (local dev)"
  space_id    = local.space_id
  sort_order  = 0
  is_default  = false

  lifecycle { ignore_changes = [description, sort_order] }
}

data "octopusdeploy_worker_pools" "selected" {
  partial_name = var.octopus_worker_pool_name
  skip         = 0
  take         = 1
  space_id     = local.space_id
  depends_on   = [octopusdeploy_static_worker_pool.vagrant]
}

locals {
  worker_pool_id = data.octopusdeploy_worker_pools.selected.worker_pools[0].id
}

# ── NFS CSI Driver (optional) ─────────────────────────────────────────────────

resource "helm_release" "nfs_csi_driver" {
  count      = var.install_nfs_csi_driver ? 1 : 0
  name       = "csi-driver-nfs"
  repository = "https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts"
  chart      = "csi-driver-nfs"
  version    = "4.12.1"
  namespace  = "kube-system"

  set {
    name  = "controller.replicas"
    value = "1"
  }
  set {
    name  = "controller.runOnControlPlane"
    value = "false"
  }
}

resource "kubernetes_storage_class_v1" "nfs" {
  count = var.install_nfs_csi_driver && var.nfs_server != "" ? 1 : 0

  metadata {
    name = var.nfs_storage_class_name
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "nfs.csi.k8s.io"
  reclaim_policy         = "Retain"
  volume_binding_mode    = "Immediate"
  allow_volume_expansion = true

  parameters = {
    server = var.nfs_server
    share  = var.nfs_share_path
  }

  mount_options = ["nfsvers=4.1", "hard", "nolock"]

  depends_on = [helm_release.nfs_csi_driver]
}

# ── Octopus Worker Helm Release ───────────────────────────────────────────────

resource "helm_release" "octopus_worker" {
  count            = var.install_octopus_worker ? 1 : 0
  name             = "octopus-worker"
  repository       = "oci://registry-1.docker.io/octopusdeploy"
  chart            = "kubernetes-agent"
  version          = "2.*.*"
  namespace        = kubernetes_namespace.octopus_workers.metadata[0].name
  create_namespace = false
  atomic           = false
  timeout          = 600

  set {
    name  = "agent.acceptEula"
    value = "Y"
  }
  set {
    name  = "agent.name"
    value = var.cluster_name
  }
  set {
    name  = "agent.serverUrl"
    value = var.octopus_server_url
  }
  set {
    name  = "agent.serverCommsAddress"
    value = var.octopus_polling_url
  }
  set {
    name  = "agent.space"
    value = var.octopus_space_name
  }

  set_sensitive {
    name  = "agent.serverApiKey"
    value = var.octopus_api_key
  }

  set {
    name  = "agent.worker.enabled"
    value = "true"
  }
  set {
    name  = "agent.deploymentTarget.enabled"
    value = "false"
  }

  set_list {
    name  = "agent.worker.initial.workerPools"
    value = [local.worker_pool_id]
  }

  set {
    name  = "replicaCount"
    value = tostring(var.octopus_worker_count)
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }
  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.octopus_worker.metadata[0].name
  }

  set {
    name  = "resources.requests.cpu"
    value = "250m"
  }
  set {
    name  = "resources.requests.memory"
    value = "512Mi"
  }
  set {
    name  = "resources.limits.cpu"
    value = "500m"
  }
  set {
    name  = "resources.limits.memory"
    value = "1Gi"
  }

  depends_on = [
    data.octopusdeploy_worker_pools.selected,
    kubernetes_service_account.octopus_worker,
  ]
}