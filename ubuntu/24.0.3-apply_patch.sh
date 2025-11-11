#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  Battlefield 1942 1.61 Patch Application Script
#
#  Purpose:
#    Apply the 1.61 update to a Battlefield 1942 Linux server that was
#    installed under a dedicated service account:
#
#       /home/bf1942_user/bf1942
#
#  Notes:
#    • This script is intended to be run by a user that has sudo privileges.
#    • The setup script already added a limited sudoers entry for bf1942_user,
#      so that account can run this script with sudo.
#    • The patch tarball contains an extra layer: patched1.61/bf1942/
#      so we peel that off and drop the files directly into the install dir.
#
#  Author: OWLCAT — https://github.com/hootmeow
# ---------------------------------------------------------------------------

set -e

echo "[+] Applying Battlefield 1942 1.61 patch ..."

BF_USER="bf1942_user"
BF_ROOT="/home/${BF_USER}/bf1942"
PATCH_URL="http://137.184.167.47/patched1.61.tar"

# ------------------------------------------------------------
# 1) Confirm install directory exists
# ------------------------------------------------------------
if [ ! -d "$BF_ROOT" ]; then
  echo "[!] ${BF_ROOT} was not found."
  echo "    Make sure the BF1942 installer was run into that location first."
  exit 1
fi

# ------------------------------------------------------------
# 2) Download patch
# ------------------------------------------------------------
echo "[+] Downloading patch from ${PATCH_URL} ..."
wget -q "$PATCH_URL" -O /tmp/patched1.61.tar

# ------------------------------------------------------------
# 3) Extract to temp
# ------------------------------------------------------------
rm -rf /tmp/bfpatchtemp
mkdir -p /tmp/bfpatchtemp
tar -xf /tmp/patched1.61.tar -C /tmp/bfpatchtemp

PATCH_DIR="/tmp/bfpatchtemp/patched1.61/bf1942"
if [ ! -d "$PATCH_DIR" ]; then
  echo "[!] Expected ${PATCH_DIR} in the patch archive but it was not found."
  exit 1
fi

# ------------------------------------------------------------
# 4) Copy patched files into the live install
# ------------------------------------------------------------
echo "[+] Copying patched files into ${BF_ROOT} ..."
cp -afv "${PATCH_DIR}/." "${BF_ROOT}/"

# ------------------------------------------------------------
# 5) Restore execute permissions
# ------------------------------------------------------------
echo "[+] Restoring execute permissions ..."
chmod +x "${BF_ROOT}/bf1942_lnxded.dynamic" 2>/dev/null || true
chmod +x "${BF_ROOT}/bf1942_lnxded.static" 2>/dev/null || true
chmod +x "${BF_ROOT}/start.sh" 2>/dev/null || true

# ------------------------------------------------------------
# 6) Ensure the service account owns the files
# ------------------------------------------------------------
sudo chown -R "${BF_USER}:${BF_USER}" "${BF_ROOT}"

# ------------------------------------------------------------
# 7) Cleanup and restart info
# ------------------------------------------------------------
rm -rf /tmp/bfpatchtemp /tmp/patched1.61.tar

echo
echo "[✅] Patch applied."
echo "You can restart the server with:"
echo "  sudo systemctl restart bf1942.service"
echo "  sudo systemctl status bf1942.service -l"
echo
