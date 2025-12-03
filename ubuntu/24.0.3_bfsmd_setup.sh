#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  Battlefield 1942 Linux Server - All-in-One Setup Script (BFSMD Version)
#
#  Purpose:
#    Provision a secure, dedicated environment for BF1942 on modern
#    Debian/Ubuntu systems. This script handles user creation, dependency
#    resolution (i386/legacy), and server installation via tarball.
#    It sets up 'bfsmd' (Battlefield Server Manager Daemon) as the system service.
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
SERVER_TAR_URL="https://files.bf1942.online/server/linux/linux-bf1942-server-bfsm.tar"
SUDOERS_FILE="/etc/sudoers.d/${BF_USER}"
SERVICE_FILE="/etc/systemd/system/bfsmd.service"

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

# Extract the server files, removing the top-level directory from the tarball
# (Assumes BFSMD files are included in this tarball)
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
# Added bfsmd and bfsmd.static as requested
chmod +x start.sh bf1942_lnxded.dynamic bf1942_lnxded.static fixinstall.sh bfsmd bfsmd.static

# Execute fixinstall.sh
if [ -f "fixinstall.sh" ]; then 
    log_info "Executing fixinstall.sh..."
    ./fixinstall.sh
    log_success "fixinstall.sh executed."
else
    log_warn "fixinstall.sh not found. Skipping execution."
fi

# Ensure correct ownership for the entire directory tree
chown -R "${BF_USER}:${BF_USER}" "${BF_HOME}"

# ------------------------------------------------------------
# 5) Systemd Service Setup (BFSMD)
# ------------------------------------------------------------
log_info "Installing BFSMD Systemd Service..."

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Battlefield 1942 Server Manager Daemon
After=network.target

[Service]
# BFSMD runs as a daemon using the -daemon flag, so we use Type=forking
Type=forking
WorkingDirectory=${BF_ROOT}
Environment=TERM=xterm

# Start command:
# -path: Path to the game server root
# -ip:   Bind IP (0.0.0.0 binds to all interfaces)
# -port: Game port (default 14667)
# -restart: Auto-restart the server if it crashes
# -start:   Start the server immediately
# -nodelay: Skip startup delay
# -daemon:  Run in background
ExecStart=${BF_ROOT}/bfsmd -path ${BF_ROOT} -ip 0.0.0.0 -port 14667 -restart -start -nodelay -daemon

# Restart the daemon itself if it fails
Restart=on-failure
RestartSec=5
User=${BF_USER}
Group=${BF_USER}

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable bfsmd.service || true
log_success "Systemd unit created: bfsmd.service"

# ------------------------------------------------------------
# 6) Sudoers Configuration
# ------------------------------------------------------------
log_info "Configuring limited sudo access for service management..."

cat > "$SUDOERS_FILE" <<EOF
# Battlefield 1942 Server Management (BFSMD)
${BF_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl start bfsmd.service
${BF_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop bfsmd.service
${BF_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart bfsmd.service
${BF_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl status bfsmd.service
${BF_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl status bfsmd.service -l
${BF_USER} ALL=(ALL) NOPASSWD: /usr/bin/journalctl -u bfsmd.service
EOF

chmod 440 "$SUDOERS_FILE"
log_success "Sudoers configured."

# ------------------------------------------------------------
# 7) Start Service
# ------------------------------------------------------------
log_info "Starting BFSMD Service..."
systemctl start bfsmd.service
log_success "Service started successfully."

# ------------------------------------------------------------
# 8) Final Summary
# ------------------------------------------------------------
echo ""
echo "=================================================="
echo "   Battlefield 1942 (BFSMD) Installation Complete"
echo "=================================================="
echo " Install Location : ${BF_ROOT}"
echo " Service User     : ${BF_USER}"
echo " Service Status   : RUNNING (Auto-started)"
echo ""
echo " To check status:"
echo "   sudo systemctl status bfsmd.service"
echo ""
echo " To manage as ${BF_USER}:"
echo "   su - ${BF_USER}"
echo "   sudo systemctl restart bfsmd.service"
echo " --------------------------------------------------"
echo " [WARNING] DEFAULT CONFIGURATION CREDENTIALS"
echo " --------------------------------------------------"
echo " The server is running with default manager credentials."
echo " YOU MUST CHANGE THESE IMMEDIATELY TO SECURE YOUR SERVER."
echo ""
echo " Default Username : bf1942"
echo " Default Password : battlefield"
echo ""
echo " Edit 'servermanager.con' and 'useraccess.con' in:"
echo " ${BF_ROOT}/mods/bf1942/settings/"
echo "=================================================="