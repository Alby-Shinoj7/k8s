#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="$SCRIPT_DIR/.env"

if [[ -f $ENV_FILE ]]; then
    set -o allexport
    source "$ENV_FILE"
    set +o allexport
else
    echo "Missing .env file" >&2
    exit 1
fi

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

case ${1:-} in
    init)
        "$SCRIPT_DIR/modules/validate_env.sh"
        "$SCRIPT_DIR/modules/control_plane.sh"
        export KUBEADM_TOKEN=$(kubeadm token create)
        export KUBEADM_CA_HASH=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | \
            openssl rsa -pubin -outform der 2>/dev/null | \
            openssl dgst -sha256 -hex | sed 's/^.* //')
        log "Token: $KUBEADM_TOKEN"
        log "CA Hash: $KUBEADM_CA_HASH"
        ;;
    control-plane)
        "$SCRIPT_DIR/modules/validate_env.sh"
        "$SCRIPT_DIR/modules/control_plane.sh"
        ;;
    join-workers)
        "$SCRIPT_DIR/modules/validate_env.sh"
        "$SCRIPT_DIR/modules/worker_node.sh"
        ;;
    install-cni)
        kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.2/manifests/calico.yaml
        ;;
    enable-gpu)
        "$SCRIPT_DIR/modules/gpu_enable.sh"
        ;;
    validate)
        "$SCRIPT_DIR/modules/validate_env.sh"
        kubectl get nodes -o wide
        ;;
    *)
        echo "Usage: $0 {init|control-plane|join-workers|install-cni|enable-gpu|validate}"
        exit 1
        ;;
esac
