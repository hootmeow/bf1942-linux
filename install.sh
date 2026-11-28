#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  Battlefield 1942 Linux Server - installer launcher
#
#  Detects your distro and runs the matching installer, downloading only
#  that one script (plus bf1942_manager.sh) - nothing else from the repo.
#
#  Usage:
#    curl -fsSLO https://raw.githubusercontent.com/hootmeow/bf1942-linux/main/install.sh
#    sudo bash install.sh [instance_name] [installer options]
#
#  Every argument is passed straight to the installer (see --help there).
#  Run from a git clone, it uses the local installers/ instead of downloading.
#
#  Environment:
#    BF1942_LINUX_REF   branch, tag or commit to download from (default: main)
# ---------------------------------------------------------------------------

set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/hootmeow/bf1942-linux"
REF="${BF1942_LINUX_REF:-main}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || pwd)"

die()  { echo "  ✖ $*" >&2; exit 1; }
info() { echo "  ▸ $*"; }

if [[ ! "$REF" =~ ^[A-Za-z0-9._/-]+$ ]]; then
    die "BF1942_LINUX_REF contains unexpected characters: $REF"
fi

[ -r /etc/os-release ] || die "Cannot detect the distro (/etc/os-release missing)."
# shellcheck source=/dev/null
. /etc/os-release
os_id="${ID:-}"
os_like=" ${ID_LIKE:-} "
os_ver="${VERSION_ID:-}"

os_major="${os_ver%%.*}"

# Ubuntu release by codename: also set by derivatives (Mint, Pop!_OS,
# Zorin, elementary ...) whose own VERSION_ID means something else.
ubuntu_installer() {
    case "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}:$1" in
        jammy:*|*:22.*)    echo "installers/ubuntu/ubu_22.04_bfsmd_setup.sh" ;;
        noble:*|*:24.*)    echo "installers/ubuntu/ubu_24.0.3_bfsmd_setup.sh" ;;
        *)                 echo "installers/ubuntu/ubu_26.04_bfsmd_setup.sh" ;;
    esac
}

# Enterprise Linux 10 dropped every 32-bit (i686) package.
el_supported() {
    if [[ "$os_major" =~ ^[0-9]+$ ]] && [ "$os_major" -ge 10 ]; then
        die "${PRETTY_NAME:-$os_id} has no 32-bit (i686) packages, so Battlefield 1942 can't run on it. Use an EL 9 release, Debian, Ubuntu, Fedora or openSUSE."
    fi
}

installer=""
case "$os_id" in
    ubuntu)                  installer="$(ubuntu_installer "$os_ver")" ;;
    debian)                  installer="installers/debian/deb_12_bfsmd_setup.sh" ;;
    fedora)                  installer="installers/fedora/fed_44_bfsmd_setup.sh" ;;
    rhel|rocky|almalinux|ol) el_supported; installer="installers/rhel/rhel_9_bfsmd_setup.sh" ;;
    centos)                  el_supported; installer="installers/centos/centos_stream9_bfsmd_setup.sh" ;;
    arch)                    installer="installers/arch/arch_bfsmd_setup.sh" ;;
    opensuse-*)              installer="installers/opensuse/opensuse_bfsmd_setup.sh" ;;
    *)
        # Derivatives: pick the closest family from ID_LIKE.
        if [[ "$os_like" == *" arch "* ]]; then
            installer="installers/arch/arch_bfsmd_setup.sh"
        elif [[ "$os_like" == *" ubuntu "* ]]; then
            installer="$(ubuntu_installer "")"
        elif [[ "$os_like" == *" debian "* ]]; then
            installer="installers/debian/deb_12_bfsmd_setup.sh"
        elif [[ "$os_like" == *" suse "* ]] || [[ "$os_like" == *" opensuse "* ]]; then
            installer="installers/opensuse/opensuse_bfsmd_setup.sh"
        elif [[ "$os_like" == *" rhel "* ]] || [[ "$os_like" == *" centos "* ]]; then
            el_supported
            installer="installers/rhel/rhel_9_bfsmd_setup.sh"
        elif [[ "$os_like" == *" fedora "* ]]; then
            installer="installers/fedora/fed_44_bfsmd_setup.sh"
        fi
        ;;
esac

[ -n "$installer" ] || die "Unsupported distro: ${PRETTY_NAME:-$os_id}. See the readme for supported systems."
info "Detected ${PRETTY_NAME:-$os_id} -> ${installer}"

script="$(basename "$installer")"
if [ -f "${HERE}/${installer}" ]; then
    # Running from a clone: use the checked-out files as-is.
    target="${HERE}/${installer}"
    info "Using local copy: ${target}"
else
    command -v curl >/dev/null 2>&1 || die "curl is required (install it with your package manager)."
    for file in "$installer" bf1942_manager.sh; do
        dest="./$(basename "$file")"
        info "Downloading $(basename "$file") (${REF})..."
        tmp="${dest}.part"
        if ! curl -fsSL --retry 2 -o "$tmp" "${REPO_RAW}/${REF}/${file}"; then
            rm -f "$tmp"
            die "Download failed: ${REPO_RAW}/${REF}/${file}"
        fi
        if ! head -1 "$tmp" | grep -q '^#!/usr/bin/env bash'; then
            rm -f "$tmp"
            die "Unexpected content downloaded for ${file} - not a bash script."
        fi
        mv -f "$tmp" "$dest"
        chmod 755 "$dest"
    done
    target="./${script}"
fi

if [[ $EUID -ne 0 ]]; then
    echo ""
    info "Installer saved. It needs root - run:"
    echo "      sudo bash ${target} $*"
    exit 0
fi

# Keep prompts interactive even when this launcher was piped into bash.
# Probe by opening /dev/tty: it exists but cannot be opened when there is
# no controlling terminal (cloud-init, CI), and --yes runs need no prompts.
if [ ! -t 0 ] && (exec < /dev/tty) 2>/dev/null; then
    exec bash "$target" "$@" < /dev/tty
fi
exec bash "$target" "$@"
