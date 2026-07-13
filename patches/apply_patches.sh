#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  BF1942 Patch Helper
#
#  Applies all patches in this directory to one or all server instances.
#  Stops the service before patching and restarts it when done.
#
#  Usage:
#    sudo ./apply_patches.sh              # list available instances
#    sudo ./apply_patches.sh all          # patch every instance
#    sudo ./apply_patches.sh standalone   # patch the standalone server
#    sudo ./apply_patches.sh <name>       # patch one BFSMD instance
# ---------------------------------------------------------------------------

set -euo pipefail

BF_USER="bf1942_user"
BF_HOME="/home/${BF_USER}"
BF_STANDALONE="${BF_HOME}/bf1942"
BF_INSTANCES="${BF_HOME}/instances"
PATCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\e[34m'
CYAN='\e[36m'
BOLD='\e[1m'
NC='\e[0m'

log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_step()    { echo -e "${CYAN}${BOLD}>>>${NC} $1"; }

# ---------------------------------------------------------------------------

if [[ $EUID -ne 0 ]]; then
    log_error "This script requires root privileges. Run with sudo."
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    log_error "python3 is required but not installed."
    exit 1
fi

# Collect patch scripts (all .py files in the same directory, sorted)
mapfile -t PATCHES < <(find "$PATCH_DIR" -maxdepth 1 -name "patch_*.py" | sort)

if [ ${#PATCHES[@]} -eq 0 ]; then
    log_error "No patch scripts found in ${PATCH_DIR}"
    exit 1
fi

# ---------------------------------------------------------------------------
# Build list of available instances

declare -a INSTANCE_NAMES=()
declare -A INSTANCE_PATHS=()
declare -A INSTANCE_SERVICES=()

if [ -d "$BF_STANDALONE" ] && [ -f "/etc/systemd/system/bf1942.service" ]; then
    INSTANCE_NAMES+=("standalone")
    INSTANCE_PATHS["standalone"]="$BF_STANDALONE"
    INSTANCE_SERVICES["standalone"]="bf1942.service"
fi

if [ -d "$BF_INSTANCES" ]; then
    for dir in "$BF_INSTANCES"/*/; do
        [ -d "$dir" ] || continue
        name=$(basename "$dir")
        service="bfsmd-${name}.service"
        if [ -f "/etc/systemd/system/${service}" ]; then
            INSTANCE_NAMES+=("$name")
            INSTANCE_PATHS["$name"]="$dir"
            INSTANCE_SERVICES["$name"]="$service"
        fi
    done
fi

if [ ${#INSTANCE_NAMES[@]} -eq 0 ]; then
    log_error "No BF1942 instances found."
    exit 1
fi

# ---------------------------------------------------------------------------
# If no argument, list instances and exit

if [ $# -eq 0 ]; then
    echo ""
    echo -e "${BOLD}Available instances:${NC}"
    echo ""
    for name in "${INSTANCE_NAMES[@]}"; do
        status=$(systemctl is-active "${INSTANCE_SERVICES[$name]}" 2>/dev/null || echo "inactive")
        color="${RED}"
        [ "$status" = "active" ] && color="${GREEN}"
        printf "  ${CYAN}%-20s${NC} ${color}%s${NC}   %s\n" \
            "$name" "$status" "${INSTANCE_PATHS[$name]}"
    done
    echo ""
    echo -e "${BOLD}Patches to apply:${NC}"
    for p in "${PATCHES[@]}"; do
        echo "  $(basename "$p")"
    done
    echo ""
    echo "Usage:"
    echo "  sudo $0 all            # patch every instance"
    echo "  sudo $0 standalone     # patch standalone server"
    echo "  sudo $0 <name>         # patch one BFSMD instance"
    echo ""
    exit 0
fi

# ---------------------------------------------------------------------------
# Resolve targets

TARGET="$1"
declare -a TARGETS=()

if [ "$TARGET" = "all" ]; then
    TARGETS=("${INSTANCE_NAMES[@]}")
else
    found=0
    for name in "${INSTANCE_NAMES[@]}"; do
        if [ "$name" = "$TARGET" ]; then
            TARGETS=("$name")
            found=1
            break
        fi
    done
    if [ $found -eq 0 ]; then
        log_error "Instance '${TARGET}' not found."
        echo ""
        echo "Available instances: ${INSTANCE_NAMES[*]}"
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# Apply patches to each target

patch_instance() {
    local name="$1"
    local path="${INSTANCE_PATHS[$name]}"
    local service="${INSTANCE_SERVICES[$name]}"
    local was_running=0

    echo ""
    echo -e "${BOLD}════════════════════════════════════════${NC}"
    log_step "Patching instance: ${name}"
    echo -e "  Path:    ${CYAN}${path}${NC}"
    echo -e "  Service: ${CYAN}${service}${NC}"
    echo ""

    # Verify server binaries exist
    if [ ! -f "${path}/bf1942_lnxded.static" ] && [ ! -f "${path}/bf1942_lnxded.dynamic" ]; then
        log_error "Server binaries not found in ${path} — skipping."
        return 1
    fi

    # Stop service if running
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        was_running=1
        log_info "Stopping ${service}..."
        systemctl stop "$service"
        sleep 2
    else
        log_info "Service is not running — no need to stop."
    fi

    # Apply each patch
    local all_ok=1
    for patch in "${PATCHES[@]}"; do
        echo ""
        log_info "Applying: $(basename "$patch")"
        echo "----------------------------------------"
        if python3 "$patch" "$path"; then
            :
        else
            log_warn "Patch script exited with an error."
            all_ok=0
        fi
    done

    # Restart if it was running before
    if [ $was_running -eq 1 ]; then
        echo ""
        log_info "Restarting ${service}..."
        systemctl start "$service"
        sleep 2
        if systemctl is-active --quiet "$service"; then
            log_success "Service restarted successfully."
        else
            log_warn "Service did not restart cleanly. Check: journalctl -u ${service} -n 50"
        fi
    fi

    if [ $all_ok -eq 1 ]; then
        log_success "Done: ${name}"
    else
        log_warn "Completed with errors: ${name}"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Run

echo ""
echo -e "${BOLD}Patches to apply:${NC}"
for p in "${PATCHES[@]}"; do
    echo "  $(basename "$p")"
done
echo ""
echo -e "${BOLD}Target instance(s):${NC} ${TARGETS[*]}"
echo ""
read -r -p "Proceed? [y/N] " confirm
if [[ ! "$confirm" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    log_info "Cancelled."
    exit 0
fi

FAILED=()
for name in "${TARGETS[@]}"; do
    if ! patch_instance "$name"; then
        FAILED+=("$name")
    fi
done

echo ""
echo -e "${BOLD}════════════════════════════════════════${NC}"
if [ ${#FAILED[@]} -eq 0 ]; then
    log_success "All instances patched successfully."
else
    log_warn "Completed with errors on: ${FAILED[*]}"
fi
echo ""
