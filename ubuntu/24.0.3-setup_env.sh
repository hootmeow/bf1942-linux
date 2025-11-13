#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  Battlefield 1942 Linux Server Environment Setup Script
#
#  Purpose:
#    Prepare a modern Ubuntu/Debian-style system to run the legacy 32-bit
#    Battlefield 1942 dedicated server using a dedicated, non-privileged
#    service account.
#
#  What this script does:
#    • Creates a dedicated account: bf1942_user
#    • Prompts to set the password for that account
#    • Creates a user-owned install path: /home/bf1942_user/bf1942
#    • Enables i386 multiarch and installs required 32-bit + legacy libs
#    • Downloads the BF1942 Linux installer to a user-owned downloads folder
#    • Creates a systemd service that runs as bf1942_user
#    • Adds a limited sudoers entry so bf1942_user can manage the service
#
#  Author: OWLCAT — https://github.com/hootmeow
# ---------------------------------------------------------------------------

set -e

echo "[+] Battlefield 1942 environment setup (non-privileged runtime)"

# ------------------------------------------------------------
# CONFIGURATION
# ------------------------------------------------------------
BF_USER="bf1942_user"
BF_HOME="/home/${BF_USER}"
BF_ROOT="${BF_HOME}/bf1942"
BF_DL_DIR="${BF_ROOT}/downloads"
INSTALLER_URL="https://files.bf1942.online/server/bf1942-1.6.run"
SUDOERS_FILE="/etc/sudoers.d/${BF_USER}"

# ------------------------------------------------------------
# 1) Create dedicated user (if it doesn't exist)
# ------------------------------------------------------------
if id "$BF_USER" >/dev/null 2>&1; then
  echo "[i] Account ${BF_USER} already exists."
else
  echo "[+] Creating account ${BF_USER} ..."
  sudo useradd -m -s /bin/bash "$BF_USER"

  echo
  echo "Set a password for ${BF_USER}:"
  sudo passwd "$BF_USER"
  echo
fi

# make sure the directories exist and are owned by the service account
sudo mkdir -p "$BF_ROOT" "$BF_DL_DIR"
sudo chown -R "$BF_USER":"$BF_USER" "$BF_HOME"

# ------------------------------------------------------------
# 2) Enable i386 and install libraries
# ------------------------------------------------------------
echo "[+] Enabling i386 multiarch ..."
sudo dpkg --add-architecture i386 || true
sudo apt update -y

echo "[+] Installing 32-bit runtime libraries ..."
sudo apt install -y \
  libc6:i386 libstdc++6:i386 libgcc-s1:i386 \
  zlib1g:i386 libcurl4t64:i386 libxext6:i386 libx11-6:i386 \
  libncurses6:i386 || true

echo "[+] Installing legacy 32-bit libraries (Debian mirror) ..."
cd /tmp
DEB_NCURSES="http://deb.debian.org/debian/pool/main/n/ncurses"
DEB_GCC="http://deb.debian.org/debian/pool/main/g/gcc-3.3"

wget -q ${DEB_NCURSES}/libtinfo5_6.2+20201114-2+deb11u2_i386.deb
wget -q ${DEB_NCURSES}/libncurses5_6.2+20201114-2+deb11u2_i386.deb
wget -q ${DEB_GCC}/libstdc++5_3.3.6-34_i386.deb

sudo dpkg -i libtinfo5_6.2+20201114-2+deb11u2_i386.deb
sudo dpkg -i libncurses5_6.2+20201114-2+deb11u2_i386.deb
sudo dpkg -i libstdc++5_3.3.6-34_i386.deb || true
sudo ldconfig

# ------------------------------------------------------------
# 3) Download BF1942 installer to the user-owned dir
# ------------------------------------------------------------
echo "[+] Downloading Battlefield 1942 installer to ${BF_DL_DIR} ..."
sudo -u "$BF_USER" mkdir -p "$BF_DL_DIR"
cd "$BF_DL_DIR"
sudo -u "$BF_USER" wget -q "$INSTALLER_URL" -O gf-bf1942_lnxded-1.6-rc2.run
sudo -u "$BF_USER" chmod +x gf-bf1942_lnxded-1.6-rc2.run

# ------------------------------------------------------------
# 4) Limited sudo privileges for the service account
# ------------------------------------------------------------
echo "[+] Adding limited sudo access for ${BF_USER} ..."
sudo tee "$SUDOERS_FILE" >/dev/null <<EOF
# Battlefield 1942 Server Management
${BF_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl start bf1942.service
${BF_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop bf1942.service
${BF_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart bf1942.service
${BF_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl status bf1942.service
${BF_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl status bf1942.service -l
${BF_USER} ALL=(ALL) NOPASSWD: /usr/bin/journalctl -u bf1942.service
${BF_USER} ALL=(ALL) NOPASSWD: /usr/bin/bash /home/${BF_USER}/bf1942/*.sh
EOF
sudo chmod 440 "$SUDOERS_FILE"

# ------------------------------------------------------------
# 5) systemd unit (runs as bf1942_user)
# ------------------------------------------------------------
echo "[+] Creating systemd unit ..."
sudo tee /etc/systemd/system/bf1942.service >/dev/null <<EOF
[Unit]
Description=Battlefield 1942 Dedicated Server
After=network.target

[Service]
Type=simple
WorkingDirectory=${BF_ROOT}
Environment=TERM=xterm
ExecStart=/bin/sh ${BF_ROOT}/start.sh +game BF1942 +statusMonitor 1
Restart=on-failure
RestartSec=5
User=${BF_USER}
Group=${BF_USER}

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable bf1942.service || true

# ------------------------------------------------------------
# 6) Final info
# ------------------------------------------------------------
echo
echo "=================================================="
echo "[✅] Environment prepared at: ${BF_ROOT}"
echo
echo "Next:"
echo "1. Download the matching apply-patch script (same distro/version)."
echo "2. Switch to the game account and run the installer:"
echo "     su - ${BF_USER}"
echo "     cd ~/bf1942"
echo "     ./downloads/gf-bf1942_lnxded-1.6-rc2.run"
echo "     (install into: ${BF_ROOT})"
echo "3. Then run the apply-patch script with sudo."
echo
echo "Service management (as ${BF_USER}):"
echo "  sudo systemctl start bf1942.service"
echo "  sudo systemctl status bf1942.service -l"
echo "  sudo journalctl -u bf1942.service"
echo "=================================================="
echo
