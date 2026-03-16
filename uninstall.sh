#!/bin/sh
set -e  # Exit on error

# Color output settings
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions (POSIX-compliant printf)
log_info() {
    printf "${GREEN}[INFO]${NC} %s\n" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1"
}

log_warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$1"
}

echo "==========================================="
echo "  AgenticSec Edge Uninstaller               "
echo "==========================================="
echo ""

# 1. Root privilege check (POSIX-compliant)
log_info "Checking root privileges..."
if [ "$(id -u)" -ne 0 ]; then
   log_error "This script must be run as root (use sudo)"
   echo "Usage: sudo sh $0"
   exit 1
fi
log_info "✓ Running as root"

# 2. Confirmation prompt
echo ""
log_warn "This will remove AgenticSec Supervisor and all related files."
log_warn "The following will be removed:"
echo "  - systemd services (agenticsec-supervisor, agenticsec-fluent-bit, agenticsec-log-cleanup)"
echo "  - Docker containers (agenticsec-supervisor, agenticsec-fluent-bit)"
echo "  - Docker images (agenticsec-supervisor, fluent/fluent-bit)"
echo "  - Docker volumes (agenticsec-fluent-bit-data)"
echo "  - Configuration files (/etc/agenticsec/)"
echo "  - Log files (/var/log/agenticsec/)"
echo "  - Utility scripts (/usr/local/bin/agenticsec-*)"
echo "  - Legacy services/files (rapidpen-*) if present"
echo ""
printf "Are you sure you want to continue? [y/N]: "
read -r CONFIRM

if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    log_info "Uninstallation cancelled"
    exit 0
fi

echo ""
log_info "Starting uninstallation..."

# 3. Stop, disable, and remove systemd services
log_info "Stopping and disabling systemd services..."

# Supervisor service
if [ -f "/etc/systemd/system/agenticsec-supervisor.service" ]; then
    systemctl stop agenticsec-supervisor 2>/dev/null || true
    log_info "  Stopped agenticsec-supervisor service"

    systemctl disable agenticsec-supervisor 2>/dev/null || true
    log_info "  Disabled agenticsec-supervisor service"

    rm -f /etc/systemd/system/agenticsec-supervisor.service
    log_info "  Removed agenticsec-supervisor service file"
else
    log_warn "  agenticsec-supervisor service not found (skipping)"
fi

# Fluent Bit service
if [ -f "/etc/systemd/system/agenticsec-fluent-bit.service" ]; then
    systemctl stop agenticsec-fluent-bit 2>/dev/null || true
    log_info "  Stopped agenticsec-fluent-bit service"

    systemctl disable agenticsec-fluent-bit 2>/dev/null || true
    log_info "  Disabled agenticsec-fluent-bit service"

    rm -f /etc/systemd/system/agenticsec-fluent-bit.service
    log_info "  Removed agenticsec-fluent-bit service file"
else
    log_warn "  agenticsec-fluent-bit service not found (skipping)"
fi

# Log cleanup timer/service
if [ -f "/etc/systemd/system/agenticsec-log-cleanup.timer" ]; then
    systemctl stop agenticsec-log-cleanup.timer 2>/dev/null || true
    systemctl disable agenticsec-log-cleanup.timer 2>/dev/null || true
    log_info "  Stopped and disabled agenticsec-log-cleanup timer"

    rm -f /etc/systemd/system/agenticsec-log-cleanup.timer
    rm -f /etc/systemd/system/agenticsec-log-cleanup.service
    log_info "  Removed agenticsec-log-cleanup timer and service files"
else
    log_warn "  agenticsec-log-cleanup timer not found (skipping)"
fi

# Legacy rapidpen-* services (from before rename)
for legacy_service in rapidpen-supervisor.service rapidpen-fluent-bit.service rapidpen-log-cleanup.timer rapidpen-log-cleanup.service; do
    if [ -f "/etc/systemd/system/$legacy_service" ]; then
        systemctl stop "$legacy_service" 2>/dev/null || true
        systemctl disable "$legacy_service" 2>/dev/null || true
        rm -f "/etc/systemd/system/$legacy_service"
        log_info "  Removed legacy service: $legacy_service"
    fi
done

# Reload systemd
systemctl daemon-reload
log_info "  Systemd daemon reloaded"

# 4. Stop and remove Docker containers and images
log_info "Cleaning up Docker resources..."

if command -v docker > /dev/null 2>&1; then
    # Stop and remove supervisor container
    if docker ps -a 2>/dev/null | grep -q agenticsec-supervisor; then
        docker rm -f agenticsec-supervisor > /dev/null 2>&1
        log_info "  Removed agenticsec-supervisor container"
    else
        log_warn "  agenticsec-supervisor container not found (skipping)"
    fi

    # Stop and remove fluent-bit container
    if docker ps -a 2>/dev/null | grep -q agenticsec-fluent-bit; then
        docker rm -f agenticsec-fluent-bit > /dev/null 2>&1
        log_info "  Removed agenticsec-fluent-bit container"
    else
        log_warn "  agenticsec-fluent-bit container not found (skipping)"
    fi

    # Legacy rapidpen-* containers
    for legacy_container in rapidpen-supervisor rapidpen-fluent-bit; do
        if docker ps -a 2>/dev/null | grep -q "$legacy_container"; then
            docker rm -f "$legacy_container" > /dev/null 2>&1
            log_info "  Removed legacy container: $legacy_container"
        fi
    done

    # Remove supervisor image
    if docker image inspect ghcr.io/agenticsec/agenticsec-supervisor >/dev/null 2>&1; then
        # Find all tags and remove them
        docker images --format "{{.Repository}}:{{.Tag}}" | grep "ghcr.io/agenticsec/agenticsec-supervisor" | while read -r image; do
            docker rmi "$image" > /dev/null 2>&1
            log_info "  Removed Docker image: $image"
        done
    else
        log_warn "  agenticsec-supervisor image not found (skipping)"
    fi

    # Remove fluent-bit image
    if docker image inspect fluent/fluent-bit:latest >/dev/null 2>&1; then
        docker rmi fluent/fluent-bit:latest > /dev/null 2>&1
        log_info "  Removed Docker image: fluent/fluent-bit:latest"
    else
        log_warn "  fluent/fluent-bit:latest image not found (skipping)"
    fi

    # Remove fluent-bit data volume (DB persistence)
    if docker volume inspect agenticsec-fluent-bit-data >/dev/null 2>&1; then
        docker volume rm agenticsec-fluent-bit-data > /dev/null 2>&1
        log_info "  Removed Docker volume: agenticsec-fluent-bit-data"
    else
        log_warn "  agenticsec-fluent-bit-data volume not found (skipping)"
    fi

    # Legacy rapidpen-fluent-bit-data volume
    if docker volume inspect rapidpen-fluent-bit-data >/dev/null 2>&1; then
        docker volume rm rapidpen-fluent-bit-data > /dev/null 2>&1
        log_info "  Removed legacy volume: rapidpen-fluent-bit-data"
    fi
else
    log_warn "  Docker not found (skipping Docker cleanup)"
fi

# 5. Remove files and directories
log_info "Removing files and directories..."

# Configuration directory
if [ -d "/etc/agenticsec" ]; then
    rm -rf /etc/agenticsec
    log_info "  Removed /etc/agenticsec/"
else
    log_warn "  /etc/agenticsec/ not found"
fi

# Log directory
if [ -d "/var/log/agenticsec" ]; then
    rm -rf /var/log/agenticsec
    log_info "  Removed /var/log/agenticsec/"
else
    log_warn "  /var/log/agenticsec/ not found"
fi

# Upgrade check script
if [ -f "/usr/local/bin/agenticsec-supervisor-check-upgrade.sh" ]; then
    rm -f /usr/local/bin/agenticsec-supervisor-check-upgrade.sh
    log_info "  Removed /usr/local/bin/agenticsec-supervisor-check-upgrade.sh"
else
    log_warn "  /usr/local/bin/agenticsec-supervisor-check-upgrade.sh not found"
fi

# Log cleanup script
if [ -f "/usr/local/bin/agenticsec-log-cleanup.sh" ]; then
    rm -f /usr/local/bin/agenticsec-log-cleanup.sh
    log_info "  Removed /usr/local/bin/agenticsec-log-cleanup.sh"
else
    log_warn "  /usr/local/bin/agenticsec-log-cleanup.sh not found"
fi

# Uninstall command itself
if [ -f "/usr/bin/agenticsec-uninstall" ]; then
    rm -f /usr/bin/agenticsec-uninstall
    log_info "  Removed /usr/bin/agenticsec-uninstall"
else
    log_warn "  /usr/bin/agenticsec-uninstall not found"
fi

# Legacy rapidpen paths
for legacy_dir in /etc/rapidpen /var/log/rapidpen; do
    if [ -d "$legacy_dir" ]; then
        rm -rf "$legacy_dir"
        log_info "  Removed $legacy_dir/"
    fi
done
for legacy_file in /usr/local/bin/rapidpen-supervisor-check-upgrade.sh /usr/local/bin/rapidpen-log-cleanup.sh /usr/bin/rapidpen-uninstall; do
    if [ -f "$legacy_file" ]; then
        rm -f "$legacy_file"
        log_info "  Removed $legacy_file"
    fi
done

# 6. Completion message
echo ""
echo "==========================================="
log_info "Uninstallation completed successfully!"
echo "==========================================="
echo ""
echo "AgenticSec Supervisor has been removed from your system."
echo "To reinstall, run: sudo sh install.sh"
echo ""
