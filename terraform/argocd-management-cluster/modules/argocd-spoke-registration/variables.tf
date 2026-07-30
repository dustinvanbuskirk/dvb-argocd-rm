variable "cluster_name" {
  description = "Name of the spoke cluster. Must match the `name:` field of the cluster entry inside the kubeconfig file at kubeconfig_path."
  type        = string
}

variable "kubeconfig_path" {
  description = "Path to this spoke cluster's exported kubeconfig (e.g. the file written to /vagrant/kubeconfigs/<name>.conf by the Vagrantfile)."
  type        = string
}

variable "kubeconfig_context" {
  description = "Context name to use inside kubeconfig_path (e.g. <name>-admin@<name>)."
  type        = string
}

variable "service_account_namespace" {
  description = "Namespace on the spoke cluster to create the argocd-manager ServiceAccount in."
  type        = string
  default     = "kube-system"
}
