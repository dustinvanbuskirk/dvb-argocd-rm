# Vagrantfile - Multi-Cluster Kubernetes (ArgoCD hub/spoke) topology
#
# Brings up multiple independent Kubernetes clusters (each with its own control
# plane + workers) in a single Vagrant project, all sharing one /16 private
# network so any cluster can reach any other cluster's API server directly.
#
# CLUSTERS CREATED (edit the CLUSTERS array below to add/remove):
#   dvb-argocd-management          (10.20.10.0/24)
#   dvb-argocd-development         (10.20.20.0/24)
#   dvb-argocd-staging             (10.20.30.0/24)
#   dvb-argocd-production-east     (10.20.40.0/24)
#   dvb-argocd-production-central  (10.20.50.0/24)
#   dvb-argocd-production-west     (10.20.60.0/24)
#
# RESOURCE NOTE: bringing up all 6 clusters with 1 control-plane + 1 worker
# each = 12 VMs. At the defaults below (2 vCPU / 4096MB per node) that's
# 24 vCPU / ~48GB RAM. Raise CONTROL_PLANE_CPUS/MEMORY and WORKER_CPUS/MEMORY
# env vars if you have headroom, or use CLUSTERS_TO_CREATE to bring up a
# subset at a time.
#
# USAGE:
#   vagrant up                                   # all clusters/nodes
#   $env:CLUSTERS_TO_CREATE='dvb-argocd-management,dvb-argocd-development'
#   vagrant up                                   # only the listed clusters
#
#   # After ALL desired clusters are up, merge their kubeconfigs onto the
#   # management control-plane so it can talk to every cluster's API:
#   vagrant provision dvb-argocd-management-control-plane --provision-with merge-kubeconfigs
#   vagrant ssh dvb-argocd-management-control-plane
#     kubectl config get-contexts
#     kubectl config use-context dvb-argocd-production-east
#     kubectl get nodes
#
#   # To pull that merged kubeconfig back to your Windows host instead:
#   vagrant ssh dvb-argocd-management-control-plane -c "cat ~/.kube/config" > merged-kubeconfig

require 'securerandom'

# ---------------------------------------------------------------------------
# Global configuration
# ---------------------------------------------------------------------------

KUBERNETES_VERSION = '1.28'
POD_NETWORK_CIDR   = '10.244.0.1/16'

# All clusters share this /16 so nodes in different clusters can route to
# each other directly (VirtualBox will place any IP in this range on the
# same host-only adapter as long as the netmask matches).
NETWORK_BASE = '10.20'
NETMASK      = '255.255.0.0'

CONTROL_PLANE_CPUS   = ENV['CONTROL_PLANE_CPUS']&.to_i   || 2
CONTROL_PLANE_MEMORY = ENV['CONTROL_PLANE_MEMORY']&.to_i || 4096
WORKER_CPUS           = ENV['WORKER_CPUS']&.to_i          || 2
WORKER_MEMORY         = ENV['WORKER_MEMORY']&.to_i        || 4096
WORKER_COUNT          = ENV['WORKER_COUNT']&.to_i         || 1

PUBLIC_NETWORK_BRIDGE = [
  "Intel(R) Wi-Fi 6E AX211 160MHz",
  "Wi-Fi",
  "WiFi",
  "Wireless",
  "wlan0",
  "en0"
]

# name: used for hostnames/VM names/kubeconfig context names.
# subnet: second octet under NETWORK_BASE, e.g. 10 -> 10.20.10.0/24
CLUSTERS = [
  { name: 'dvb-argocd-management',         subnet: 10 },
  { name: 'dvb-argocd-development',        subnet: 20 },
  { name: 'dvb-argocd-staging',            subnet: 30 },
  { name: 'dvb-argocd-production-east',    subnet: 40 },
  { name: 'dvb-argocd-production-central', subnet: 50 },
  { name: 'dvb-argocd-production-west',    subnet: 60 },
]

MANAGEMENT_CLUSTER_NAME = 'dvb-argocd-management'

# Optional filter: CLUSTERS_TO_CREATE='dvb-argocd-management,dvb-argocd-staging'
active_clusters =
  if ENV['CLUSTERS_TO_CREATE'] && !ENV['CLUSTERS_TO_CREATE'].strip.empty?
    wanted = ENV['CLUSTERS_TO_CREATE'].split(',').map(&:strip)
    CLUSTERS.select { |c| wanted.include?(c[:name]) }
  else
    CLUSTERS
  end

def control_plane_ip(cluster)
  "#{NETWORK_BASE}.#{cluster[:subnet]}.11"
end

def worker_ip(cluster, i)
  "#{NETWORK_BASE}.#{cluster[:subnet]}.#{20 + i}"
end

# ---------------------------------------------------------------------------
# Provisioning scripts
# ---------------------------------------------------------------------------

def common_script
  <<-SCRIPT
  # Disable swap
  swapoff -a
  sed -i '/swap/d' /etc/fstab

  # Load kernel modules
  cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

  modprobe overlay
  modprobe br_netfilter

  # Configure sysctl
  cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

  sysctl --system >/dev/null 2>&1 || true

  # Configure DNS - limit to 2 nameservers to avoid kubelet errors
  cat > /etc/resolv.conf <<EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF

  mkdir -p /etc/systemd/resolved.conf.d
  cat > /etc/systemd/resolved.conf.d/dns.conf <<EOF
[Resolve]
DNS=8.8.8.8 8.8.4.4
DNSStubListener=no
EOF

  ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf || true
  systemctl restart systemd-resolved 2>/dev/null || true

  # Install containerd
  apt-get update -qq
  apt-get install -y apt-transport-https ca-certificates curl software-properties-common

  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

  apt-get update -qq
  apt-get install -y containerd.io

  mkdir -p /etc/containerd
  containerd config default > /etc/containerd/config.toml
  sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
  sed -i 's|sandbox_image = ".*"|sandbox_image = "registry.k8s.io/pause:3.9"|' /etc/containerd/config.toml

  systemctl restart containerd
  systemctl enable containerd
  sleep 5

  curl -fsSL https://pkgs.k8s.io/core:/stable:/v#{KUBERNETES_VERSION}/deb/Release.key | gpg --dearmor -o /usr/share/keyrings/kubernetes-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v#{KUBERNETES_VERSION}/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list

  apt-get update -qq
  apt-get install -y kubelet kubeadm kubectl
  apt-mark hold kubelet kubeadm kubectl

  mkdir -p /etc/default
  cat > /etc/default/kubelet <<EOF
KUBELET_EXTRA_ARGS=--resolv-conf=/run/systemd/resolve/resolv.conf
EOF

  systemctl enable kubelet
  SCRIPT
end

def control_plane_provision_script(cluster)
  name = cluster[:name]
  ip   = control_plane_ip(cluster)

  <<-SCRIPT
  mkdir -p /vagrant/logs /vagrant/join-commands /vagrant/worker-tracking /vagrant/kubeconfigs

  PUBLIC_IP=$(ip -4 addr show enp0s8 2>/dev/null | grep -oP '(?<=inet\\s)\\d+(\\.\\d+){3}' || ip -4 addr show eth1 2>/dev/null | grep -oP '(?<=inet\\s)\\d+(\\.\\d+){3}')

  if [ -z "$PUBLIC_IP" ]; then
    echo "Warning: Could not detect public IP, using only private IP"
    PUBLIC_IP=""
  else
    echo "Detected public IP: $PUBLIC_IP"
  fi

  echo "Initializing Kubernetes cluster: #{name}..."
  if [ -n "$PUBLIC_IP" ]; then
    kubeadm init --pod-network-cidr=#{POD_NETWORK_CIDR} \\
      --apiserver-advertise-address=#{ip} \\
      --apiserver-cert-extra-sans=$PUBLIC_IP 2>&1 | tee /vagrant/logs/#{name}-kubeadm-init.log
  else
    kubeadm init --pod-network-cidr=#{POD_NETWORK_CIDR} \\
      --apiserver-advertise-address=#{ip} 2>&1 | tee /vagrant/logs/#{name}-kubeadm-init.log
  fi

  if [ ! -f /etc/kubernetes/admin.conf ]; then
    echo "ERROR: kubeadm init failed for #{name}! Check /vagrant/logs/#{name}-kubeadm-init.log"
    cat /vagrant/logs/#{name}-kubeadm-init.log
    exit 1
  fi

  echo "#{name}: Kubernetes cluster initialized successfully!"

  mkdir -p /root/.kube
  cp -i /etc/kubernetes/admin.conf /root/.kube/config
  chown root:root /root/.kube/config

  mkdir -p /home/vagrant/.kube
  cp -i /etc/kubernetes/admin.conf /home/vagrant/.kube/config
  chown vagrant:vagrant /home/vagrant/.kube/config
  chmod 600 /home/vagrant/.kube/config
  chmod 600 /root/.kube/config

  # Raw kubeconfig for local (this-node) use
  cp -i /etc/kubernetes/admin.conf /vagrant/#{name}-kubeconfig

  echo "#{name}: Installing Calico network plugin..."
  kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml

  echo "#{name}: Waiting for Calico to initialize..."
  sleep 45

  kubeadm token create --print-join-command > /vagrant/join-commands/#{name}-join-command.sh
  chmod +x /vagrant/join-commands/#{name}-join-command.sh

  touch /vagrant/worker-tracking/#{name}-worker-nodes-to-label.txt

  echo "#{name}: Testing connectivity to container registries..."
  curl -I https://quay.io 2>&1 | head -n 1
  curl -I https://docker.io 2>&1 | head -n 1

  # Export a renamed copy of this cluster's admin.conf so it can be merged
  # safely with other clusters' kubeconfigs (kubeadm names cluster/user/context
  # identically -- "kubernetes" / "kubernetes-admin" -- on every cluster, so
  # we rename them to be unique before they land in the shared folder).
  cp /etc/kubernetes/admin.conf /tmp/#{name}-export.conf
  sed -i "s/name: kubernetes$/name: #{name}/" /tmp/#{name}-export.conf
  sed -i "s/cluster: kubernetes$/cluster: #{name}/" /tmp/#{name}-export.conf
  sed -i "s/name: kubernetes-admin$/name: #{name}-admin/" /tmp/#{name}-export.conf
  sed -i "s/user: kubernetes-admin$/user: #{name}-admin/" /tmp/#{name}-export.conf
  sed -i "s/name: kubernetes-admin@kubernetes$/name: #{name}-admin@#{name}/" /tmp/#{name}-export.conf
  sed -i "s/current-context: kubernetes-admin@kubernetes$/current-context: #{name}-admin@#{name}/" /tmp/#{name}-export.conf
  cp /tmp/#{name}-export.conf /vagrant/kubeconfigs/#{name}.conf
  echo "#{name}: Exported kubeconfig to /vagrant/kubeconfigs/#{name}.conf"

  echo "#{name}: Kubernetes control plane initialized successfully!"
  echo "#{name}: Control plane node is ready for workers to join"

  nohup bash -c '
    echo "#{name}: Starting worker node labeling service..."
    while true; do
      if [ -f /vagrant/worker-tracking/#{name}-worker-nodes-to-label.txt ]; then
        while IFS= read -r node_name; do
          if [ ! -z "$node_name" ]; then
            kubectl label node "$node_name" node-role.kubernetes.io/worker=worker --overwrite 2>/dev/null && \
              echo "#{name}: Labeled node: $node_name" || true
          fi
        done < /vagrant/worker-tracking/#{name}-worker-nodes-to-label.txt
      fi
      sleep 10
    done
  ' > /var/log/label-workers.log 2>&1 &
  SCRIPT
end

def worker_provision_script(cluster)
  name        = cluster[:name]
  cp_ip       = control_plane_ip(cluster)

  <<-SCRIPT
  echo "#{name}: Waiting for control plane node to be ready..."
  while [ ! -f /vagrant/join-commands/#{name}-join-command.sh ]; do
    echo "#{name}: Waiting for join command..."
    sleep 5
  done

  echo "#{name}: Join command found, waiting for control plane API server to be fully ready..."
  sleep 30

  CONTROL_PLANE_IP=#{cp_ip}
  MAX_RETRIES=20
  RETRY_COUNT=0

  while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -k -s https://$CONTROL_PLANE_IP:6443/healthz > /dev/null 2>&1; then
      echo "#{name}: Control plane API server is ready!"
      break
    fi
    echo "#{name}: Control plane API server not ready yet, waiting... (attempt $((RETRY_COUNT+1))/$MAX_RETRIES)"
    sleep 10
    RETRY_COUNT=$((RETRY_COUNT+1))
  done

  if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "#{name}: Warning: Could not verify control plane API server readiness, attempting to join anyway..."
  fi

  echo "#{name}: Joining the cluster..."
  timeout 300 bash /vagrant/join-commands/#{name}-join-command.sh || {
    echo "#{name}: Join command timed out or failed, retrying in 30 seconds..."
    sleep 30
    timeout 300 bash /vagrant/join-commands/#{name}-join-command.sh
  }

  echo "#{name}: Worker node joined the cluster successfully!"

  NODE_NAME=$(hostname)
  sleep 15
  echo "$NODE_NAME" >> /vagrant/worker-tracking/#{name}-worker-nodes-to-label.txt

  echo "#{name}: Worker node setup complete!"
  SCRIPT
end

def merge_kubeconfigs_script
  <<-SCRIPT
  mkdir -p /home/vagrant/.kube

  FILES=$(ls /vagrant/kubeconfigs/*.conf 2>/dev/null | tr '\\n' ':' | sed 's/:$//')

  if [ -z "$FILES" ]; then
    echo "No kubeconfig files found in /vagrant/kubeconfigs -- have the other clusters finished provisioning?"
    exit 1
  fi

  echo "Merging kubeconfigs: $FILES"
  KUBECONFIG="$FILES" kubectl config view --flatten > /tmp/merged-config
  cp /tmp/merged-config /home/vagrant/.kube/config
  chown vagrant:vagrant /home/vagrant/.kube/config
  chmod 600 /home/vagrant/.kube/config

  echo "Available contexts:"
  KUBECONFIG=/home/vagrant/.kube/config kubectl config get-contexts

  KUBECONFIG=/home/vagrant/.kube/config kubectl config use-context #{MANAGEMENT_CLUSTER_NAME} 2>/dev/null || true
  echo "Merged kubeconfig written to /home/vagrant/.kube/config on this node."
  SCRIPT
end

# ---------------------------------------------------------------------------
# Vagrant configuration
# ---------------------------------------------------------------------------

Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/jammy64"
  config.vm.box_check_update = false
  config.ssh.insert_key = false
  config.vm.boot_timeout = 900
  config.ssh.connect_timeout = 120

  active_clusters.each do |cluster|
    name  = cluster[:name]
    cp_ip = control_plane_ip(cluster)

    # --- Control plane ---
    config.vm.define "#{name}-control-plane", primary: (name == MANAGEMENT_CLUSTER_NAME) do |node|
      node.vm.hostname = "#{name}-control-plane"

      node.vm.network "public_network", bridge: PUBLIC_NETWORK_BRIDGE
      node.vm.network "private_network", ip: cp_ip, netmask: NETMASK

      node.vm.provider "virtualbox" do |vb|
        vb.name = "#{name}-control-plane"
        vb.cpus = CONTROL_PLANE_CPUS
        vb.memory = CONTROL_PLANE_MEMORY
        vb.gui = false
        vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
        vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
        vb.customize ["modifyvm", :id, "--nictype1", "virtio"]
      end

      node.vm.provision "shell", inline: <<-SHELL
        export DEBIAN_FRONTEND=noninteractive
        hostnamectl set-hostname #{name}-control-plane
        echo "#{cp_ip} #{name}-control-plane.local #{name}-control-plane" >> /etc/hosts
      SHELL

      node.vm.provision "shell", inline: common_script
      node.vm.provision "shell", inline: control_plane_provision_script(cluster)

      # Manual-only: run after ALL desired clusters are up to pull every
      # cluster's kubeconfig onto the management node.
      if name == MANAGEMENT_CLUSTER_NAME
        node.vm.provision "shell", name: "merge-kubeconfigs", run: "never", inline: merge_kubeconfigs_script
      end
    end

    # --- Workers ---
    (1..WORKER_COUNT).each do |i|
      w_ip = worker_ip(cluster, i)

      config.vm.define "#{name}-worker-#{i}" do |node|
        node.vm.hostname = "#{name}-worker-#{i}"

        node.vm.network "public_network", bridge: PUBLIC_NETWORK_BRIDGE
        node.vm.network "private_network", ip: w_ip, netmask: NETMASK

        node.vm.provider "virtualbox" do |vb|
          vb.name = "#{name}-worker-#{i}"
          vb.cpus = WORKER_CPUS
          vb.memory = WORKER_MEMORY
          vb.gui = false
          vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
          vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
          vb.customize ["modifyvm", :id, "--nictype1", "virtio"]
        end

        node.vm.provision "shell", inline: <<-SHELL
          export DEBIAN_FRONTEND=noninteractive
          hostnamectl set-hostname #{name}-worker-#{i}
          echo "#{w_ip} #{name}-worker-#{i}.local #{name}-worker-#{i}" >> /etc/hosts
        SHELL

        node.vm.provision "shell", inline: common_script
        node.vm.provision "shell", inline: worker_provision_script(cluster)
      end
    end
  end
end