#!/usr/bin/env bash

set -euo pipefail

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        log "This script must be run as root" >&2
        exit 1
    fi
}

check_os() {
    if [[ ! -f /etc/os-release ]]; then
        log "Cannot detect OS" >&2
        exit 1
    fi
    . /etc/os-release
    if [[ $ID != "ubuntu" || ${VERSION_ID%%.*} -lt 22 ]]; then
        log "Unsupported OS version: $PRETTY_NAME" >&2
        exit 1
    fi
}

check_internet() {
    if ! ping -c1 -w3 8.8.8.8 >/dev/null 2>&1; then
        log "No internet connectivity" >&2
        exit 1
    fi
    if ! getent hosts kubernetes.io >/dev/null 2>&1; then
        log "DNS resolution failed" >&2
        exit 1
    fi
}

check_time_sync() {
    if systemctl is-active --quiet chrony; then
        return
    fi
    if systemctl is-active --quiet systemd-timesyncd; then
        return
    fi
    log "Time synchronization service not active" >&2
    exit 1
}

validate_ips() {
    local ips=( "$CONTROL_PLANE_IP" "$WORKER1_IP" "$WORKER2_IP" )
    local ip
    local seen=""
    for ip in "${ips[@]}"; do
        if ! [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            log "Invalid IP format: $ip" >&2
            exit 1
        fi
        if grep -qw "$ip" <<< "$seen"; then
            log "Duplicate IP detected: $ip" >&2
            exit 1
        fi
        seen+=" $ip"
    done
}

update_hosts() {
    local entries=(
        "$CONTROL_PLANE_IP $CONTROL_PLANE_HOSTNAME"
        "$WORKER1_IP $WORKER1_HOSTNAME"
        "$WORKER2_IP $WORKER2_HOSTNAME"
    )
    for e in "${entries[@]}"; do
        if ! grep -q "^$e" /etc/hosts; then
            echo "$e" >> /etc/hosts
        fi
    done
}

main() {
    require_root
    check_os
    check_internet
    check_time_sync
    validate_ips
    update_hosts
    log "Environment validation complete"
}

[[ ${BASH_SOURCE[0]} != "$0" ]] || main "$@"
