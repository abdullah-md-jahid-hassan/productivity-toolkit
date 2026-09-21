#!/bin/bash
# Usage: sudo bash delete_user.sh <username> [username2] ...

# Guard against sourcing
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    echo "Do not source this script. Run it directly: sudo bash delete_user.sh <username>"
    return 1
fi

set -uo pipefail

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

ok()      { echo -e "${GREEN}[ OK ]${NC} $*"; }
info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERR ]${NC} $*" >&2; }
header()  { echo -e "\n${BOLD}${CYAN}━━━ $* ━━━${NC}"; }
divider() { echo -e "${CYAN}────────────────────────────────────────${NC}"; }

# ─── Root check ───────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    error "Run this script as root: sudo bash delete_user.sh <username>"
    exit 1
fi

if [[ $# -eq 0 ]]; then
    error "Usage: sudo bash delete_user.sh <username> [username2] ..."
    exit 1
fi

# ─── Remove a specific public key from an authorized_keys file ────────────────
remove_key_from_file() {
    local pubkey="$1"
    local auth_file="$2"

    [[ -f "$auth_file" ]] || return 0

    if grep -qF "$pubkey" "$auth_file" 2>/dev/null; then
        local tmpfile
        tmpfile=$(mktemp)
        grep -vF "$pubkey" "$auth_file" > "$tmpfile" || true
        mv "$tmpfile" "$auth_file"
        chmod 600 "$auth_file"
        ok "Removed key from: $auth_file"
    fi
}

# ─── Delete one user ──────────────────────────────────────────────────────────
delete_user() {
    local USERNAME="$1"

    header "Removing: $USERNAME"
    echo ""

    if ! id "$USERNAME" &>/dev/null; then
        warn "User '$USERNAME' does not exist. Skipping."
        return 0
    fi

    local USER_HOME
    USER_HOME=$(getent passwd "$USERNAME" | cut -d: -f6)

    # ── Find this user's generated public key ─────────────────────────────────
    local PUBKEY=""
    local PUBKEY_FILE="$USER_HOME/.ssh/${USERNAME}_key.pub"

    if [[ -f "$PUBKEY_FILE" ]]; then
        PUBKEY=$(cat "$PUBKEY_FILE")
        info "Found key: $PUBKEY_FILE"
    else
        warn "No generated key found at $PUBKEY_FILE — skipping key cleanup."
    fi

    # ── Remove key from root authorized_keys ──────────────────────────────────
    if [[ -n "$PUBKEY" ]]; then
        remove_key_from_file "$PUBKEY" "/root/.ssh/authorized_keys"
    fi

    # ── Remove key from every other user's authorized_keys ───────────────────
    if [[ -n "$PUBKEY" ]]; then
        while IFS= read -r auth_file; do
            # Skip the user's own home (about to be deleted anyway)
            [[ "$auth_file" == "$USER_HOME/.ssh/authorized_keys" ]] && continue
            remove_key_from_file "$PUBKEY" "$auth_file"
        done < <(find /home -maxdepth 3 -name "authorized_keys" -type f 2>/dev/null)
    fi

    # ── Remove sudoers entry ──────────────────────────────────────────────────
    if [[ -f "/etc/sudoers.d/$USERNAME" ]]; then
        rm -f "/etc/sudoers.d/$USERNAME"
        ok "Removed sudoers entry."
    fi

    # ── Delete user + home directory ──────────────────────────────────────────
    if deluser --remove-home "$USERNAME" 2>/dev/null; then
        ok "User '$USERNAME' and home directory deleted."
    else
        error "Failed to remove user '$USERNAME'."
    fi
}

# ─── Process all given usernames ──────────────────────────────────────────────
RESULTS=()

for USER in "$@"; do
    delete_user "$USER"
    RESULTS+=("$USER")
done

# ─── Summary ──────────────────────────────────────────────────────────────────
header "Cleanup Complete"
echo ""
divider
for USER in "${RESULTS[@]}"; do
    printf "  %-24s removed\n" "$USER"
done
divider
echo ""
