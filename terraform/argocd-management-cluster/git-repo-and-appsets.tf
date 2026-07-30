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
