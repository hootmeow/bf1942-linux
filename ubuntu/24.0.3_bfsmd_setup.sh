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
# PRE-FLIGHT CHECKS
# ------------------------------------------------------------
# Ensure script is running with administrative privileges (sudo)
if [[ $EUID -ne 0 ]]; then
   echo -e "\e[31m[ERROR] This script requires admin privileges. Please run with sudo:\e[0m"
   echo -e "        sudo $0"
   exit 1
fi

# ------------------------------------------------------------
# CONFIGURATION
# ------------------------------------------------------------
BF_USER="bf1942_user"
BF_HOME="/home/${BF_USER}"
BF_ROOT="${BF_HOME}/bf1942"
SUDOERS_FILE="/etc/sudoers.d/${BF_USER}"
SERVICE_FILE="/etc/systemd/system/bfsmd.service"

# Visual helpers
log_info() { echo -e "\e[34m[INFO]\e[0m $1"; }
log_success() { echo -e "\e[32m[OK]\e[0m $1"; }
log_warn() { echo -e "\e[33m[WARN]\e[0m $1"; }

# ------------------------------------------------------------
# SAFETY: Cleanup Trap & Install Guard
# ------------------------------------------------------------
# Create a temporary directory safely for downloads
TEMP_DIR=$(mktemp -d)

# Cleanup function to run on exit (successful or failed)
cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
}
trap cleanup EXIT

# Check if install directory already exists and is not empty
if [ -d "$BF_ROOT" ] && [ "$(ls -A "$BF_ROOT")" ]; then
    log_warn "Target directory '$BF_ROOT' already exists and is not empty."
    read -r -p "Do you want to continue and potentially overwrite files? [y/N] " confirm
    if [[ ! "$confirm" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo "Installation aborted by user."
        exit 0
    fi
fi

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
    
    # Catch password failure (e.g. mismatch) and exit with a clear error
    if ! passwd "$BF_USER"; then
        echo ""
        echo -e "\e[31m[ERROR] Password setup failed. Script aborted.\e[0m"
        exit 1
    fi
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
log_info "Fetching and installing legacy Debian libraries..."

pushd "$TEMP_DIR" > /dev/null

DEB_NCURSES="http://deb.debian.org/debian/pool/main/n/ncurses"
DEB_GCC="http://deb.debian.org/debian/pool/main/g/gcc-3.3"

wget -q "${DEB_NCURSES}/libtinfo5_6.2+20201114-2+deb11u2_i386.deb"
wget -q "${DEB_NCURSES}/libncurses5_6.2+20201114-2+deb11u2_i386.deb"
wget -q "${DEB_GCC}/libstdc++5_3.3.6-34_i386.deb"

dpkg -i libtinfo5*.deb libncurses5*.deb libstdc++5*.deb || true
ldconfig

popd > /dev/null
log_success "Dependencies installed."

# ------------------------------------------------------------
# 3) Server Installation (Version Selection & Download)
# ------------------------------------------------------------
echo ""
echo "--------------------------------------------------"
echo " SELECT SERVER MANAGER VERSION"
echo "--------------------------------------------------"
echo " 1) BF Remote Manager v2.0 (Final)"
echo "    - Better support for special characters in player names."
echo ""
echo " 2) BF Remote Manager v2.01 (Patched)"
echo "    - Fixes unauthorized admin bugs and PunkBuster lists."
echo "    - KNOWN ISSUE: May truncate names with special characters."
echo "--------------------------------------------------"
read -r -p "Enter your choice [1 or 2]: " version_choice

case "$version_choice" in
    1)
        SERVER_TAR_URL="https://files.bf1942.online/server/linux/linux-bf1942-server-bfsm-hitreg.tar"
        log_info "Selected: v2.0 (Final)"
        ;;
    2)
        SERVER_TAR_URL="https://files.bf1942.online/server/linux/linux-bf1942-server-bfsm-hitreg-201patched.tar"
        log_info "Selected: v2.01 (Patched)"
        ;;
    *)
        echo -e "\e[33m[WARN] Invalid input. Defaulting to Option 1 (v2.0 Final).\e[0m"
        SERVER_TAR_URL="https://files.bf1942.online/server/linux/linux-bf1942-server-bfsm-hitreg.tar"
        ;;
esac

log_info "Downloading and installing Server files..."

# Extract the server files
if ! wget -qO- "$SERVER_TAR_URL" | tar -x --strip-components=1 -C "$BF_ROOT"; then
    echo -e "\e[31m[ERROR] Download or extraction failed. Check your internet connection.\e[0m"
    exit 1
fi

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
Type=forking
WorkingDirectory=${BF_ROOT}
Environment=TERM=xterm
ExecStart=${BF_ROOT}/bfsmd -path ${BF_ROOT} -ip 0.0.0.0 -port 14667 -restart -start -nodelay -daemon
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
# 8) Optional: Firewall Configuration (UFW)
# ------------------------------------------------------------
echo ""
log_info "Firewall Configuration"
read -r -p "Would you like to automatically add UFW firewall rules for BF1942? [y/N] " response

if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    log_info "Applying UFW rules..."
    
    if command -v ufw >/dev/null; then
        ufw allow 14567/udp comment 'BF1942 Game Port'
        ufw allow 23000/udp comment 'BF1942 GameSpy Query'
        ufw allow 14667/udp comment 'BFSMD Manager Port'
        
        ufw reload
        log_success "Firewall rules added for ports 14567, 23000, and 14667 (UDP)."
    else
        log_warn "UFW is not installed. Skipping firewall configuration."
    fi
else
    log_info "Skipping firewall configuration."
fi

# ------------------------------------------------------------
# 9) Service Restart (Ensure clean init)
# ------------------------------------------------------------
echo ""
log_info "Performing final service restart sequence..."
systemctl stop bfsmd.service
log_info "Waiting 5 seconds..."
sleep 5
systemctl start bfsmd.service
log_success "Service restarted."

# ------------------------------------------------------------
# 10) Final Summary
# ------------------------------------------------------------
echo ""
echo "=================================================="
echo "   Battlefield 1942 (BFSMD) Installation Complete"
echo "=================================================="
echo " Install Location : ${BF_ROOT}"
echo " Service User     : ${BF_USER}"
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