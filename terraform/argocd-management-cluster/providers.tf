# The Vagrantfile writes kubeconfig to ./kubeconfig (the shared /vagrant folder)
# Override with KUBECONFIG_PATH env var or tfvars if needed

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path
  }
}

provider "octopusdeploy" {
  address = var.octopus_server_url
  api_key = var.octopus_api_key
}