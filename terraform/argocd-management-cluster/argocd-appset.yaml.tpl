# NOTE: this file is rendered by Terraform via templatefile() before being
# applied -- the $${git_repo_url} below is a Terraform interpolation, not
# valid YAML on its own. See git-repo-and-appsets.tf. It does not collide
# with ArgoCD's own {{.name}}/{{.server}} Go-template syntax used further
# down, since Terraform only substitutes $${...} expressions.
#
# Installs ArgoCD via this repo's own argocd-umbrella-chart (which pins
# the upstream argo-cd chart version in its Chart.yaml -- see
# argocd-umbrella-chart/values.yaml's meta.chartVersion for the documented
# version, and argocd-umbrella-chart/sync-chart-version.sh to propagate a
# change into Chart.yaml). Lives on the MANAGEMENT cluster's ArgoCD (this
# is what pushes the chart out to each spoke) -- it does not touch the
# management cluster's own ArgoCD, which stays installed via Terraform's
# helm_release.argocd.
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
      # Three-source Application: source 1 installs the umbrella chart
      # (which pulls in argo-cd as a dependency); source 2 is an unnamed-
      # path "ref" source providing this cluster's override values file to
      # source 1's valueFiles; source 3 deploys the RBAC + PostSync hook
      # Job that generates the gateway token right after ArgoCD comes up.
      sources:
        - repoURL: ${git_repo_url}
          path: argocd-umbrella-chart
          targetRevision: main
          helm:
            releaseName: argocd
            # Chart's own values.yaml (argocd-umbrella-chart/values.yaml)
            # supplies the defaults automatically. This adds this cluster's
            # override file on top -- sparse diffs only, see
            # argocd-versions/<cluster-name>/values.yaml. Referenced via the
            # named ref source below since it lives outside the chart path.
            valueFiles:
              - $cluster-values/argocd-versions/{{.name}}/values.yaml
        - repoURL: ${git_repo_url}
          targetRevision: main
          ref: cluster-values
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