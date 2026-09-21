#!/bin/bash
# Usage: sudo bash create_user.sh

# Guard against sourcing — exit would close the SSH session
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    echo "Do not source this script. Run it directly: sudo bash create_user.sh"
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

ok()      { echo -e "${GREEN}[ OK ]${NC} $*"; }
info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERR ]${NC} $*" >&2; }
header()  { echo -e "\n${BOLD}${CYAN}━━━ $* ━━━${NC}"; }
divider() { echo -e "${CYAN}────────────────────────────────────────${NC}"; }

# ─── Root check ───────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    error "Run this script as root: sudo bash create_user.sh"
    exit 1
fi

# ─── Detect sshd policy ───────────────────────────────────────────────────────
get_sshd_value() {
    local key="$1"
    local value=""
    local files=("/etc/ssh/sshd_config")

    if [[ -d /etc/ssh/sshd_config.d ]]; then
        while IFS= read -r -d '' f; do
            files+=("$f")
        done < <(find /etc/ssh/sshd_config.d -name "*.conf" -print0 2>/dev/null | sort -z)
    fi

    for f in "${files[@]}"; do
        [[ -f "$f" ]] || continue
        local v
        v=$(grep -i "^${key}[[:space:]]" "$f" 2>/dev/null | tail -1 | awk '{print $2}')
        [[ -n "$v" ]] && value="${v,,}"
    done

    echo "$value"
}

PASSWORD_ALLOWED="unknown"
PUBKEY_ALLOWED="unknown"

if [[ -f /etc/ssh/sshd_config ]]; then
    pa=$(get_sshd_value "PasswordAuthentication")
    pka=$(get_sshd_value "PubkeyAuthentication")
    cra=$(get_sshd_value "ChallengeResponseAuthentication")
    kia=$(get_sshd_value "KbdInteractiveAuthentication")  # renamed in Ubuntu 22.04+
    pam=$(get_sshd_value "UsePAM")

    [[ -z "$pa" ]]  && pa="yes"
    [[ -z "$pka" ]] && pka="yes"

    # KbdInteractiveAuthentication is the Ubuntu 22.04+ rename of ChallengeResponseAuthentication
    [[ "$kia" == "yes" ]] && cra="yes"

    # AWS-style: PasswordAuthentication no but PAM+CRA still allows password login
    if [[ "$pa" == "no" && "$cra" == "yes" && "$pam" == "yes" ]]; then
        pa="pam"
    fi

    PASSWORD_ALLOWED="$pa"
    PUBKEY_ALLOWED="$pka"
fi

# ─── Banner ───────────────────────────────────────────────────────────────────
clear
header "Create New Server User"

echo ""
echo -e " ${BOLD}Server SSH Policy:${NC}"
divider

case "$PASSWORD_ALLOWED" in
    yes)     echo -e "  Password Auth  :  ${GREEN}Enabled${NC}" ;;
    pam)     echo -e "  Password Auth  :  ${YELLOW}Enabled via PAM${NC}" ;;
    no)      echo -e "  Password Auth  :  ${RED}Disabled${NC}" ;;
    unknown) echo -e "  Password Auth  :  ${YELLOW}Unknown (sshd_config not found)${NC}" ;;
esac

case "$PUBKEY_ALLOWED" in
    yes)     echo -e "  Key Auth       :  ${GREEN}Enabled${NC}" ;;
    no)      echo -e "  Key Auth       :  ${RED}Disabled${NC}" ;;
    unknown) echo -e "  Key Auth       :  ${YELLOW}Unknown (sshd_config not found)${NC}" ;;
esac

echo ""

# ─── Step 1: Username ─────────────────────────────────────────────────────────
header "Step 1 · Username"
echo ""
read -rp "  Enter new username: " USERNAME

if [[ -z "$USERNAME" ]]; then
    error "Username cannot be empty."
    exit 1
fi

USER_EXISTS=false
if id "$USERNAME" &>/dev/null; then
    warn "User '$USERNAME' already exists. Will configure auth only."
    USER_EXISTS=true
fi

# ─── Step 2: Group Assignment ─────────────────────────────────────────────────
header "Step 2 · Group Assignment"
echo ""

# Show well-known service groups (if present) + all user-created groups (GID >= 1000)
USEFUL_SERVICE_GROUPS="www-data docker ssl-cert adm nginx mysql redis postgresql postgres lxd certbot"
mapfile -t GROUP_NAMES < <(awk -F: -v svc="$USEFUL_SERVICE_GROUPS" '
    BEGIN { n=split(svc, s); for (i=1;i<=n;i++) want[s[i]]=1 }
    ($3 >= 1000 || $1 in want) && $1 != "nogroup" { print $1 }
' /etc/group | sort)

SELECTED_GROUP=""

if [[ ${#GROUP_NAMES[@]} -eq 0 ]]; then
    info "No relevant groups found. Skipping group selection."
else
    echo -e "  ${BOLD}Available groups:${NC}"
    echo ""
    for i in "${!GROUP_NAMES[@]}"; do
        printf "  %3d)  %s\n" "$((i+1))" "${GROUP_NAMES[$i]}"
    done
    echo ""
    echo -e "    0)  Skip (no additional group)"
    echo ""
    read -rp "  Choose group number [0-${#GROUP_NAMES[@]}]: " GROUP_CHOICE

    if [[ -z "$GROUP_CHOICE" || "$GROUP_CHOICE" == "0" ]]; then
        info "No additional group assigned."
    elif [[ "$GROUP_CHOICE" =~ ^[0-9]+$ ]] && [[ "$GROUP_CHOICE" -ge 1 ]] && [[ "$GROUP_CHOICE" -le "${#GROUP_NAMES[@]}" ]]; then
        SELECTED_GROUP="${GROUP_NAMES[$((GROUP_CHOICE - 1))]}"
        ok "Selected group: $SELECTED_GROUP"
    else
        warn "Invalid selection. Skipping group assignment."
    fi
fi

# ─── Step 3: Authentication Method ───────────────────────────────────────────
header "Step 3 · Authentication Method"
echo ""

can_password=false
can_key=false

if [[ "$PASSWORD_ALLOWED" == "yes" || "$PASSWORD_ALLOWED" == "pam" || "$PASSWORD_ALLOWED" == "unknown" ]]; then
    can_password=true
fi
if [[ "$PUBKEY_ALLOWED" == "yes" || "$PUBKEY_ALLOWED" == "unknown" ]]; then
    can_key=true
fi

declare -a AUTH_OPTIONS=()
declare -a AUTH_LABELS=()

if $can_password && $can_key; then
    AUTH_OPTIONS=("password" "key" "both")
    AUTH_LABELS=("Password only" "SSH Key only" "Password + SSH Key")
elif $can_password; then
    AUTH_OPTIONS=("password")
    AUTH_LABELS=("Password only")
elif $can_key; then
    AUTH_OPTIONS=("key")
    AUTH_LABELS=("SSH Key only")
else
    error "Server policy disallows both password and key authentication. Cannot configure login."
    exit 1
fi

echo -e "  ${BOLD}Choose authentication method:${NC}"
echo ""
for i in "${!AUTH_OPTIONS[@]}"; do
    printf "  %d)  %s\n" "$((i+1))" "${AUTH_LABELS[$i]}"
done
echo ""
read -rp "  Your choice [1-${#AUTH_OPTIONS[@]}]: " AUTH_CHOICE

if ! [[ "$AUTH_CHOICE" =~ ^[0-9]+$ ]] || [[ "$AUTH_CHOICE" -lt 1 ]] || [[ "$AUTH_CHOICE" -gt "${#AUTH_OPTIONS[@]}" ]]; then
    error "Invalid choice."
    exit 1
fi

AUTH_METHOD="${AUTH_OPTIONS[$((AUTH_CHOICE - 1))]}"

PASSWORD=""
if [[ "$AUTH_METHOD" == "password" || "$AUTH_METHOD" == "both" ]]; then
    echo ""
    while true; do
        read -rsp "  Enter password: " PASSWORD
        echo
        read -rsp "  Confirm password: " PASSWORD2
        echo
        if [[ "$PASSWORD" != "$PASSWORD2" ]]; then
            warn "Passwords do not match. Try again."
        elif [[ -z "$PASSWORD" ]]; then
            warn "Password cannot be empty."
        else
            break
        fi
    done
fi

# ─── Step 4: Docker Access ────────────────────────────────────────────────────
header "Step 4 · Docker Access"
echo ""

GRANT_DOCKER=false

if ! command -v docker &>/dev/null; then
    info "Docker is not installed on this server. Skipping."
else
    echo -e "  Docker is installed on this server."
    echo ""
    warn "Docker group grants root-equivalent access. Only grant to fully trusted developers."
    echo ""
    read -rp "  Grant Docker access to '$USERNAME'? [y/N]: " DOCKER_CHOICE
    if [[ "${DOCKER_CHOICE,,}" == "y" || "${DOCKER_CHOICE,,}" == "yes" ]]; then
        GRANT_DOCKER=true
        ok "Docker access will be granted."
    else
        info "Docker access not granted."
    fi
fi

# ─── Step 5: Service Restart Permissions ─────────────────────────────────────
header "Step 5 · Service Restart Permissions"
echo ""

SYSTEMCTL=$(command -v systemctl 2>/dev/null || echo "/usr/bin/systemctl")

# Detect installed services
CANDIDATE_SERVICES=(
    "nginx" "apache2" "mysql" "mariadb" "redis-server" "redis"
    "postgresql" "mongod" "supervisor" "php8.3-fpm" "php8.2-fpm"
    "php8.1-fpm" "php8.0-fpm" "php7.4-fpm"
)
DETECTED_SERVICES=()

for svc in "${CANDIDATE_SERVICES[@]}"; do
    if systemctl cat "${svc}.service" &>/dev/null 2>&1; then
        DETECTED_SERVICES+=("$svc")
    fi
done

ALLOWED_SERVICES=()

if [[ ${#DETECTED_SERVICES[@]} -gt 0 ]]; then
    echo -e "  ${BOLD}Detected services:${NC}"
    echo ""
    for i in "${!DETECTED_SERVICES[@]}"; do
        printf "  %3d)  %s\n" "$((i+1))" "${DETECTED_SERVICES[$i]}"
    done
    echo ""
    echo -e "    0)  None"
    echo ""
    read -rp "  Select services (comma-separated, e.g. 1,3) or 0 to skip: " SVC_INPUT

    if [[ -n "$SVC_INPUT" && "$SVC_INPUT" != "0" ]]; then
        IFS=',' read -ra SVC_NUMS <<< "$SVC_INPUT"
        for num in "${SVC_NUMS[@]}"; do
            num="${num// /}"  # trim spaces
            if [[ "$num" =~ ^[0-9]+$ ]] && [[ "$num" -ge 1 ]] && [[ "$num" -le "${#DETECTED_SERVICES[@]}" ]]; then
                ALLOWED_SERVICES+=("${DETECTED_SERVICES[$((num - 1))]}")
            fi
        done
        [[ ${#ALLOWED_SERVICES[@]} -gt 0 ]] && ok "Selected: ${ALLOWED_SERVICES[*]}"
    fi
else
    info "No common services detected on this server."
fi

echo ""
read -rp "  Add a custom service name (or press Enter to skip): " CUSTOM_SVC
if [[ -n "$CUSTOM_SVC" ]]; then
    ALLOWED_SERVICES+=("$CUSTOM_SVC")
    ok "Added custom service: $CUSTOM_SVC"
fi

# ─── Step 6: Apply Configuration ─────────────────────────────────────────────
header "Step 6 · Applying Configuration"
echo ""

# Create user
if [[ "$USER_EXISTS" == false ]]; then
    if adduser_out=$(adduser --disabled-password --gecos "" "$USERNAME" 2>&1); then
        ok "User '$USERNAME' created."
    else
        error "Failed to create user: $adduser_out"
        exit 1
    fi
fi

# Set password
if [[ "$AUTH_METHOD" == "password" || "$AUTH_METHOD" == "both" ]]; then
    if chpasswd_out=$(echo "$USERNAME:$PASSWORD" | chpasswd 2>&1); then
        ok "Password set."
    else
        error "Failed to set password: $chpasswd_out"
        warn "Server may enforce a password policy or disallow password authentication."
        warn "User created without a password. Configure auth manually if needed."
    fi
fi

# Add to selected group
if [[ -n "$SELECTED_GROUP" ]]; then
    usermod -aG "$SELECTED_GROUP" "$USERNAME"
    ok "Added to group '$SELECTED_GROUP'."
fi

# Add to docker group
if [[ "$GRANT_DOCKER" == true ]]; then
    usermod -aG docker "$USERNAME"
    ok "Added to 'docker' group."
fi

# Scoped sudoers
if [[ ${#ALLOWED_SERVICES[@]} -gt 0 ]]; then
    SUDOERS_FILE="/etc/sudoers.d/$USERNAME"
    TMPFILE=$(mktemp)

    {
        echo "# Scoped sudo permissions for $USERNAME"
        echo "# Generated by create_user.sh on $(date '+%Y-%m-%d')"
        echo ""
        for svc in "${ALLOWED_SERVICES[@]}"; do
            echo "$USERNAME ALL=(ALL) NOPASSWD: $SYSTEMCTL restart ${svc}, $SYSTEMCTL reload ${svc}, $SYSTEMCTL start ${svc}, $SYSTEMCTL stop ${svc}"
        done
    } > "$TMPFILE"

    # Validate before installing — a bad sudoers file can lock out sudo on the whole server
    if visudo -c -f "$TMPFILE" &>/dev/null; then
        mv "$TMPFILE" "$SUDOERS_FILE"
        chmod 440 "$SUDOERS_FILE"
        ok "Scoped sudoers configured for: ${ALLOWED_SERVICES[*]}"
    else
        rm -f "$TMPFILE"
        error "Sudoers syntax validation failed. Permissions not applied."
    fi
else
    info "No sudo permissions granted."
fi

# Setup SSH directory
USER_HOME=$(getent passwd "$USERNAME" | cut -d: -f6)
mkdir -p "$USER_HOME/.ssh"
chmod 700 "$USER_HOME/.ssh"

# Copy root authorized_keys if it exists (preserves existing admin access)
if [[ -f /root/.ssh/authorized_keys ]]; then
    cp /root/.ssh/authorized_keys "$USER_HOME/.ssh/authorized_keys"
    chmod 600 "$USER_HOME/.ssh/authorized_keys"
    ok "Copied root's authorized_keys."
fi

# Generate SSH key
KEY_PATH=""
if [[ "$AUTH_METHOD" == "key" || "$AUTH_METHOD" == "both" ]]; then
    KEY_NAME="${USERNAME}_key"
    KEY_PATH="$USER_HOME/.ssh/${KEY_NAME}"

    if ssh-keygen -t ed25519 -f "$KEY_PATH" -N "" -C "${USERNAME}@$(hostname)" -q 2>/dev/null; then
        # Add to new user's authorized_keys
        cat "${KEY_PATH}.pub" >> "$USER_HOME/.ssh/authorized_keys"
        chmod 600 "$USER_HOME/.ssh/authorized_keys"

        # Add to root's authorized_keys
        mkdir -p /root/.ssh
        chmod 700 /root/.ssh
        cat "${KEY_PATH}.pub" >> /root/.ssh/authorized_keys
        chmod 600 /root/.ssh/authorized_keys

        ok "SSH key generated (Ed25519)."
        ok "Saved to: ${KEY_PATH}"
        ok "Public key added to $USERNAME and root authorized_keys."
    else
        error "SSH key generation failed. The server may not support key authentication."
        KEY_PATH=""
    fi
fi

# Fix ownership
chown -R "$USERNAME:$USERNAME" "$USER_HOME/.ssh"
ok "SSH directory permissions set."

# ─── Summary ──────────────────────────────────────────────────────────────────
header "Setup Complete"
echo ""
divider

printf "  %-16s %s\n" "Username:" "$USERNAME"

GROUPS_SUMMARY=""
[[ -n "$SELECTED_GROUP" ]]    && GROUPS_SUMMARY="$SELECTED_GROUP"
[[ "$GRANT_DOCKER" == true ]] && GROUPS_SUMMARY="${GROUPS_SUMMARY:+$GROUPS_SUMMARY, }docker"
[[ -z "$GROUPS_SUMMARY" ]]    && GROUPS_SUMMARY="(none)"
printf "  %-16s %s\n" "Groups:" "$GROUPS_SUMMARY"

printf "  %-16s %s\n" "Auth:" "$AUTH_METHOD"

if [[ ${#ALLOWED_SERVICES[@]} -gt 0 ]]; then
    printf "  %-16s %s\n" "Can restart:" "${ALLOWED_SERVICES[*]}"
else
    printf "  %-16s %s\n" "Sudo:" "None"
fi

if [[ -n "$KEY_PATH" ]]; then
    printf "  %-16s %s\n" "Private key:" "$KEY_PATH"
    printf "  %-16s %s\n" "Public key:"  "${KEY_PATH}.pub"
fi

divider
echo ""

if [[ -n "$KEY_PATH" ]]; then
    warn "Download the private key to your local machine before closing this session:"
    echo -e "  ${CYAN}scp root@YOUR_SERVER_IP:$KEY_PATH ~/.ssh/${USERNAME}_key${NC}"
    echo ""
fi

echo -e "  Login: ${CYAN}ssh $USERNAME@YOUR_SERVER_IP${NC}"
echo ""
