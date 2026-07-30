# NOTE: this file is rendered by Terraform via templatefile() before being
# applied -- the $${git_repo_url} below is a Terraform interpolation, not
# valid YAML on its own. See git-repo-and-appsets.tf. It does not collide
# with ArgoCD's own {{.name}}/{{.server}} Go-template syntax used further
# down, since Terraform only substitutes $${...} expressions.
#
# Installs ArgoCD (argo-helm/argo-cd @ 7.7.9) onto every registered spoke
# cluster. Lives on the MANAGEMENT cluster's ArgoCD (this is what pushes the
# chart out to each spoke) -- it does not touch the management cluster's own
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
    - matrix:
        generators:
          - clusters:
              selector:
                matchExpressions:
                  - key: env
                    operator: Exists
          - git:
              repoURL: ${git_repo_url}
              revision: main
              files:
                # Second generator's path references {{.name}} from the
                # cluster generator above -- ArgoCD evaluates this generator
                # once per matched cluster, substituting that cluster's own
                # name in. Each cluster needs its own values.yaml committed
                # at this path (see argocd-versions/ in this repo) or that
                # cluster is silently skipped -- there's no fallback/default.
                - path: "argocd-versions/{{.name}}/values.yaml"

  template:
    metadata:
      name: "argocd-{{.name}}"
      annotations:
        argo.octopus.com/project: "ArgoCD Management"
        argo.octopus.com/environment: '{{ index (splitList "-" (trimPrefix "dvb-argocd-" .name)) 0 }}'
        argo.octopus.com/tenant: '{{ $parts := splitList "-" (trimPrefix "dvb-argocd-" .name) }}{{ if gt (len $parts) 1 }}{{ index $parts 1 }}{{ end }}'
    spec:
      project: default
      # Multi-source Application: the Helm chart installs ArgoCD, and the
      # second source deploys the RBAC + PostSync hook Job that generates
      # the gateway token right after ArgoCD comes up. Replace repoURL/
      # targetRevision below with wherever you commit
      # bootstrap/argocd-token-gen/manifests.yaml.
      sources:
        - repoURL: https://argoproj.github.io/argo-helm
          chart: argo-cd
          targetRevision: '{{ .targetRevision }}'
          helm:
            releaseName: argocd
            valuesObject:
              global:
                domain: argocd.local
              server:
                replicas: 1
                service:
                  type: NodePort
                ingress:
                  enabled: false
                extraArgs:
                  - --insecure
                metrics:
                  enabled: false
              configs:
                params:
                  server.insecure: "true"
              redis-ha:
                enabled: false
              controller:
                replicas: 1
              repoServer:
                replicas: 1
              applicationSet:
                replicas: 1
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