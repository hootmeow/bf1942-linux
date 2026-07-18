#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  patch-existing-logging.sh
#
#  Enables BF1942 XML event logging on EXISTING server installs that were
#  created before the installer fix. Only these things are changed:
#
#    game.serverEventLogging 1       (in serversettings.con and, if present,
#    game.serverEventLogCompression 0     servermanager.con)
#
#  Every other setting (ports, server name, credentials, map rotation) is
#  left exactly as it is. Edited files are backed up next to the original
#  as <name>.bak-logging-<timestamp>.
#
#  Compression is forced OFF because compressed .zxml logs are flushed to
#  disk in deferred blocks - a server stop/crash can lose the whole round,
#  and stats tools want plain .xml.
#
#  Usage:
#    sudo ./patch-existing-logging.sh                  # auto-detect installs
#    sudo ./patch-existing-logging.sh /path/to/server  # patch specific dir(s)
#
#  A server root is the directory that contains mods/bf1942 (for example
#  /home/bf1942_user/bf1942 or /home/bf1942_user/instances/<name>).
#
#  Restart the server afterwards for the change to take effect:
#    standalone:      sudo systemctl restart bf1942.service
#    BFSMD instance:  sudo systemctl restart bfsmd-<name>.service
# ---------------------------------------------------------------------------

set -euo pipefail

BF_USER="bf1942_user"
BF_HOME="/home/${BF_USER}"

log_info()    { echo -e "\e[34m[INFO]\e[0m $1"; }
log_success() { echo -e "\e[32m[OK]\e[0m $1"; }
log_warn()    { echo -e "\e[33m[WARN]\e[0m $1"; }
log_error()   { echo -e "\e[31m[ERROR]\e[0m $1"; }

if [[ $EUID -ne 0 ]]; then
    log_error "Run with sudo: sudo $0 $*"
    exit 1
fi

# Set key to value in file, replacing the existing line or appending one.
set_setting() {
    local file="$1" key="$2" value="$3"
    if grep -q "^${key} " "$file"; then
        sed -i "s/^${key} .*/${key} ${value}/" "$file"
    else
        echo "${key} ${value}" >> "$file"
    fi
}

patch_install() {
    local root="$1"
    local settings="${root}/mods/bf1942/settings"

    if [ ! -d "$settings" ]; then
        log_warn "Skipping ${root}: no mods/bf1942/settings directory"
        return
    fi

    log_info "Checking ${root}"

    local stamp
    stamp=$(date +%Y%m%d-%H%M%S)
    local found_con=0

    # serversettings.con is read by the standalone server; servermanager.con
    # is the file BFSMD actually reads when it launches the game server.
    # Patch whichever exist.
    local con f
    for con in serversettings.con servermanager.con; do
        f="${settings}/${con}"
        [ -f "$f" ] || continue
        found_con=1

        if grep -q '^game.serverEventLogging 1' "$f" && \
           grep -q '^game.serverEventLogCompression 0' "$f"; then
            log_success "  ${con}: already correct"
            continue
        fi

        cp -p "$f" "${f}.bak-logging-${stamp}"
        set_setting "$f" "game.serverEventLogging" "1"
        set_setting "$f" "game.serverEventLogCompression" "0"
        log_success "  ${con}: event logging enabled (backup: ${con}.bak-logging-${stamp})"
        PATCHED_ANY=1
    done

    if [ "$found_con" -eq 0 ]; then
        log_warn "  No serversettings.con or servermanager.con found - skipped"
        return
    fi

    PATCHED_ROOTS+=("$root")
}

PATCHED_ANY=0
PATCHED_ROOTS=()

if [ "$#" -gt 0 ]; then
    for root in "$@"; do
        patch_install "$root"
    done
else
    log_info "No paths given - scanning ${BF_HOME} for installs..."
    found=0
    for root in "${BF_HOME}"/bf1942*/ "${BF_HOME}"/instances/*/; do
        [ -d "$root" ] || continue
        [ -d "${root}/mods/bf1942" ] || continue
        found=1
        patch_install "${root%/}"
    done
    if [ "$found" -eq 0 ]; then
        log_error "No installs found under ${BF_HOME}. Pass the server directory explicitly:"
        echo "       sudo $0 /path/to/server"
        exit 1
    fi
fi

echo ""
if [ "$PATCHED_ANY" -eq 1 ]; then
    log_warn "Restart the affected server(s) for the change to take effect:"
    echo "         standalone:      sudo systemctl restart bf1942.service"
    echo "         BFSMD instance:  sudo systemctl restart bfsmd-<name>.service"
    log_info "Event logs will appear as mods/<active mod>/logs/ev_<port>-<date>.xml"
    log_info "(the engine creates the logs folder itself on first start)"
else
    log_success "Nothing to change - event logging is already configured everywhere."
fi
