# Registers the forked repo (this same repo, at the user's fork URL) as a
# Git repository ArgoCD can pull from, using a GitHub API token for auth.
#
# git_repo_url and github_api_token are declared in variables.tf alongside
# the rest of this project's variables -- only the resource lives here.
#
# Fork workflow: the ONLY thing that changes per fork is git_repo_url (and
# github_api_token, which is per-user/per-fork by nature). Nothing in the
# ApplicationSet YAML itself needs hand-editing -- see the note at the top
# of applicationsets/argocd-spoke-install-appset.yaml.

# Standard declarative repo-credential format ArgoCD watches for:
# https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#repositories
resource "kubernetes_secret" "argocd_repo_credentials" {
  metadata {
    name      = "argocd-repo-fork"
    namespace = var.argocd_namespace
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  type = "Opaque"

  data = {
    type     = "git"
    url      = var.git_repo_url
    username = var.github_username
    password = var.github_api_token
  }

  depends_on = [helm_release.argocd]
}

# Renders the ApplicationSet template with git_repo_url substituted in, and
# writes the result alongside the template so it's easy to inspect what
# actually got applied (this rendered file is gitignore'd -- it's a build
# artifact, not something to commit; re-running terraform apply overwrites
# it in place).
resource "local_file" "argocd_appset_rendered" {
  filename = "${path.module}/argocd-appset.rendered.yaml"
  content = templatefile("${path.module}/argocd-appset.yaml.tpl", {
    git_repo_url = var.git_repo_url
  })
}

# Applies the rendered ApplicationSet to the management cluster. Uses
# local-exec + kubectl rather than kubernetes_manifest, since kubernetes_manifest
# needs the ApplicationSet CRD's schema available at plan time, which doesn't
# exist until helm_release.argocd has already applied -- a chicken-and-egg
# problem this sidesteps entirely.
resource "null_resource" "apply_argocd_appset" {
  triggers = {
    rendered_hash = sha256(local_file.argocd_appset_rendered.content)
  }

  provisioner "local-exec" {
    # --validate=false works around a known ArgoCD gap: the ApplicationSet
    # CRD's embedded copy of the Application schema for
    # spec.template.spec.sources[] doesn't include the `name` field on
    # some ArgoCD/chart versions, even though the ApplicationSet
    # controller's actual code fully supports it when generating the real
    # Application objects. Without this flag, kubectl's strict schema
    # validation rejects the ApplicationSet before it's ever created.
    command = "kubectl --kubeconfig=${var.kubeconfig_path} apply --validate=false -f ${local_file.argocd_appset_rendered.filename}"
  }

  depends_on = [
    helm_release.argocd,
    kubernetes_secret.argocd_repo_credentials,
    local_file.argocd_appset_rendered,
  ]
}
