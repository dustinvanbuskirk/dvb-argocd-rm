# ── Octopus ArgoCD Gateway ────────────────────────────────────────────────────
# Chart: oci://registry-1.docker.io/octopusdeploy/octopus-argocd-gateway-chart
# Docs:  https://octopus.com/docs/argo-cd/instances

# ── Namespace ─────────────────────────────────────────────────────────────────

resource "kubernetes_namespace" "octopus_gateway" {
  count = var.install_octopus_gateway ? 1 : 0

  metadata {
    name   = var.octopus_gateway_namespace
    labels = { name = var.octopus_gateway_namespace }
  }
}

# ── Gateway Helm Release ──────────────────────────────────────────────────────

resource "helm_release" "octopus_gateway" {
  count      = var.install_octopus_gateway ? 1 : 0
  name       = "octopus-argocd-gateway"
  repository = "oci://registry-1.docker.io/octopusdeploy"
  chart      = "octopus-argocd-gateway-chart"
  version    = var.octopus_gateway_chart_version
  namespace  = var.octopus_gateway_namespace

  create_namespace = false
  atomic           = false
  timeout          = 600

  # Sensitive values passed via set_sensitive so Terraform handles escaping
  set_sensitive {
    name  = "registration.octopus.serverAccessToken"
    value = var.octopus_api_key
  }
  set_sensitive {
    name  = "gateway.argocd.authenticationToken"
    value = data.kubernetes_secret.argocd_gateway_token[0].data["token"]
  }

  values = [<<-YAML
    registration:
      octopus:
        name: "${var.cluster_name}-argocd-gateway"
        serverApiUrl: "${var.octopus_server_url}"
        spaceId: "${local.space_id}"
      argocd:
        webUiUrl: "${var.argocd_web_ui_url}"

    gateway:
      octopus:
        serverGrpcUrl: "${var.octopus_grpc_url}"
        plaintext: false
      argocd:
        serverGrpcUrl: "argocd-server.${var.argocd_namespace}.svc.cluster.local:80"
        plaintext: true
        insecure: true

    service:
      type: ${var.octopus_gateway_service_type}
      port: ${var.octopus_gateway_port}

  YAML
  ]

  depends_on = [
    helm_release.argocd,
    kubernetes_namespace.octopus_gateway,
    data.kubernetes_secret.argocd_admin,
    data.kubernetes_secret.argocd_gateway_token,
    kubernetes_job_v1.argocd_gateway_token,
  ]
}

# ── Connection info file ──────────────────────────────────────────────────────

resource "local_file" "octopus_gateway_info" {
  count           = var.install_octopus_gateway ? 1 : 0
  filename        = "${path.module}/octopus-gateway-connection-info.txt"
  file_permission = "0600"

  content = <<-EOT
    ==========================================
    Octopus ArgoCD Gateway Connection Info
    ==========================================

    Namespace    : ${var.octopus_gateway_namespace}
    Gateway name : ${var.cluster_name}-argocd-gateway
    Port         : ${var.octopus_gateway_port}

    ==========================================
    ArgoCD connection used by gateway
    ==========================================

    ArgoCD gRPC  : argocd-server.${var.argocd_namespace}.svc.cluster.local:80
    ArgoCD Web UI: ${var.argocd_web_ui_url}
    Password     : ${data.kubernetes_secret.argocd_admin[0].data["password"]}

    ==========================================
    Port-forward to reach gateway locally
    ==========================================

    kubectl --kubeconfig=../kubeconfig \
      port-forward svc/octopus-argocd-gateway \
      -n ${var.octopus_gateway_namespace} ${var.octopus_gateway_port}:${var.octopus_gateway_port}

    Health check:
      curl http://localhost:${var.octopus_gateway_port}/health

    ==========================================
    Verify in Octopus
    ==========================================

    Infrastructure -> Argo CD Instances
    Look for: ${var.cluster_name}-argocd-gateway

    ==========================================
  EOT

  depends_on = [helm_release.octopus_gateway]
}

output "octopus_gateway_info_file" {
  description = "Path to Octopus ArgoCD Gateway connection info file"
  value       = var.install_octopus_gateway ? local_file.octopus_gateway_info[0].filename : ""
}