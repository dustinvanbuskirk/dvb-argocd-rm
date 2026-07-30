resource "helm_release" "argocd" {
  count      = var.install_argocd ? 1 : 0
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  namespace  = var.argocd_namespace

  create_namespace = false
  timeout          = 600
  atomic           = false

  set {
    name  = "global.domain"
    value = "argocd.local"
  }
  set {
    name  = "server.service.type"
    value = "NodePort"
  }
  set {
    name  = "server.ingress.enabled"
    value = "false"
  }
  set {
    name  = "configs.params.server\\.insecure"
    value = "true"
  }
  set {
    name  = "server.extraArgs[0]"
    value = "--insecure"
  }
  set {
    name  = "redis-ha.enabled"
    value = "false"
  }
  set {
    name  = "controller.replicas"
    value = "1"
  }
  set {
    name  = "server.replicas"
    value = "1"
  }
  set {
    name  = "repoServer.replicas"
    value = "1"
  }
  set {
    name  = "applicationSet.replicas"
    value = "1"
  }
  set {
    name  = "server.metrics.enabled"
    value = "false"
  }

  depends_on = [kubernetes_namespace.argocd]
}

data "kubernetes_secret" "argocd_admin" {
  count = var.install_argocd ? 1 : 0
  metadata {
    name      = "argocd-initial-admin-secret"
    namespace = var.argocd_namespace
  }
  depends_on = [helm_release.argocd]
}

resource "local_file" "argocd_info" {
  count           = var.install_argocd ? 1 : 0
  filename        = "${path.module}/argocd-connection-info.txt"
  file_permission = "0600"

  content = <<-EOT
    ==========================================
    ArgoCD Connection Info
    ==========================================
    Username : admin
    Password : ${data.kubernetes_secret.argocd_admin[0].data["password"]}

    port-forward:
      kubectl --kubeconfig=../kubeconfig port-forward svc/argocd-server -n ${var.argocd_namespace} 8080:80

    Then open: http://localhost:8080
    ==========================================
  EOT

  depends_on = [data.kubernetes_secret.argocd_admin]
}

output "argocd_info_file" {
  description = "Path to ArgoCD connection info file"
  value       = var.install_argocd ? local_file.argocd_info[0].filename : ""
}

resource "kubernetes_service_account" "argocd_token_gen" {
  count = var.install_argocd ? 1 : 0
  metadata {
    name      = "argocd-token-gen"
    namespace = var.argocd_namespace
  }
  depends_on = [kubernetes_namespace.argocd]
}

resource "kubernetes_role" "argocd_token_gen" {
  count = var.install_argocd ? 1 : 0
  metadata {
    name      = "argocd-token-gen"
    namespace = var.argocd_namespace
  }
  rule {
    api_groups = [""]
    resources  = ["configmaps", "secrets"]
    verbs      = ["get", "list", "create", "update", "patch"]
  }
  depends_on = [kubernetes_namespace.argocd]
}

resource "kubernetes_role_binding" "argocd_token_gen" {
  count = var.install_argocd ? 1 : 0
  metadata {
    name      = "argocd-token-gen"
    namespace = var.argocd_namespace
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.argocd_token_gen[0].metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.argocd_token_gen[0].metadata[0].name
    namespace = var.argocd_namespace
  }
  depends_on = [kubernetes_role.argocd_token_gen]
}

resource "kubernetes_job_v1" "argocd_gateway_token" {
  count = var.install_argocd ? 1 : 0

  metadata {
    name      = "argocd-gateway-token-gen"
    namespace = var.argocd_namespace
  }

  spec {
    template {
      metadata {
        labels = { job = "argocd-gateway-token-gen" }
      }
      spec {
        restart_policy       = "Never"
        service_account_name = kubernetes_service_account.argocd_token_gen[0].metadata[0].name

        init_container {
          name    = "check-secret"
          image   = "docker.io/dustinvanbuskirk/argocd-token-gen:v2.9.0"
          command = ["/bin/bash", "-c"]
          args    = [<<-SCRIPT
            if kubectl get secret argocd-gateway-token -n argocd > /dev/null 2>&1; then
              echo "==> argocd-gateway-token already exists, nothing to do."
              touch /tmp/skip
            else
              echo "==> argocd-gateway-token not found, proceeding with token generation."
            fi
          SCRIPT
          ]

          volume_mount {
            name       = "shared"
            mount_path = "/tmp"
          }
        }

        container {
          name    = "token-gen"
          image   = "docker.io/dustinvanbuskirk/argocd-token-gen:v2.9.0"
          command = ["/bin/bash", "-c"]
          args    = [<<-SCRIPT
            set -e

            if [ -f /tmp/skip ]; then
              echo "==> Secret already exists, skipping."
              exit 0
            fi

            ARGOCD_SERVER="argocd-server.argocd.svc.cluster.local:80"
            ARGOCD_PASSWORD=$(cat /argocd-admin-secret/password)

            echo "==> Patching argocd-cm to enable apiKey for admin..."
            kubectl patch configmap argocd-cm \
              -n argocd \
              --type merge \
              -p '{"data":{"accounts.admin":"apiKey, login"}}'
            echo "argocd-cm patched."

            echo "==> Waiting for ArgoCD to reload config (20s)..."
            sleep 20

            echo "==> Verifying ArgoCD server is reachable..."
            curl -sf --max-time 10 "http://$ARGOCD_SERVER/healthz" \
              || curl -sfk --max-time 10 "https://$ARGOCD_SERVER/healthz" \
              || { echo "ERROR: ArgoCD server not reachable on port 80"; exit 1; }

            echo "==> Logging into ArgoCD..."
            argocd login "$ARGOCD_SERVER" \
              --username admin \
              --password "$ARGOCD_PASSWORD" \
              --plaintext \
              --insecure

            echo "==> Generating token for admin account..."
            GATEWAY_TOKEN=$(argocd account generate-token \
              --server "$ARGOCD_SERVER" \
              --plaintext \
              --insecure)

            if [ -z "$GATEWAY_TOKEN" ]; then
              echo "ERROR: token empty"
              exit 1
            fi
            echo "Token obtained."

            echo "==> Storing secret via kubectl..."
            kubectl create secret generic argocd-gateway-token \
              -n argocd \
              --from-literal=token="$GATEWAY_TOKEN"
            echo "Secret created."

            echo "==> Done."
          SCRIPT
          ]

          volume_mount {
            name       = "argocd-admin-secret"
            mount_path = "/argocd-admin-secret"
            read_only  = true
          }

          volume_mount {
            name       = "shared"
            mount_path = "/tmp"
          }
        }

        volume {
          name = "argocd-admin-secret"
          secret {
            secret_name = "argocd-initial-admin-secret"
          }
        }

        volume {
          name = "shared"
          empty_dir {}
        }
      }
    }

    backoff_limit = 2
  }

  wait_for_completion = true

  timeouts {
    create = "5m"
    update = "5m"
  }

  depends_on = [
    helm_release.argocd,
    data.kubernetes_secret.argocd_admin,
    kubernetes_role_binding.argocd_token_gen,
  ]
}

data "kubernetes_secret" "argocd_gateway_token" {
  count = var.install_argocd ? 1 : 0
  metadata {
    name      = "argocd-gateway-token"
    namespace = var.argocd_namespace
  }
  depends_on = [kubernetes_job_v1.argocd_gateway_token]
}