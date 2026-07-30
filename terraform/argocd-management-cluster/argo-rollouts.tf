resource "helm_release" "argo_rollouts" {
  count      = var.install_argo_rollouts ? 1 : 0
  name       = "argo-rollouts"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-rollouts"
  version    = var.argo_rollouts_chart_version
  namespace  = "argo-rollouts"

  create_namespace = false
  timeout          = 600
  atomic           = false

  set {
    name  = "controller.replicas"
    value = "1"
  }
  set {
    name  = "controller.metrics.enabled"
    value = "false"
  }
  set {
    name  = "dashboard.enabled"
    value = "true"
  }
  set {
    name  = "dashboard.service.type"
    value = "ClusterIP"
  }

  depends_on = [kubernetes_namespace.argo_rollouts]
}

output "argo_rollouts_dashboard_access" {
  description = "Port-forward to reach the Argo Rollouts dashboard"
  value = var.install_argo_rollouts ? (
    "kubectl --kubeconfig=../kubeconfig port-forward svc/argo-rollouts-dashboard -n argo-rollouts 3100:3100"
  ) : ""
}