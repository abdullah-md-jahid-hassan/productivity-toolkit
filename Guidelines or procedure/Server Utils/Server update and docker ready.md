# Server Update & Docker Installation Guide

Supports **Ubuntu** and **Debian**. The scripts auto-detect the OS and use the correct repository.

---

## Step 1: Remove old Docker Compose (if installed)

Older systems used `docker-compose` (v1). Remove it to avoid conflicts.

```bash
sudo rm -f /usr/local/bin/docker-compose
sudo apt remove docker-compose -y 2>/dev/null || true
```

---

## Step 2: Update system packages

```bash
sudo apt update
sudo apt upgrade -y
```

---

## Step 3: Detect OS

```bash
. /etc/os-release

OS_ID="$ID"

# Handle Ubuntu/Debian derivatives (e.g. Linux Mint, Kali, Pop!_OS)
if [[ "$OS_ID" != "ubuntu" && "$OS_ID" != "debian" ]]; then
    for parent in $ID_LIKE; do
        if [[ "$parent" == "ubuntu" || "$parent" == "debian" ]]; then
            OS_ID="$parent"
            break
        fi
    done
fi

if [[ "$OS_ID" != "ubuntu" && "$OS_ID" != "debian" ]]; then
    echo "[ERR] Unsupported OS: ${ID}. Only Ubuntu and Debian are supported."
    exit 1
fi

echo "[OK] OS detected: $OS_ID — codename: $(lsb_release -cs)"
```

---

## Step 4: Install dependencies

```bash
sudo apt install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
```

---

## Step 5: Clean up any existing Docker source files

Removes both the classic `.list` format and the newer DEB822 `.sources` format to prevent duplicate repo conflicts.

```bash
sudo rm -f /etc/apt/sources.list.d/docker.list
sudo rm -f /etc/apt/sources.list.d/docker.sources
sudo rm -f /etc/apt/keyrings/docker.gpg
```

---

## Step 6: Add Docker GPG key

```bash
curl -fsSL https://download.docker.com/linux/${OS_ID}/gpg | \
sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
```

---

## Step 7: Add Docker repository

```bash
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/${OS_ID} $(lsb_release -cs) stable" | \
sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Verify the file looks correct before installing
cat /etc/apt/sources.list.d/docker.list
```

Expected output (Debian example):
```
deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian trixie stable
```

---

## Step 8: Install Docker Engine + Compose plugin

```bash
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

---

## Step 9: Enable and start Docker

```bash
sudo systemctl enable docker
sudo systemctl start docker
```

---

## Step 10: Verify installation

```bash
docker --version
docker compose version
```

Expected output:
```
Docker version 27.x.x
Docker Compose version v2.x.x
```

---

## Step 11: Run Docker without sudo (optional)

```bash
sudo usermod -aG docker $USER
newgrp docker
docker run hello-world
```

---

# All Code Together

```bash
set -e

echo "=== Docker Installation Script (Ubuntu + Debian) ==="

# ── Step 1: Remove old Compose ────────────────────────────────────────────────
echo "[1/9] Removing old Docker Compose..."
sudo rm -f /usr/local/bin/docker-compose
sudo apt remove docker-compose -y 2>/dev/null || true

# ── Step 2: Update system ─────────────────────────────────────────────────────
echo "[2/9] Updating system packages..."
sudo apt update
sudo apt upgrade -y

# ── Step 3: Detect OS ─────────────────────────────────────────────────────────
echo "[3/9] Detecting OS..."
. /etc/os-release

OS_ID="$ID"

# Handle derivatives (Linux Mint -> ubuntu, Kali -> debian, etc.)
if [[ "$OS_ID" != "ubuntu" && "$OS_ID" != "debian" ]]; then
    for parent in $ID_LIKE; do
        if [[ "$parent" == "ubuntu" || "$parent" == "debian" ]]; then
            OS_ID="$parent"
            break
        fi
    done
fi

if [[ "$OS_ID" != "ubuntu" && "$OS_ID" != "debian" ]]; then
    echo "[ERR] Unsupported OS: ${ID}. Only Ubuntu and Debian are supported."
    exit 1
fi

CODENAME=$(lsb_release -cs)
echo "[OK] OS: $OS_ID | Codename: $CODENAME"

# ── Step 4: Install dependencies ──────────────────────────────────────────────
echo "[4/9] Installing dependencies..."
sudo apt install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings

# ── Step 5: Remove ALL existing Docker sources and keyrings ──────────────────
echo "[5/9] Cleaning all existing Docker source files and keys..."
sudo rm -f /etc/apt/sources.list.d/docker.list
sudo rm -f /etc/apt/sources.list.d/docker.sources
sudo rm -f /etc/apt/sources.list.d/docker*.list
sudo rm -f /etc/apt/sources.list.d/docker*.sources
sudo rm -f /etc/apt/keyrings/docker.gpg
sudo rm -f /etc/apt/keyrings/docker.asc
sudo sed -i '/download\.docker\.com/d' /etc/apt/sources.list

# ── Step 6: Add Docker GPG key ────────────────────────────────────────────────
echo "[6/9] Adding Docker GPG key..."
curl -fsSL https://download.docker.com/linux/${OS_ID}/gpg | \
sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# ── Step 7: Add Docker repository ─────────────────────────────────────────────
echo "[7/9] Adding Docker repository..."
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/${OS_ID} ${CODENAME} stable" | \
sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "[OK] Repo file: $(cat /etc/apt/sources.list.d/docker.list)"

# ── Step 8: Install Docker ────────────────────────────────────────────────────
echo "[8/9] Installing Docker Engine + Compose plugin..."
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# ── Step 9: Enable service + verify ───────────────────────────────────────────
echo "[9/9] Enabling Docker service..."
sudo systemctl enable docker
sudo systemctl start docker

echo ""
echo "=== Installation Complete ==="
docker --version
docker compose version
echo ""
echo "To run Docker without sudo:"
echo "  sudo usermod -aG docker \$USER && newgrp docker"
```
