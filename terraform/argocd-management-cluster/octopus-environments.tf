# Octopus Deploy Environments
# Creates environments defined in octopus_agent_environments variable
# Space is resolved from octopus_space_name variable

data "octopusdeploy_space" "space" {
  name = var.octopus_space_name
}

resource "octopusdeploy_environment" "environments" {
  for_each = toset(var.octopus_agent_environments)

  name                         = each.value
  description                  = "Managed by Terraform"
  allow_dynamic_infrastructure = true
  use_guided_failure           = false
  space_id                     = data.octopusdeploy_space.space.id
}