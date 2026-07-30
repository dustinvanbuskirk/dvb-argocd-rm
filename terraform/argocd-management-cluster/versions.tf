terraform {
  required_version = ">= 1.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
    octopusdeploy = {
      source  = "OctopusDeploy/octopusdeploy"
      version = "~> 1.9.0"
    }
  }
}
