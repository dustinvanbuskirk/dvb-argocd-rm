# Setup

This covers everything needed to get `dvb-argocd-rm` running on a local
machine: host prerequisites, provisioning the six Vagrant clusters, and
wiring up Terraform and Octopus for the first time. For how the platform
works once it's running -- architecture, ApplicationSets, and version
promotion -- see [USAGE.md](USAGE.md).

## Host machine setup (Windows NUC)

This runs on a single Windows 11 box: VirtualBox/Vagrant manage the VMs
directly from Windows (run from **PowerShell**), while Terraform/kubectl/git
run from **WSL2** against the repo checked out on the Windows filesystem
(this is the pattern the command examples below assume).

### 1. Enable virtualization in BIOS/UEFI

Confirm Intel VT-x (or AMD-V) is enabled in the NUC's BIOS/UEFI before
installing anything below -- both VirtualBox and WSL2 need it, and it's
off by default on some NUC firmware.

### 2. Install Chocolatey

From an **administrator** PowerShell prompt:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
```

Close and reopen the shell afterward so `choco` is on `PATH`.

### 3. Install required software

```powershell
choco install virtualbox -y
choco install vagrant -y
choco install terraform -y
choco install kubernetes-cli -y
choco install git -y
```

| Tool | Chocolatey package | Minimum version | Why |
|---|---|---|---|
| VirtualBox | `virtualbox` | 6.1+ | Runs the cluster VMs |
| Vagrant | `vagrant` | 2.2.19+ | Provisions the Vagrantfile |
| Terraform | `terraform` | **1.3+** | `optional()` in `variables.tf`'s `spoke_clusters` type requires it |
| kubectl | `kubernetes-cli` | any recent | Cluster access, kubeconfig merging |
| Git | `git` | any recent | Cloning your fork, pushing `argocd-versions/` changes |
| Helm | `kubernetes-helm` | 3.8+ | Local dependency resolution (`helm dependency update`) for the umbrella charts |

A reboot after installing VirtualBox is recommended before first use.

### 4. Install WSL2

```powershell
wsl --install
```

Reboots when prompted, enables the "Virtual Machine Platform" and
"Windows Subsystem for Linux" Windows features, sets WSL2 as the default
version, and installs Ubuntu.

Inside the new Ubuntu shell, install matching Terraform/kubectl/helm so
commands behave identically whether run from PowerShell or WSL:

```bash
sudo apt update
sudo apt install -y unzip curl gnupg software-properties-common

# Terraform
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y terraform

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

Your Windows filesystem is reachable from WSL under `/mnt/c/...` -- e.g. a
repo cloned to `C:\Users\<you>\src\dvb-argocd-rm` shows up at
`/mnt/c/Users/<you>/src/dvb-argocd-rm`. Run `vagrant`/`VBoxManage` commands
from PowerShell (VirtualBox VM management doesn't work from inside WSL),
and run `terraform`/`kubectl`/`git`/`helm` from WSL against that same path.

### 5. VirtualBox and WSL2 on the same machine

These two used to conflict outright (WSL2 requires Hyper-V; older
VirtualBox versions required exclusive access to VT-x). VirtualBox 6.1.18+
can run alongside Hyper-V/WSL2 using the Windows Hypervisor Platform
(WHPX) as its acceleration backend instead -- Oracle still documents this
as "experimental," but it's the expected way to run both today, and no
`bcdedit` changes should be needed.

If a VM fails to boot with `VERR_NEM_NOT_AVAILABLE` or "VT-x is not
available": confirm both "Virtual Machine Platform" and "Windows
Hypervisor Platform" are enabled in Windows Features
(`optionalfeatures.exe`), and check that no per-VM nested-virtualization
setting is fighting with it.

### Additional prerequisites

- An Octopus Deploy instance and API key
- A fork of this repository, plus a GitHub personal access token (repo scope)
- A git credential configured in Octopus (Infrastructure -> Git
  Credentials) for this repo -- required before the "Update Argo CD
  Application Manifests" step will run

## Setup

### 1. Provision the clusters

```powershell
vagrant up
```

Brings up all 6 clusters (12 VMs by default: 1 control-plane + 1 worker
each). To bring up a subset while testing, e.g.:

```powershell
$env:CLUSTERS_TO_CREATE='dvb-argocd-management,dvb-argocd-development'
vagrant up
```

Resource note: all 6 clusters at once is 24 vCPU / ~48GB RAM at the
defaults (`CONTROL_PLANE_CPUS`/`MEMORY`, `WORKER_CPUS`/`MEMORY` env vars
override this).

This writes, per cluster, to the project root: `<cluster>-kubeconfig`
(raw), `kubeconfigs/<cluster>.conf` (renamed export, used for cross-cluster
access), plus `join-commands/`, `worker-tracking/`, `logs/`.

### 2. Fork this repo

The only two things that change per fork are `git_repo_url` and
`github_api_token` in `terraform.tfvars` -- nothing else in this project
needs hand-editing to point at a fork.

### 3. Configure Terraform

```powershell
cd terraform/argocd-management-cluster
cp terraform.tfvars.example terraform.tfvars
```

Fill in `terraform.tfvars`: Octopus connection details, `kubeconfig_path`
for the management cluster, `spoke_clusters` (paths to each spoke's
`kubeconfigs/<cluster>.conf` and its renamed context), and `git_repo_url` /
`github_username` / `github_api_token` for your fork.

### 4. Apply

```powershell
terraform init
terraform apply
```

This installs ArgoCD + the Octopus Gateway/Worker/Agent on the management
cluster, registers each spoke cluster as an ArgoCD Cluster secret, creates
a Git repository credential Secret for your fork, and renders + applies
`argocd-appset.yaml.tpl` to the management cluster's ArgoCD.

### 5. Configure the Octopus deployment process

In your Octopus project, add an **Update Argo CD Application Manifests**
step:

- Template source: this git repo (your fork), branch `main`
- Path to templates: `octostache-templates` (a directory -- both
  `octostache-templates` and `octostache-templates/**/*` glob patterns get
  generated automatically)
- A **git credential** for this repo must exist in Octopus first, or the
  step fails outright before doing anything

Then define `#{ArgoCDChartVersion}` as a project variable, scoped per
Environment (and Tenant, for the three regional production clusters) so
promoting a release through your normal Octopus lifecycle is what changes
the deployed ArgoCD version per cluster.

**Important:** Octopus releases pin an exact git commit at creation time.
If you change files in this repo (`octostache-templates/`, etc.) *after*
creating a release, that release keeps pointing at the old commit --
create a new release to pick up repo changes, don't try to redeploy an
existing one.

## Getting cross-cluster `kubectl` access

Each control-plane exports a renamed kubeconfig to `kubeconfigs/<cluster>.conf`
during Vagrant provisioning. To merge them onto the management node into one
kubeconfig with a context per cluster, run the `merge-kubeconfigs`
provisioner (not run automatically, since it needs every desired cluster
to already be up):

```powershell
vagrant provision dvb-argocd-management-control-plane --provision-with merge-kubeconfigs
vagrant ssh dvb-argocd-management-control-plane
kubectl config get-contexts
kubectl config use-context dvb-argocd-production-east
```

Once setup is complete, see [USAGE.md](USAGE.md) for how version
promotion, the ApplicationSet, and the Octopus scoping annotations
actually work day to day.
