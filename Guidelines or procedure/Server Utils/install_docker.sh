#!/bin/bash
# Usage: sudo bash install_docker.sh

# Guard against sourcing
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    echo "Do not source this script. Run it directly: sudo bash install_docker.sh"
    return 1
fi

set -euo pipefail

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

ok()     { echo -e "${GREEN}[ OK ]${NC} $*"; }
info()   { echo -e "${CYAN}[INFO]${NC} $*"; }
warn()   { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()  { echo -e "${RED}[ERR ]${NC} $*" >&2; }
header() { echo -e "\n${BOLD}${CYAN}━━━ $* ━━━${NC}"; }

# ─── Root check ───────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    error "Run this script as root: sudo bash install_docker.sh"
    exit 1
fi

header "Docker Installation — Ubuntu + Debian"

# ─── Step 1: Detect OS ────────────────────────────────────────────────────────
info "Detecting OS..."
. /etc/os-release

OS_ID="$ID"

# Handle derivatives (Linux Mint → ubuntu, Kali → debian, etc.)
if [[ "$OS_ID" != "ubuntu" && "$OS_ID" != "debian" ]]; then
    for parent in $ID_LIKE; do
        if [[ "$parent" == "ubuntu" || "$parent" == "debian" ]]; then
            OS_ID="$parent"
            break
        fi
    done
fi

if [[ "$OS_ID" != "ubuntu" && "$OS_ID" != "debian" ]]; then
    error "Unsupported OS: ${ID}. Only Ubuntu and Debian are supported."
    exit 1
fi

CODENAME=$(lsb_release -cs)
ok "OS: $OS_ID | Codename: $CODENAME"

# ─── Step 2: Purge ALL existing Docker sources and keys ───────────────────────
# Must happen before any apt update — conflicting entries cause apt to abort
info "Removing all existing Docker source files and keys..."

# Remove any apt source file that references docker (by content, not just filename)
grep -rl "download.docker.com" /etc/apt/sources.list.d/ 2>/dev/null | xargs -r rm -f
grep -rl "download.docker.com" /etc/apt/sources.list    2>/dev/null || true
sed -i '/download\.docker\.com/d' /etc/apt/sources.list

# Remove all docker keyrings (both .gpg and .asc formats)
rm -f /etc/apt/keyrings/docker.gpg
rm -f /etc/apt/keyrings/docker.asc

ok "Docker sources and keys cleared."

# ─── Step 3: Remove old docker-compose v1 ────────────────────────────────────
info "Removing old Docker Compose v1 (if present)..."
rm -f /usr/local/bin/docker-compose
apt remove docker-compose -y 2>/dev/null || true
ok "Done."

# ─── Step 4: Update system ────────────────────────────────────────────────────
info "Updating system packages..."
apt update
apt upgrade -y
ok "System up to date."

# ─── Step 5: Install dependencies ────────────────────────────────────────────
info "Installing dependencies..."
apt install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
ok "Dependencies ready."

# ─── Step 6: Add Docker GPG key ──────────────────────────────────────────────
info "Adding Docker GPG key for $OS_ID..."
curl -fsSL "https://download.docker.com/linux/${OS_ID}/gpg" | \
    gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
ok "GPG key added."

# ─── Step 7: Add Docker repository ───────────────────────────────────────────
info "Adding Docker repository..."
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/${OS_ID} ${CODENAME} stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null

ok "Repo: $(cat /etc/apt/sources.list.d/docker.list)"

# ─── Step 8: Install Docker Engine ───────────────────────────────────────────
info "Installing Docker Engine + Compose plugin..."
apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
ok "Docker installed."

# ─── Step 9: Enable and start service ────────────────────────────────────────
info "Enabling Docker service..."
systemctl enable docker
systemctl start docker
ok "Docker service running."

# ─── Summary ──────────────────────────────────────────────────────────────────
header "Installation Complete"
echo ""
docker --version
docker compose version
echo ""
warn "To run Docker without sudo, run:"
echo "  sudo usermod -aG docker \$USER && newgrp docker"
echo ""
