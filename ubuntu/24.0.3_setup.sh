#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  Battlefield 1942 Linux Server - All-in-One Setup Script
#
#  Purpose:
#    Provision a secure, dedicated environment for BF1942 on modern
#    Debian/Ubuntu systems. This script handles user creation, dependency
#    resolution (i386/legacy), and server installation via tarball.
#
#  Target OS: Ubuntu 24.04 LTS (and similar Debian-based distros)
#
#  Author: OWLCAT (https://github.com/hootmeow / wwww.bf1942.online)
# ---------------------------------------------------------------------------

set -euo pipefail

# ------------------------------------------------------------
# CONFIGURATION
# ------------------------------------------------------------
BF_USER="bf1942_user"
BF_HOME="/home/${BF_USER}"
BF_ROOT="${BF_HOME}/bf1942"
# Note: You can change this URL to a custom mirror if needed.
# If hosting yourself, ensure the tar structure matches the official one.
SERVER_TAR_URL="https://files.bf1942.online/server/linux/linux-bf1942-server.tar"
SUDOERS_FILE="/etc/sudoers.d/${BF_USER}"
SERVICE_FILE="/etc/systemd/system/bf1942.service"

# Visual helpers
log_info() { echo -e "\e[34m[INFO]\e[0m $1"; }
log_success() { echo -e "\e[32m[OK]\e[0m $1"; }
log_warn() { echo -e "\e[33m[WARN]\e[0m $1"; }

# ------------------------------------------------------------
# 1) User Management
# ------------------------------------------------------------
log_info "Configuring service user: ${BF_USER}..."

if id "$BF_USER" >/dev/null 2>&1; then
    log_info "User ${BF_USER} already exists. Skipping creation."
else
    useradd -m -s /bin/bash "$BF_USER"
    log_success "User created."
    
    echo ""
    log_warn "You must set a password for ${BF_USER} to allow manual login."
    passwd "$BF_USER"
fi

# Ensure root directory exists
mkdir -p "$BF_ROOT"

# ------------------------------------------------------------
# 2) Dependencies (i386 Multiarch & Legacy Libs)
# ------------------------------------------------------------
log_info "Configuring system dependencies..."

# Enable 32-bit architecture
dpkg --add-architecture i386
apt-get update -y

# Install modern 32-bit support libraries
log_info "Installing modern 32-bit libraries..."
apt-get install -y --no-install-recommends \
    libc6:i386 libstdc++6:i386 libgcc-s1:i386 \
    zlib1g:i386 libcurl4t64:i386 libxext6:i386 \
    libx11-6:i386 libncurses6:i386 wget tar

# Install legacy libraries required by the 2003 binaries
# If you are hosting these on your own server, update the URL/logic here.
log_info "Fetching and installing legacy Debian libraries..."
TEMP_DIR=$(mktemp -d)
pushd "$TEMP_DIR" > /dev/null

DEB_NCURSES="http://deb.debian.org/debian/pool/main/n/ncurses"
DEB_GCC="http://deb.debian.org/debian/pool/main/g/gcc-3.3"

wget -q "${DEB_NCURSES}/libtinfo5_6.2+20201114-2+deb11u2_i386.deb"
wget -q "${DEB_NCURSES}/libncurses5_6.2+20201114-2+deb11u2_i386.deb"
wget -q "${DEB_GCC}/libstdc++5_3.3.6-34_i386.deb"

dpkg -i libtinfo5*.deb libncurses5*.deb libstdc++5*.deb || true
ldconfig

popd > /dev/null
rm -rf "$TEMP_DIR"
log_success "Dependencies installed."

# ------------------------------------------------------------
# 3) Server Installation (Tarball Extraction)
# ------------------------------------------------------------
log_info "Downloading and installing Server files..."

# FIX APPLIED HERE: --strip-components=1 removes the top-level folder
wget -qO- "$SERVER_TAR_URL" | tar -x --strip-components=1 -C "$BF_ROOT"

log_success "Files extracted to ${BF_ROOT}"

# ------------------------------------------------------------
# 4) Post-Install Configuration (Symlinks & Permissions)
# ------------------------------------------------------------
log_info "Configuring file permissions and links..."

cd "$BF_ROOT"

# Create Symlink: bf1942_lnxded -> bf1942_lnxded.dynamic
if [ -f "bf1942_lnxded.dynamic" ]; then
    ln -sf bf1942_lnxded.dynamic bf1942_lnxded
    log_success "Symlink created: bf1942_lnxded -> bf1942_lnxded.dynamic"
else
    # If this fails now, it means the extraction failed completely
    log_warn "bf1942_lnxded.dynamic not found. Check tarball content."
    exit 1
fi

# Set executable permissions
chmod +x start.sh bf1942_lnxded.dynamic bf1942_lnxded.static

# Ensure correct ownership for the entire directory tree
# (This fixes the root ownership issue you saw in your ls -l output)
chown -R "${BF_USER}:${BF_USER}" "${BF_HOME}"

# ------------------------------------------------------------
# 5) Systemd Service Setup
# ------------------------------------------------------------
log_info "Installing Systemd Service..."

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Battlefield 1942 Dedicated Server
After=network.target

[Service]
Type=simple
WorkingDirectory=${BF_ROOT}
Environment=TERM=xterm
ExecStart=/bin/bash ${BF_ROOT}/start.sh +game BF1942 +statusMonitor 1
Restart=on-failure
RestartSec=5
User=${BF_USER}
Group=${BF_USER}

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable bf1942.service || true
log_success "Systemd unit created: bf1942.service"

# ------------------------------------------------------------
# 6) Sudoers Configuration
# ------------------------------------------------------------
log_info "Configuring limited sudo access for service management..."

cat > "$SUDOERS_FILE" <<EOF
# Battlefield 1942 Server Management
${BF_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl start bf1942.service
${BF_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop bf1942.service
${BF_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart bf1942.service
${BF_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl status bf1942.service
${BF_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl status bf1942.service -l
${BF_USER} ALL=(ALL) NOPASSWD: /usr/bin/journalctl -u bf1942.service
EOF

chmod 440 "$SUDOERS_FILE"
log_success "Sudoers configured."

# ------------------------------------------------------------
# 7) Final Summary
# ------------------------------------------------------------
echo ""
echo "=================================================="
echo "   Battlefield 1942 Server Installation Complete"
echo "=================================================="
echo " Install Location : ${BF_ROOT}"
echo " Service User     : ${BF_USER}"
echo ""
echo " To start the server:"
echo "   sudo systemctl start bf1942.service"
echo ""
echo " To check status:"
echo "   sudo systemctl status bf1942.service"
echo ""
echo " To manage as ${BF_USER}:"
echo "   su - ${BF_USER}"
echo "   sudo systemctl restart bf1942.service"
echo "=================================================="