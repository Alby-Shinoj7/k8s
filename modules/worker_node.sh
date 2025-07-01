#!/usr/bin/env bash

set -euo pipefail

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

retry_apt() {
    local tries=5
    until apt-get update && apt-get install -y "$@"; do
        ((tries--)) || { log "APT install failed"; return 1; }
        log "Retrying APT..."
        sleep 2
    done
}

install_containerd() {
    if command -v containerd >/dev/null 2>&1; then
        log "containerd already installed"
        return
    fi
    retry_apt ca-certificates curl gnupg lsb-release
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
    retry_apt containerd.io
    containerd config default | tee /etc/containerd/config.toml >/dev/null
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    systemctl restart containerd
    systemctl enable containerd
}

install_k8s() {
    if command -v kubeadm >/dev/null 2>&1; then
        log "Kubernetes packages already installed"
        return
    fi
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" > /etc/apt/sources.list.d/kubernetes.list
    retry_apt kubelet kubeadm kubectl
    apt-mark hold kubelet kubeadm kubectl
}

configure_sysctl() {
    cat <<EOF_SYS > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF_SYS
    modprobe overlay
    modprobe br_netfilter
    cat <<EOF_SYSCTL >/etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF_SYSCTL
    sysctl --system
}

disable_swap() {
    swapoff -a
    sed -i '/ swap / s/^/#/' /etc/fstab
}

join_cluster() {
    if kubectl get nodes >/dev/null 2>&1; then
        log "Node already part of a cluster"
        return
    fi
    kubeadm join "$CONTROL_PLANE_IP:6443" --token "$KUBEADM_TOKEN" --discovery-token-ca-cert-hash "$KUBEADM_CA_HASH"
}

main() {
    install_containerd
    install_k8s
    configure_sysctl
    disable_swap
    join_cluster
    log "Worker node joined"
}

[[ ${BASH_SOURCE[0]} != "$0" ]] || main "$@"
