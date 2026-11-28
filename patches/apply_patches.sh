#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  BF1942 Patch Runner
#
#  Applies every patch in this folder to one, several, or all server
#  instances - no need to run each patch script by hand.
#
#    patch_*.py   binary fixes for bf1942_lnxded.static / .dynamic
#    patch-*.sh   config fixes (called as: patch-x.sh [--check] <server dir>)
#    install-*.sh optional add-ons - listed here, run separately
#
#  For each instance it first checks what is needed, then (only if something
#  will change) stops the service, backs up the server binaries, applies the
#  patches and restarts the service if it was running. Already-patched
#  instances are left alone and are not restarted.
#
#  Usage:
#    sudo ./apply_patches.sh                    # show instances + patch status
#    sudo ./apply_patches.sh all                # patch every instance
#    sudo ./apply_patches.sh <name> [<name>..]  # patch specific instances
#                                               # ('standalone' = standalone server)
#  Options:
#    --check            report status only, change nothing
#    --only <id,...>    apply only these patches (ids as listed, e.g. patch_ctf_respawn)
#    --with-recorder    also binary-patch instances that run the replay recorder
#    --yes, -y          do not ask for confirmation
#    --summary          print "<instance> <patches needed>" per line, nothing else
#                       (used by 'bf1942_manager.sh health')
# ---------------------------------------------------------------------------

set -euo pipefail

BF_USER="bf1942_user"
BF_HOME="/home/${BF_USER}"
BF_STANDALONE="${BF_HOME}/bf1942"
BF_INSTANCES="${BF_HOME}/instances"
PATCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; BLUE=$'\e[34m'
    CYAN=$'\e[36m'; BOLD=$'\e[1m'; DIM=$'\e[2m'; NC=$'\e[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; DIM=''; NC=''
fi

log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_step()    { echo -e "${CYAN}${BOLD}>>>${NC} $1"; }

usage() { sed -n '2,30p' "$0" | sed 's/^#  \{0,1\}//'; }

# ---------------------------------------------------------------------------
# Arguments

CHECK_ONLY=0
ASSUME_YES=0
WITH_RECORDER=0
SUMMARY=0
ONLY=""
declare -a REQUESTED=()

while [ $# -gt 0 ]; do
    case "$1" in
        --check)         CHECK_ONLY=1 ;;
        --yes|-y)        ASSUME_YES=1 ;;
        --with-recorder) WITH_RECORDER=1 ;;
        --summary)       SUMMARY=1 ;;
        --only)
            [ $# -ge 2 ] || { log_error "--only needs a comma-separated list of patch ids"; exit 1; }
            ONLY="$2"; shift ;;
        -h|--help)       usage; exit 0 ;;
        -*)              log_error "Unknown option: $1 (see --help)"; exit 1 ;;
        *)               REQUESTED+=("$1") ;;
    esac
    shift
done

if [[ $EUID -ne 0 ]]; then
    log_error "This script requires root privileges. Run with sudo."
    exit 1
fi

# ---------------------------------------------------------------------------
# Discover patches

declare -a BIN_PATCHES=() CONF_PATCHES=() ADDONS=()
mapfile -t BIN_PATCHES  < <(find "$PATCH_DIR" -maxdepth 1 -type f -name 'patch_*.py' | sort)
mapfile -t CONF_PATCHES < <(find "$PATCH_DIR" -maxdepth 1 -type f -name 'patch-*.sh' | sort)
mapfile -t ADDONS       < <(find "$PATCH_DIR" -maxdepth 1 -type f -name 'install-*.sh' | sort)

patch_id() { local b; b=$(basename "$1"); echo "${b%.*}"; }

# Title from the patch file's header block (first "#  Something" line).
patch_title() {
    awk '/^#  [A-Za-z]/ && !/\.(sh|py)$/ {sub(/^#  /, ""); print substr($0, 1, 70); exit}' "$1"
}

if [ -n "$ONLY" ]; then
    declare -A WANT=()
    IFS=',' read -ra want_list <<< "$ONLY"
    for w in "${want_list[@]}"; do WANT["$w"]=1; done
    filter() {
        local p
        for p in "$@"; do [ -n "${WANT[$(patch_id "$p")]:-}" ] && echo "$p"; done
        return 0
    }
    mapfile -t BIN_PATCHES  < <(filter "${BIN_PATCHES[@]}")
    mapfile -t CONF_PATCHES < <(filter "${CONF_PATCHES[@]}")
    known=" $(for p in "${BIN_PATCHES[@]}" "${CONF_PATCHES[@]}"; do patch_id "$p"; done | tr '\n' ' ')"
    for w in "${want_list[@]}"; do
        [[ "$known" == *" $w "* ]] || { log_error "Unknown patch id: $w"; exit 1; }
    done
fi

if [ ${#BIN_PATCHES[@]} -eq 0 ] && [ ${#CONF_PATCHES[@]} -eq 0 ]; then
    log_error "No patches selected/found in ${PATCH_DIR}"
    exit 1
fi
if [ "$SUMMARY" -eq 1 ] && ! command -v python3 >/dev/null 2>&1; then
    BIN_PATCHES=()   # summary: report what can be checked, don't fail
fi
if [ ${#BIN_PATCHES[@]} -gt 0 ] && ! command -v python3 >/dev/null 2>&1; then
    log_error "python3 is required for the binary patches (install it, or use --only to skip them)."
    exit 1
fi

# ---------------------------------------------------------------------------
# Discover instances

declare -a INSTANCE_NAMES=()
declare -A INSTANCE_PATHS=() INSTANCE_SERVICES=()

if [ -d "$BF_STANDALONE" ] && [ -f "/etc/systemd/system/bf1942.service" ]; then
    INSTANCE_NAMES+=("standalone")
    INSTANCE_PATHS["standalone"]="$BF_STANDALONE"
    INSTANCE_SERVICES["standalone"]="bf1942.service"
fi
if [ -d "$BF_INSTANCES" ]; then
    for dir in "$BF_INSTANCES"/*/; do
        [ -d "$dir" ] || continue
        name=$(basename "$dir")
        if [ -f "/etc/systemd/system/bfsmd-${name}.service" ]; then
            INSTANCE_NAMES+=("$name")
            INSTANCE_PATHS["$name"]="${dir%/}"
            INSTANCE_SERVICES["$name"]="bfsmd-${name}.service"
        fi
    done
fi

if [ ${#INSTANCE_NAMES[@]} -eq 0 ]; then
    [ "$SUMMARY" -eq 1 ] && exit 0
    log_error "No BF1942 instances found under ${BF_HOME}."
    exit 1
fi

# ---------------------------------------------------------------------------
# Status helpers

has_recorder() { [ -f "$1/recorder.so" ]; }

# True if any bf1942_lnxded process has this install as its working dir
# (BFSMD starts the game as ./bf1942_lnxded, so the path is not in argv).
server_running_in() {
    local pid
    for pid in $(pgrep -f bf1942_lnxded 2>/dev/null || true); do
        [ "$(readlink -f "/proc/${pid}/cwd" 2>/dev/null)" = "$(readlink -f "$1")" ] && return 0
    done
    return 1
}

# Echo one of: needed | done | mismatch | missing
binary_state() {
    local patch="$1" path="$2" out
    out=$(python3 "$patch" "$path" --check 2>&1 || true)
    if grep -q '^\[MISMATCH\]' <<< "$out"; then echo mismatch
    elif grep -q '^\[NEEDED\]' <<< "$out"; then echo needed
    elif grep -q '^\[PATCHED\]' <<< "$out"; then echo done
    else echo missing
    fi
}

conf_state() {
    local patch="$1" path="$2" out
    out=$(bash "$patch" --check "$path" 2>&1 || true)
    if grep -q 'would be patched' <<< "$out"; then echo needed
    elif grep -qi 'skip' <<< "$out"; then echo missing
    else echo done
    fi
}

state_label() {
    case "$1" in
        needed)   echo "${YELLOW}needed${NC}" ;;
        done)     echo "${GREEN}applied${NC}" ;;
        mismatch) echo "${RED}unknown build - will not apply${NC}" ;;
        missing)  echo "${DIM}n/a (files not found)${NC}" ;;
        recorder) echo "${DIM}skipped - replay recorder in use (--with-recorder)${NC}" ;;
    esac
}

# Fills NEEDED_BIN / NEEDED_CONF for an instance and prints a status table.
declare -a NEEDED_BIN=() NEEDED_CONF=()
inspect_instance() {
    local name="$1" path="${INSTANCE_PATHS[$1]}" p st
    NEEDED_BIN=(); NEEDED_CONF=()
    for p in "${BIN_PATCHES[@]}"; do
        st=$(binary_state "$p" "$path")
        if [ "$st" = needed ] && has_recorder "$path" && [ "$WITH_RECORDER" -eq 0 ]; then
            st=recorder
        fi
        [ "$st" = needed ] && NEEDED_BIN+=("$(basename "$p")")
        printf "    %-28s %s\n" "$(patch_id "$p")" "$(state_label "$st")"
    done
    for p in "${CONF_PATCHES[@]}"; do
        st=$(conf_state "$p" "$path")
        [ "$st" = needed ] && NEEDED_CONF+=("$(basename "$p")")
        printf "    %-28s %s\n" "$(patch_id "$p")" "$(state_label "$st")"
    done
}

show_catalog() {
    echo -e "${BOLD}Patches in ${PATCH_DIR}:${NC}"
    local p
    for p in "${BIN_PATCHES[@]}"; do
        printf "  %-28s %s\n" "$(patch_id "$p")" "[binary] $(patch_title "$p")"
    done
    for p in "${CONF_PATCHES[@]}"; do
        printf "  %-28s %s\n" "$(patch_id "$p")" "[config] $(patch_title "$p")"
    done
    if [ ${#ADDONS[@]} -gt 0 ]; then
        echo ""
        echo -e "${BOLD}Optional add-ons (run separately, not applied by this script):${NC}"
        for p in "${ADDONS[@]}"; do
            printf "  %-28s sudo bash %s\n" "$(basename "$p")" "$p"
        done
    fi
    echo ""
}

# ---------------------------------------------------------------------------
# Machine-readable summary

if [ "$SUMMARY" -eq 1 ]; then
    for name in "${INSTANCE_NAMES[@]}"; do
        inspect_instance "$name" >/dev/null
        echo "$name $(( ${#NEEDED_BIN[@]} + ${#NEEDED_CONF[@]} ))"
    done
    exit 0
fi

# ---------------------------------------------------------------------------
# No targets: overview

if [ ${#REQUESTED[@]} -eq 0 ]; then
    echo ""
    show_catalog
    echo -e "${BOLD}Instances:${NC}"
    for name in "${INSTANCE_NAMES[@]}"; do
        status=$(systemctl is-active "${INSTANCE_SERVICES[$name]}" 2>/dev/null || true)
        color="$RED"; [ "$status" = "active" ] && color="$GREEN"
        echo -e "  ${CYAN}${name}${NC}  ${color}${status:-inactive}${NC}  ${DIM}${INSTANCE_PATHS[$name]}${NC}"
        inspect_instance "$name"
    done
    echo ""
    echo "Usage:"
    echo "  sudo $0 all              # apply all needed patches to every instance"
    echo "  sudo $0 <name> [...]     # specific instances ('standalone' for the standalone server)"
    echo "  sudo $0 all --check      # status only"
    echo "  sudo $0 --help           # all options"
    echo ""
    exit 0
fi

# ---------------------------------------------------------------------------
# Resolve targets

declare -a TARGETS=()
for req in "${REQUESTED[@]}"; do
    if [ "$req" = "all" ]; then
        TARGETS=("${INSTANCE_NAMES[@]}")
        break
    fi
    if [ -z "${INSTANCE_PATHS[$req]:-}" ]; then
        log_error "Instance '${req}' not found. Available: ${INSTANCE_NAMES[*]}"
        exit 1
    fi
    TARGETS+=("$req")
done

# ---------------------------------------------------------------------------
# Plan

echo ""
show_catalog
declare -a TODO=()
declare -A TODO_BIN=() TODO_CONF=()
for name in "${TARGETS[@]}"; do
    echo -e "${CYAN}${name}${NC}  ${DIM}${INSTANCE_PATHS[$name]}${NC}"
    inspect_instance "$name"
    if [ ${#NEEDED_BIN[@]} -gt 0 ] || [ ${#NEEDED_CONF[@]} -gt 0 ]; then
        TODO+=("$name")
        TODO_BIN["$name"]="${NEEDED_BIN[*]:-}"
        TODO_CONF["$name"]="${NEEDED_CONF[*]:-}"
    fi
    if has_recorder "${INSTANCE_PATHS[$name]}" && [ ${#BIN_PATCHES[@]} -gt 0 ]; then
        if [ "$WITH_RECORDER" -eq 1 ]; then
            log_warn "  ${name} runs the replay recorder: binary patches change bf1942_lnxded.static,"
            log_warn "  and the recorder skips its hooks on a modified binary (recordings stop)."
        fi
    fi
done
echo ""

if [ "$CHECK_ONLY" -eq 1 ]; then
    log_info "--check given - nothing changed."
    exit 0
fi
if [ ${#TODO[@]} -eq 0 ]; then
    log_success "Everything selected is already patched - nothing to do."
    exit 0
fi

echo -e "${BOLD}Will patch:${NC} ${TODO[*]}"
echo "  Running services are stopped for the patch and started again afterwards."
if [ "$ASSUME_YES" -eq 0 ]; then
    read -r -p "Proceed? [y/N] " confirm
    if [[ ! "$confirm" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        log_info "Cancelled."
        exit 0
    fi
fi

# ---------------------------------------------------------------------------
# Apply

# .orig = the binary as it was before this runner first patched it (kept
# once); .pre-patch-<stamp> = a copy taken before every run.
backup_binaries() {
    local path="$1" stamp="$2" bin
    for bin in bf1942_lnxded.static bf1942_lnxded.dynamic; do
        [ -f "${path}/${bin}" ] || continue
        [ -e "${path}/${bin}.orig" ] || cp -p "${path}/${bin}" "${path}/${bin}.orig"
        cp -p "${path}/${bin}" "${path}/${bin}.pre-patch-${stamp}"
    done
    log_info "Backed up server binaries (*.orig, *.pre-patch-${stamp})"
}

patch_instance() {
    local name="$1" path="${INSTANCE_PATHS[$1]}" service="${INSTANCE_SERVICES[$1]}"
    local was_running=0 all_ok=1 p stamp
    local -a bins confs
    read -ra bins  <<< "${TODO_BIN[$name]}"
    read -ra confs <<< "${TODO_CONF[$name]}"
    stamp=$(date +%Y%m%d-%H%M%S)

    echo ""
    echo -e "${BOLD}════════════════════════════════════════${NC}"
    log_step "Patching ${name}  (${path})"

    if systemctl is-active --quiet "$service" 2>/dev/null; then
        was_running=1
        log_info "Stopping ${service}..."
        systemctl stop "$service"
        sleep 2
    fi

    if [ ${#bins[@]} -gt 0 ]; then
        if server_running_in "$path"; then
            log_error "A server process from ${path} is still running - skipping binary patches."
            bins=()
            all_ok=0
        else
            backup_binaries "$path" "$stamp"
        fi
    fi

    for p in "${bins[@]}"; do
        p="${PATCH_DIR}/${p}"
        log_info "Applying $(patch_id "$p")"
        if ! python3 "$p" "$path" | sed 's/^/      /'; then
            all_ok=0
        fi
        # Trust the on-disk result over the exit status.
        [ "$(binary_state "$p" "$path")" = done ] || { log_warn "$(patch_id "$p") did not apply"; all_ok=0; }
    done
    for p in "${confs[@]}"; do
        p="${PATCH_DIR}/${p}"
        log_info "Applying $(patch_id "$p")"
        if ! bash "$p" "$path" | sed 's/^/      /'; then
            all_ok=0
        fi
        [ "$(conf_state "$p" "$path")" != needed ] || { log_warn "$(patch_id "$p") did not apply"; all_ok=0; }
    done

    if [ "$was_running" -eq 1 ]; then
        log_info "Starting ${service}..."
        systemctl start "$service"
        sleep 2
        if systemctl is-active --quiet "$service"; then
            log_success "Service running again."
        else
            log_warn "Service did not start cleanly. Check: journalctl -u ${service} -n 50"
            all_ok=0
        fi
    elif [ ${#confs[@]} -gt 0 ]; then
        log_info "Config changes take effect the next time ${service} starts."
    fi

    if [ "$all_ok" -eq 1 ]; then
        log_success "Done: ${name}"
    else
        log_warn "Completed with errors: ${name}"
        return 1
    fi
}

FAILED=()
for name in "${TODO[@]}"; do
    patch_instance "$name" || FAILED+=("$name")
done

echo ""
echo -e "${BOLD}════════════════════════════════════════${NC}"
if [ ${#FAILED[@]} -eq 0 ]; then
    log_success "All selected instances patched."
    log_info "To undo a binary patch: stop the service and copy bf1942_lnxded.<type>.orig back."
else
    log_warn "Completed with errors on: ${FAILED[*]}"
    exit 1
fi
echo ""
