# dvb-argocd-rm

A homelab hub-and-spoke ArgoCD platform: six Vagrant-provisioned Kubernetes
clusters (one management "hub" + five spokes), wired together with
Terraform, an ArgoCD ApplicationSet, per-cluster Helm umbrella charts, and
Octopus Deploy driving version promotion.

The management cluster runs ArgoCD and the Octopus ArgoCD Gateway. From
there, an ApplicationSet installs ArgoCD onto each spoke cluster
automatically. Each spoke's ArgoCD chart version is promoted through
Octopus's own release/environment process, via its "Update Argo CD
Application Manifests" step -- not by hand-editing files or running
scripts.

## Documentation

- **[SETUP.md](SETUP.md)** -- host machine prerequisites (Windows NUC,
  VirtualBox, WSL2), provisioning the six clusters with Vagrant, and
  configuring Terraform + Octopus for the first time.
- **[USAGE.md](USAGE.md)** -- architecture, network topology, repository
  layout, how the ApplicationSet installs ArgoCD onto each spoke, how
  Octopus promotes ArgoCD versions across environments/tenants, and
  common pitfalls.
