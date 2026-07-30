# ── Cluster ───────────────────────────────────────────────────────────────────

variable "kubeconfig_path" {
  description = "Path to kubeconfig written by Vagrantfile provisioner"
  type        = string
  default     = "../kubeconfig"
}

variable "cluster_name" {
  description = "Must match CLUSTER_NAME used in Vagrantfile (default: dvb-finance-1)"
  type        = string
  default     = "dvb-finance-1"
}

# ── Octopus ───────────────────────────────────────────────────────────────────

variable "octopus_server_url" {
  description = "https://your-instance.octopus.app"
  type        = string
}

variable "octopus_polling_url" {
  description = "https://polling.your-instance.octopus.app (used for registration comms address)"
  type        = string
}

variable "octopus_grpc_url" {
  description = "grpcs://your-instance.octopus.app:443 (used by the ArgoCD gateway for its persistent gRPC connection)"
  type        = string
}

variable "octopus_api_key" {
  description = "API-XXXXXXXX"
  type        = string
  sensitive   = true
}

variable "octopus_space_name" {
  type    = string
  default = "Default"
}

# ── Octopus Worker ────────────────────────────────────────────────────────────

variable "install_octopus_worker" {
  description = "Whether to install the Octopus Worker as a Kubernetes deployment (worker pool is still controlled separately via create_worker_pool)"
  type        = bool
  default     = true
}

variable "octopus_worker_pool_name" {
  type    = string
  default = "Vagrant K8s Workers"
}

variable "create_worker_pool" {
  type    = bool
  default = true
}

variable "octopus_worker_count" {
  type    = number
  default = 2
}

# ── Octopus Kubernetes Agent (deployment target) ──────────────────────────────

variable "install_octopus_agent" {
  description = "Whether to install the Octopus Kubernetes Agent as a deployment target"
  type        = bool
  default     = false
}

variable "octopus_agent_namespace" {
  type    = string
  default = "octopus-agent"
}

variable "octopus_agent_environments" {
  description = "Environments to register the deployment target into"
  type        = list(string)
  default     = ["Development", "Test", "Production"]
}

variable "octopus_agent_tags" {
  description = "Target tags to assign to the deployment target (at least one required)"
  type        = list(string)
  default     = ["kubernetes"]
}

variable "octopus_agent_default_namespace" {
  description = "Default Kubernetes namespace the agent deploys into"
  type        = string
  default     = "default"
}

variable "octopus_agent_k8s_monitor_enabled" {
  description = "Enable Kubernetes monitoring via the agent"
  type        = bool
  default     = false
}

variable "octopus_agent_k8s_monitor_grpc_url" {
  description = "gRPC URL for Kubernetes monitor to connect back to Octopus (e.g. grpcs://your-instance.octopus.app:443)"
  type        = string
  default     = ""
}

variable "octopus_agent_cpu_request" {
  type    = string
  default = "250m"
}

variable "octopus_agent_memory_request" {
  type    = string
  default = "512Mi"
}

variable "octopus_agent_cpu_limit" {
  type    = string
  default = "500m"
}

variable "octopus_agent_memory_limit" {
  type    = string
  default = "1Gi"
}

# ── Octopus ArgoCD Gateway ────────────────────────────────────────────────────

variable "install_octopus_gateway" {
  description = "Whether to install the Octopus ArgoCD Gateway (requires install_argocd = true)"
  type        = bool
  default     = false
}

variable "octopus_gateway_namespace" {
  type    = string
  default = "octopus-argocd-gateway"
}

variable "octopus_gateway_chart_version" {
  type    = string
  default = "1.21.0"
}

variable "octopus_gateway_service_type" {
  type    = string
  default = "ClusterIP"
}

variable "octopus_gateway_port" {
  type    = number
  default = 8080
}

# ── NFS CSI (optional) ────────────────────────────────────────────────────────

variable "install_nfs_csi_driver" {
  type    = bool
  default = false
}

variable "nfs_server" {
  description = "NFS server IP/hostname (e.g. your host machine or a dedicated NFS VM)"
  type        = string
  default     = ""
}

variable "nfs_share_path" {
  type    = string
  default = "/"
}

variable "nfs_storage_class_name" {
  type    = string
  default = "nfs-csi-storageclass"
}

# ── ArgoCD (optional) ─────────────────────────────────────────────────────────

variable "install_argocd" {
  type    = bool
  default = false
}

variable "argocd_chart_version" {
  type    = string
  default = "7.7.9"
}

variable "argocd_namespace" {
  type    = string
  default = "argocd"
}

variable "argocd_web_ui_url" {
  description = "URL of the ArgoCD web UI visible from Octopus (e.g. http://localhost:8080 via port-forward, or a NodePort/ingress URL)"
  type        = string
  default     = "http://localhost:8080"
}

# ── Argo Rollouts (optional) ──────────────────────────────────────────────────

variable "install_argo_rollouts" {
  type    = bool
  default = false
}

variable "argo_rollouts_chart_version" {
  type    = string
  default = "2.37.7"
}

# ── ArgoCD spoke cluster registration ─────────────────────────────────────────

variable "spoke_clusters" {
  description = <<-EOT
    Non-management clusters to register with ArgoCD. Map key is used as both
    the ArgoCD cluster display name and must match the cluster `name:` field
    inside the referenced kubeconfig file. Every key referenced by a module
    block in spoke_clusters.tf must have a corresponding entry here.
  EOT
  type = map(object({
    kubeconfig_path    = string
    kubeconfig_context = string
    labels             = optional(map(string), {})
  }))
  default = {}
}

# ── Git repo / ArgoCD repo credential (this same repo, forked) ───────────────

variable "git_repo_url" {
  description = "HTTPS clone URL of this repo's fork, e.g. https://github.com/<you>/dvb-argocd-rm.git. Used both to register the repo with ArgoCD and to render the bootstrap source path in the ApplicationSet."
  type        = string
}

variable "github_username" {
  description = "GitHub username used by ArgoCD to authenticate pulls from git_repo_url."
  type        = string
  sensitive   = true
}

variable "github_api_token" {
  description = "GitHub personal access token (repo scope) used by ArgoCD to authenticate pulls from git_repo_url."
  type        = string
  sensitive   = true
}
