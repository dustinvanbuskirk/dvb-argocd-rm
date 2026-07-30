# ── Octopus Deploy Kubernetes Agent ──────────────────────────────────────────
# Deployment target agent with optional Kubernetes monitoring
# No AWS/IRSA — plain service account for local Vagrant cluster

locals {
  agent_name = "${var.cluster_name}-agent"
}

# ── Namespace ─────────────────────────────────────────────────────────────────

resource "kubernetes_namespace" "octopus_agent" {
  count = var.install_octopus_agent ? 1 : 0

  metadata {
    name = var.octopus_agent_namespace
    labels = {
      name = var.octopus_agent_namespace
    }
  }
}

# ── Service Account ───────────────────────────────────────────────────────────
# Plain service account — no AWS IRSA annotations needed for local Vagrant cluster

resource "kubernetes_service_account" "octopus_agent" {
  count = var.install_octopus_agent ? 1 : 0

  metadata {
    name      = "octopus-agent"
    namespace = kubernetes_namespace.octopus_agent[0].metadata[0].name
  }
}

# ── Agent Helm Release ────────────────────────────────────────────────────────

resource "helm_release" "octopus_agent" {
  count = var.install_octopus_agent ? 1 : 0

  name             = local.agent_name
  repository       = "oci://registry-1.docker.io"
  chart            = "octopusdeploy/kubernetes-agent"
  version          = "2.*.*"
  namespace        = kubernetes_namespace.octopus_agent[0].metadata[0].name
  create_namespace = false
  atomic           = false
  timeout          = 600

  values = [
    yamlencode({
      agent = {
        acceptEula           = "Y"
        name                 = local.agent_name
        serverApiKey         = var.octopus_api_key
        serverUrl            = var.octopus_server_url
        serverCommsAddresses = [var.octopus_polling_url]
        space                = var.octopus_space_name

        deploymentTarget = {
          enabled = true
          initial = {
            environments     = var.octopus_agent_environments
            tags             = var.octopus_agent_tags
            defaultNamespace = var.octopus_agent_default_namespace
          }
        }

        worker = {
          enabled = false
        }
      }

      kubernetesMonitor = {
        enabled = var.octopus_agent_k8s_monitor_enabled
        registration = var.octopus_agent_k8s_monitor_enabled ? {
          serverApiUrl      = var.octopus_server_url
          serverAccessToken = var.octopus_api_key
          spaceId           = local.space_id
          machineName       = local.agent_name
        } : {}
        monitor = var.octopus_agent_k8s_monitor_enabled ? {
          serverGrpcUrl = var.octopus_agent_k8s_monitor_grpc_url
        } : {}
      }

      serviceAccount = {
        create = false
        name   = kubernetes_service_account.octopus_agent[0].metadata[0].name
      }

      resources = {
        requests = {
          cpu    = var.octopus_agent_cpu_request
          memory = var.octopus_agent_memory_request
        }
        limits = {
          cpu    = var.octopus_agent_cpu_limit
          memory = var.octopus_agent_memory_limit
        }
      }
    })
  ]

  depends_on = [
    kubernetes_service_account.octopus_agent,
    helm_release.nfs_csi_driver,
  ]
}

# ── Cleanup on Destroy ────────────────────────────────────────────────────────

resource "null_resource" "cleanup_octopus_agent" {
  count = var.install_octopus_agent ? 1 : 0

  triggers = {
    agent_name  = local.agent_name
    space_id    = local.space_id
    octopus_url = var.octopus_server_url
    api_key     = var.octopus_api_key
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      echo "Attempting to deregister agent '${self.triggers.agent_name}' from Octopus Deploy..."

      MACHINE_ID=$(curl -s -H "X-Octopus-ApiKey: ${self.triggers.api_key}" \
        "${self.triggers.octopus_url}/api/${self.triggers.space_id}/machines/all" | \
        jq -r '.[] | select(.Name=="${self.triggers.agent_name}") | .Id' | head -n 1)

      if [ -n "$MACHINE_ID" ] && [ "$MACHINE_ID" != "null" ]; then
        echo "Found deployment target ID: $MACHINE_ID"
        curl -X DELETE -H "X-Octopus-ApiKey: ${self.triggers.api_key}" \
          "${self.triggers.octopus_url}/api/${self.triggers.space_id}/machines/$MACHINE_ID"
        echo "Deployment target deregistered successfully"
      else
        echo "Deployment target '${self.triggers.agent_name}' not found in Octopus Deploy (may already be deleted)"
      fi
    EOT
    on_failure = continue
  }

  depends_on = [helm_release.octopus_agent]
}