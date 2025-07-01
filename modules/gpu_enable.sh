#!/usr/bin/env bash

set -euo pipefail

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

install_nvidia_driver() {
    if command -v nvidia-smi >/dev/null 2>&1; then
        log "NVIDIA driver already installed"
        return
    fi
    apt-get update
    apt-get install -y ubuntu-drivers-common
    ubuntu-drivers autoinstall
}

install_container_runtime_hook() {
    if grep -q nvidia-container-runtime /etc/containerd/config.toml 2>/dev/null; then
        log "NVIDIA container runtime already configured"
        return
    fi
    distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
    curl -s -L https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /etc/apt/keyrings/nvidia-container-runtime-keyring.gpg
    curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | sed 's#deb https://#deb [signed-by=/etc/apt/keyrings/nvidia-container-runtime-keyring.gpg] https://#' > /etc/apt/sources.list.d/nvidia-container-runtime.list
    apt-get update
    apt-get install -y nvidia-container-toolkit
    nvidia-ctk runtime configure --runtime=containerd
    systemctl restart containerd
}

install_device_plugin() {
    if kubectl -n kube-system get ds nvidia-device-plugin >/dev/null 2>&1; then
        log "NVIDIA device plugin already installed"
        return
    fi
    kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.0/nvidia-device-plugin.yml
}

main() {
    install_nvidia_driver
    install_container_runtime_hook
    install_device_plugin
    log "GPU support enabled"
}

[[ ${BASH_SOURCE[0]} != "$0" ]] || main "$@"
