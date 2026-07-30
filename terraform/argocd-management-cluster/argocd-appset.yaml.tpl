# NOTE: this file is rendered by Terraform via templatefile() before being
# applied -- the $${git_repo_url} below is a Terraform interpolation, not
# valid YAML on its own. See git-repo-and-appsets.tf. It does not collide
# with ArgoCD's own {{.name}}/{{.server}} Go-template syntax used further
# down, since Terraform only substitutes $${...} expressions.
#
# Installs ArgoCD via a per-cluster umbrella chart at
# argocd-versions/<cluster-name>/ in this same repo -- each cluster has its
# own Chart.yaml (dependencies: argo-cd + a local file:// dependency on
# charts/argocd-token-gen, the shared bootstrap RBAC + PostSync hook Job)
# and values.yaml (Helm values, argo-cd only). Chart.yaml is what Octopus's
# "Update Argo CD Application Manifests" step overwrites on deployment, via
# an Octostache template (see octostache-templates/Chart.yaml), to change
# the pinned argo-cd dependency version -- values.yaml is a normal
# git-committed file, not templated. Lives on the MANAGEMENT cluster's
# ArgoCD (this is what pushes the chart out to each spoke) -- it does not
# touch the management cluster's own ArgoCD, which stays installed via
# Terraform's helm_release.argocd.
#
# SINGLE SOURCE, NOT MULTI-SOURCE: an earlier version of this file used a
# second Application source for the bootstrap Job, which required naming
# that source (per https://octopus.com/docs/argo-cd/annotations#multiple-sources)
# -- but the ApplicationSet CRD's embedded copy of the Application schema
# doesn't include sources[].name on the ArgoCD version this repo installs,
# so the API server silently pruned that field on every apply, and the
# generated Applications never actually got a named source no matter what
# the template said. The token-gen Job is now a local Helm dependency
# instead (see charts/argocd-token-gen/), so it deploys as part of the same
# single source with no second source needed at all.
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
        # Single source now -- per
        # https://octopus.com/docs/argo-cd/annotations#single-source,
        # unscoped (unsuffixed) annotations are correct here; no source
        # name needed or used.
        #
        # Values must be Octopus SLUGS, not display names -- confirm
        # "argocd-management" matches your actual Octopus project's slug
        # (visible in its URL/settings), and that each environment/tenant
        # slug below matches what Octopus generated for your Environments
        # (e.g. a "Production" environment's slug may not be "production"
        # if it was renamed after creation).
        argo.octopus.com/project: "argocd-management"
        argo.octopus.com/environment: '{{ index (splitList "-" (trimPrefix "dvb-argocd-" .name)) 0 }}'
        argo.octopus.com/tenant: '{{ $parts := splitList "-" (trimPrefix "dvb-argocd-" .name) }}{{ if gt (len $parts) 1 }}{{ index $parts 1 }}{{ end }}'
    spec:
      project: default
      source:
        repoURL: ${git_repo_url}
        path: "argocd-versions/{{.name}}"
        targetRevision: main
        helm:
          releaseName: argocd
      destination:
        server: "{{.server}}"
        namespace: argocd
      syncPolicy:
        automated:
          selfHeal: true
        syncOptions:
          - CreateNamespace=true