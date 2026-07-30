# NOTE: this file is rendered by Terraform via templatefile() before being
# applied -- the $${git_repo_url} below is a Terraform interpolation, not
# valid YAML on its own. See git-repo-and-appsets.tf. It does not collide
# with ArgoCD's own {{.name}}/{{.server}} Go-template syntax used further
# down, since Terraform only substitutes $${...} expressions.
#
# Installs ArgoCD via a per-cluster umbrella chart at
# argocd-versions/<cluster-name>/ in this same repo -- each cluster has its
# own Chart.yaml (dependency version) and values.yaml (Helm values).
# Chart.yaml is what Octopus's "Update Argo CD Application Manifests" step
# overwrites on deployment, via an Octostache template (see
# octostache-templates/Chart.yaml), to change the pinned argo-cd dependency
# version -- values.yaml is a normal git-committed file, not templated.
# Lives on the MANAGEMENT cluster's ArgoCD (this is what pushes the chart
# out to each spoke) -- it does not touch the management cluster's own
# ArgoCD, which stays installed via Terraform's helm_release.argocd.
#
# Selector: matches only cluster secrets carrying an "env" label. That's the
# label set on the spoke cluster secrets (see kubernetes_secret.argocd_cluster
# / spoke_clusters.tf), so this naturally excludes ArgoCD's implicit
# "in-cluster" entry (which has no such label) without needing to name it.

apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: argocd-spoke-install
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]

  generators:
    - clusters:
        selector:
          matchExpressions:
            - key: env
              operator: Exists

  template:
    metadata:
      name: "argocd-{{.name}}"
      annotations:
        argo.octopus.com/project: "ArgoCD Management"
        argo.octopus.com/environment: '{{ index (splitList "-" (trimPrefix "dvb-argocd-" .name)) 0 }}'
        argo.octopus.com/tenant: '{{ $parts := splitList "-" (trimPrefix "dvb-argocd-" .name) }}{{ if gt (len $parts) 1 }}{{ index $parts 1 }}{{ end }}'
    spec:
      project: default
      # Two-source Application: source 1 installs this cluster's own
      # umbrella chart (folder name = cluster name, so each Application
      # gets a distinct path); source 2 deploys the RBAC + PostSync hook
      # Job that generates the gateway token right after ArgoCD comes up.
      sources:
        - repoURL: ${git_repo_url}
          path: "argocd-versions/{{.name}}"
          targetRevision: main
          helm:
            releaseName: argocd
        - repoURL: ${git_repo_url}
          targetRevision: main
          path: bootstrap/argocd-token-gen
      destination:
        server: "{{.server}}"
        namespace: argocd
      syncPolicy:
        automated:
          selfHeal: true
        syncOptions:
          - CreateNamespace=true