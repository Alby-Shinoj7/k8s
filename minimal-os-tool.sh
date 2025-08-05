#!/usr/bin/env bash
# Minimal OS preparation tool
# Transforms a Linux system into a minimal, clean, hardened base image

set -euo pipefail

LOG_FILE="/var/log/minimal-os-tool.log"
DRY_RUN=0
INTERACTIVE=0
BACKUP=1

# Default package lists
REMOVE_PKGS=(
    snapd
    apport
    whoopsie
    popularity-contest
    ubuntu-release-upgrader-core
    landscape-client
    cloud-init
    lxd
    lxd-client
)
ESSENTIAL_PKGS=(
    openssh-server
    sudo
    curl
    wget
    vim
    git
    net-tools
    ca-certificates
)

# Hardening settings
SYSCTL_CONF=$(cat <<'HARDEN'
# Harden network stack
net.ipv4.ip_forward = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
HARDEN
)

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

run_cmd() {
    if [[ $DRY_RUN -eq 1 ]]; then
        log "[DRY-RUN] $*"
    else
        log "Running: $*"
        eval "$@"
    fi
}

usage() {
    cat <<USAGE
Usage: $0 [options]

Options:
  -n            Dry-run mode
  -i            Interactive mode
  -b            Disable backups
  -h            Show this help
USAGE
}

parse_args() {
    while getopts "nibh" opt; do
        case $opt in
            n) DRY_RUN=1 ;;
            i) INTERACTIVE=1 ;;
            b) BACKUP=0 ;;
            h) usage; exit 0 ;;
            *) usage; exit 1 ;;
        esac
    done
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root" >&2
        exit 1
    fi
}

preflight_checks() {
    log "--- Pre-flight checks ---"
    if ! ping -c1 -W1 8.8.8.8 >/dev/null 2>&1; then
        log "No internet connectivity" && exit 1
    fi
    if [[ $(df / | tail -1 | awk '{print $4}') -lt 1048576 ]]; then
        log "Less than 1GB free on /" && exit 1
    fi
    if command -v apt-get >/dev/null; then
        PKG_MGR="apt"
    elif command -v dnf >/dev/null; then
        PKG_MGR="dnf"
    elif command -v yum >/dev/null; then
        PKG_MGR="yum"
    else
        log "Unsupported package manager" && exit 1
    fi
    log "Package manager: $PKG_MGR"
}

backup_system() {
    [[ $BACKUP -eq 0 ]] && return
    log "--- Backup phase ---"
    run_cmd "mkdir -p /var/backups/minimal-tool"
    run_cmd "tar czf /var/backups/minimal-tool/etc-$(date +%F).tgz /etc"
    case $PKG_MGR in
        apt)
            run_cmd "dpkg --get-selections > /var/backups/minimal-tool/pkglist-$(date +%F).txt" ;;
        dnf|yum)
            run_cmd "rpm -qa > /var/backups/minimal-tool/pkglist-$(date +%F).txt" ;;
    esac
}

analysis_phase() {
    log "--- Analysis phase ---"
    run_cmd "df -h"
    run_cmd "systemctl list-unit-files --state=enabled"
}

is_installed() {
    case $PKG_MGR in
        apt) dpkg -l "$1" >/dev/null 2>&1 ;;
        dnf|yum) rpm -q "$1" >/dev/null 2>&1 ;;
    esac
}

cleanup_phase() {
    log "--- Cleanup phase ---"
    for pkg in "${REMOVE_PKGS[@]}"; do
        if is_installed "$pkg"; then
            run_cmd "$PKG_MGR -y remove $pkg"
        else
            log "$pkg not installed"
        fi
    done
    case $PKG_MGR in
        apt) run_cmd "$PKG_MGR autoremove -y && $PKG_MGR clean" ;;
        dnf|yum) run_cmd "$PKG_MGR autoremove -y" ;;
    esac
}

update_phase() {
    log "--- Update phase ---"
    case $PKG_MGR in
        apt) run_cmd "$PKG_MGR update && $PKG_MGR -y dist-upgrade" ;;
        dnf|yum) run_cmd "$PKG_MGR -y update" ;;
    esac
}

install_essentials() {
    log "--- Install essentials ---"
    for pkg in "${ESSENTIAL_PKGS[@]}"; do
        if is_installed "$pkg"; then
            log "$pkg already installed"
        else
            run_cmd "$PKG_MGR -y install $pkg"
        fi
    done
}

hardening_phase() {
    log "--- Hardening phase ---"
    run_cmd "printf '%s\n' '$SYSCTL_CONF' > /etc/sysctl.d/99-hardening.conf"
    run_cmd "sysctl --system"
    run_cmd "sed -ri 's/^#?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config"
    run_cmd "systemctl restart sshd 2>/dev/null || systemctl restart ssh"
}

final_checks() {
    log "--- Final checks ---"
    run_cmd "$PKG_MGR check"
    run_cmd "systemctl --failed || true"
    run_cmd "systemd-analyze blame || true"
    log "Completed. Reboot recommended."
}

confirm() {
    [[ $INTERACTIVE -eq 0 ]] && return
    read -rp "$1 [y/N]: " ans
    [[ ${ans:-N} =~ ^[Yy]$ ]]
}

main() {
    parse_args "$@"
    require_root
    preflight_checks
    confirm "Proceed with backup?" && backup_system
    confirm "Run analysis?" && analysis_phase
    confirm "Run cleanup?" && cleanup_phase
    confirm "Apply updates?" && update_phase
    confirm "Install essentials?" && install_essentials
    confirm "Apply hardening?" && hardening_phase
    final_checks
}

main "$@"
