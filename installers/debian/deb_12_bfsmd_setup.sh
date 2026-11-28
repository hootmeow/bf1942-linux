#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  Battlefield 1942 Linux Server - Unified Setup Script (Debian)
#
#  Tested on:
#    - Debian 12 (Bookworm)
#    - Debian 13 (Trixie)
#
#  Features:
#    ✓ Smart IP detection (LAN, NAT, public scenarios)
#    ✓ Comprehensive input validation
#    ✓ CPU affinity & performance tuning
#    ✓ Multi-instance support
#    ✓ Standalone or BFSMD modes
#
#  Usage:
#    Interactive: sudo ./deb_12_bfsmd_setup.sh [instance_name]
#    Unattended:  sudo ./deb_12_bfsmd_setup.sh <instance_name> --yes [options]
#    All options: sudo ./deb_12_bfsmd_setup.sh --help
#
#  Author: OWLCAT (https://github.com/hootmeow / https://captheflag.com)
# ---------------------------------------------------------------------------

set -euo pipefail

# SHA-256 pins for downloaded server archives and legacy packages.
SERVER_SHA_STANDALONE="6b6a2fc293385636881474dff37f248b67df299431797d43050725c2f0938b8e"
SERVER_SHA_BFSMD_20="f499494d74e5301f82f71077798a531575467df95ccbe4077df99fec29ea909a"
SERVER_SHA_BFSMD_201="44eaff4270f0c3d615d47d1153acf5f26ccc67a8b9d18a7d5b74a6a860516598"
LIBSTDC5_SHA="55d14a8e77551f500b61893a006d960872a35a29229c782acfa7f8cd48d21063"
LIBTINFO5_SHA="35375adcb232873346377aa7a4ce64483ab4858d3b0ec63c7cf8ec07d12e742f"
LIBNCURSES5_SHA="80c6cae3f063fcccd5bdabc475692bbc3b0e43de5ad1e272a3d2b105cbccfc62"

verify_sha256() {
    local expected="$1" file="$2" actual
    actual=$(sha256sum "$file" 2>/dev/null | awk '{print $1}') || return 1
    [ -n "$actual" ] && [ "$actual" = "$expected" ]
}

accept_unverified_download() {
    local expected="$1" file="$2" label="$3" actual answer
    [ -s "$file" ] || return 1
    actual=$(sha256sum "$file" | awk '{print $1}')
    log_warn "SHA-256 mismatch for $label"
    log_warn "Expected: $expected"
    log_warn "Received: $actual"
    log_warn "Continuing may install or execute unreviewed third-party code."
    if [ "$ASSUME_YES" -eq 1 ]; then
        if [ "${ALLOW_UNVERIFIED_DOWNLOADS:-0}" -ne 1 ]; then
            log_error "Unattended installation stopped. --yes alone does not bypass checksums."
            return 1
        fi
        log_warn "Explicit --allow-unverified-downloads with --yes: continuing."
        return 0
    fi
    if ! read -r -p "Type UNVERIFIED to continue with this changed download: " answer; then
        log_error "Checksum override declined. Installation stopped."
        return 1
    fi
    if [ "$answer" != "UNVERIFIED" ]; then
        log_error "Checksum override declined. Installation stopped."
        return 1
    fi
    return 0
}

# These exact builds rotate off the main mirror when Debian archives an
# old release, so fall back to archive.debian.org before giving up.
fetch_legacy_deb() {
    local path="$1"
    local expected="$2"
    local file="${path##*/}"
    local primary="${file}.primary" archive="${file}.archive" candidate=""

    if wget -q -O "$primary" "https://deb.debian.org/debian/${path}"; then
        if verify_sha256 "$expected" "$primary"; then
            mv -f "$primary" "$file"
            return 0
        fi
        candidate="$primary"
    fi
    log_warn "Verified ${file} unavailable on deb.debian.org; trying archive.debian.org..."
    if wget -q -O "$archive" "https://archive.debian.org/debian/${path}"; then
        if verify_sha256 "$expected" "$archive"; then
            mv -f "$archive" "$file"
            rm -f "$primary"
            return 0
        fi
        [ -n "$candidate" ] || candidate="$archive"
    fi
    if [ -n "$candidate" ] && accept_unverified_download "$expected" "$candidate" "$file"; then
        mv -f "$candidate" "$file"
        rm -f "$primary" "$archive"
        return 0
    fi
    rm -f "$primary" "$archive"
    log_error "Could not download an accepted copy of ${file}."
    return 1
}

# Configuration
BF_USER="bf1942_user"
BF_HOME="/home/${BF_USER}"

# ------------------------------------------------------------
# TERMINAL STYLE
# Colors auto-disable when stdout is not a terminal, NO_COLOR is
# set (https://no-color.org), or the terminal cannot render them.
# ------------------------------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != "dumb" ]; then
    RED='\e[31m'; GREEN='\e[32m'; YELLOW='\e[33m'; BLUE='\e[34m'
    CYAN='\e[36m'; MAGENTA='\e[35m'; BOLD='\e[1m'; DIM='\e[2m'; NC='\e[0m'
    if [ "$(tput colors 2>/dev/null || echo 8)" -ge 256 ]; then
        # Battlefield palette: olive drab, khaki, sand, gunmetal
        C_ARMY='\e[38;5;58m'
        C_OLIVE='\e[38;5;100m'
        C_KHAKI='\e[38;5;143m'
        C_SAND='\e[38;5;180m'
        C_STEEL='\e[38;5;246m'
    else
        C_ARMY='\e[33m'; C_OLIVE='\e[32m'; C_KHAKI='\e[33m'
        C_SAND='\e[37m'; C_STEEL='\e[37m'
    fi
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; MAGENTA=''
    BOLD=''; DIM=''; NC=''
    C_ARMY=''; C_OLIVE=''; C_KHAKI=''; C_SAND=''; C_STEEL=''
fi

HR_LINE='──────────────────────────────────────────────────────────'

hr()  { echo -e "${C_OLIVE}${HR_LINE}${NC}"; }
cls() { [ -t 1 ] && clear 2>/dev/null; return 0; }

log_error()   { echo -e "  ${RED}${BOLD}✖${NC} ${RED}$1${NC}"; }
log_success() { echo -e "  ${GREEN}${BOLD}✔${NC} $1"; }
log_warn()    { echo -e "  ${YELLOW}${BOLD}⚠${NC} ${YELLOW}$1${NC}"; }
log_info()    { echo -e "  ${BLUE}${BOLD}▸${NC} $1"; }
log_step() {
    local label="$1"
    echo ""
    echo -e "${C_KHAKI}${BOLD}▶ ${label}${NC}"
    if [ -t 1 ] && [[ "$label" =~ ^([1-8])/8: ]]; then
        local current="${BASH_REMATCH[1]}"
        local filled="" empty="" i
        for ((i=0; i<8; i++)); do
            if ((i < current)); then filled+="■"; else empty+="·"; fi
        done
        echo -e "  ${C_OLIVE}[${filled}${C_STEEL}${empty}${C_OLIVE}]${NC} ${C_STEEL}MISSION PROGRESS ${current}/8${NC}"
    fi
    echo -e "${C_ARMY}${HR_LINE}${NC}"
}

# ------------------------------------------------------------
# QUIET COMMANDS
# Package-manager output goes to INSTALL_LOG and the screen gets a single
# status line with a spinner; on failure the last lines are shown.
# --verbose streams everything instead.
# ------------------------------------------------------------
INSTALL_LOG="/var/log/bf1942-install.log"
VERBOSE=0
QUIET_PID=""

run_quiet() {
    local soft=0
    if [ "${1:-}" = "--soft" ]; then
        soft=1
        shift
    fi
    local label="$1"
    shift
    local start=$SECONDS rc=0 frame=0 frames='|/-\' mark
    mark=$(wc -l < "$INSTALL_LOG" 2>/dev/null || echo 0)
    echo "=== ${label}: $*" >> "$INSTALL_LOG" 2>/dev/null || true

    if [ "$VERBOSE" -eq 1 ]; then
        log_info "${label}..."
        "$@" 2>&1 | tee -a "$INSTALL_LOG" || rc=$?
    elif [ -t 1 ]; then
        "$@" >> "$INSTALL_LOG" 2>&1 < /dev/null &
        QUIET_PID=$!
        while kill -0 "$QUIET_PID" 2>/dev/null; do
            echo -ne "\r  ${C_OLIVE}${frames:frame%4:1}${NC} ${label}... ${DIM}$((SECONDS - start))s${NC} "
            frame=$((frame + 1))
            sleep 0.2
        done
        wait "$QUIET_PID" || rc=$?
        QUIET_PID=""
        echo -ne "\r\033[K"
    else
        log_info "${label}..."
        "$@" >> "$INSTALL_LOG" 2>&1 < /dev/null || rc=$?
    fi

    if [ "$rc" -eq 0 ]; then
        log_success "${label} ($((SECONDS - start))s)"
        return 0
    fi
    if [ "$soft" -eq 1 ]; then
        log_warn "${label} - skipped (details in ${INSTALL_LOG})"
        return "$rc"
    fi
    log_error "${label} failed (exit ${rc})."
    if [ "$VERBOSE" -eq 0 ]; then
        echo "    Last output:"
        tail -n +"$((mark + 1))" "$INSTALL_LOG" 2>/dev/null | tail -n 20 | sed 's/^/      /' || true
    fi
    log_info "Full log: ${INSTALL_LOG}"
    return "$rc"
}

# ------------------------------------------------------------
# UTILITY FUNCTIONS
# ------------------------------------------------------------

# Note: Password generation removed - BFSMD uses proprietary hash format
# that cannot be generated externally. Default credentials must be used.

# First global IPv4 address; `hostname -I` is missing on some distros.
detect_local_ip() {
    local ip_addr=""
    if command -v ip >/dev/null 2>&1; then
        ip_addr=$(ip -4 addr show scope global 2>/dev/null | awk '$1=="inet"{split($2,a,"/"); print a[1]; exit}' || true)
    fi
    if [ -z "$ip_addr" ]; then
        ip_addr=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
    fi
    echo "$ip_addr"
}

detect_public_ip() {
    local ip
    ip=$(timeout 5 curl -4 -fsS https://api.ipify.org 2>/dev/null || \
         timeout 5 curl -4 -fsS https://ifconfig.me 2>/dev/null || \
         timeout 5 curl -4 -fsS https://icanhazip.com 2>/dev/null || true)
    ip=$(echo "$ip" | tr -d '[:space:]')
    if validate_ip "$ip"; then
        echo "$ip"
    fi
    return 0
}

detect_ip_addresses() {
    local local_ip public_ip
    local_ip=$(detect_local_ip)
    echo "Detecting public IP address..." >&2
    public_ip=$(detect_public_ip)
    echo "${local_ip}|${public_ip}"
}

# RFC 1918, CGNAT and loopback: players on the internet cannot reach these
# directly, so the final screen also shows the public address.
is_private_ip() {
    local a b rest
    IFS=. read -r a b rest <<< "$1"
    [ "$a" = 10 ] || [ "$a" = 127 ] ||
        { [ "$a" = 192 ] && [ "$b" = 168 ]; } ||
        { [ "$a" = 172 ] && [ "$b" -ge 16 ] && [ "$b" -le 31 ]; } ||
        { [ "$a" = 100 ] && [ "$b" -ge 64 ] && [ "$b" -le 127 ]; }
}

select_ip_address() {
    local ips=$(detect_ip_addresses)
    local local_ip=$(echo "$ips" | cut -d'|' -f1)
    local public_ip=$(echo "$ips" | cut -d'|' -f2)

    echo "" >&2
    hr >&2
    echo "   IP Address Configuration" >&2
    hr >&2
    echo "" >&2

    if [ -z "$local_ip" ]; then
        log_error "Could not detect local IP address"
        read_custom_ip
        return
    fi

    echo "Detected Network Configuration:" >&2
    echo -e "  Local IP:  ${CYAN}${local_ip}${NC}" >&2
    [ -n "$public_ip" ] && [ "$public_ip" != "$local_ip" ] && \
        echo -e "  Public IP: ${CYAN}${public_ip}${NC}" >&2
    echo "" >&2
    echo "Which IP should the server bind to?" >&2
    echo "" >&2
    echo -e "  ${BOLD}1) Local IP${NC} (${local_ip})" >&2
    echo -e "     ${BLUE}Use if:${NC} Running on LAN or behind NAT/firewall" >&2
    echo -e "     ${BLUE}Example:${NC} Home network, cloud instance behind firewall" >&2
    echo "" >&2

    if [ -n "$public_ip" ] && [ "$public_ip" != "$local_ip" ]; then
        echo -e "  ${BOLD}2) Public IP${NC} (${public_ip})" >&2
        echo -e "     ${BLUE}Use if:${NC} Server has direct public IP (no NAT)" >&2
        echo -e "     ${BLUE}Example:${NC} Dedicated server with public interface" >&2
        echo "" >&2
        echo -e "  ${BOLD}3) Custom IP${NC} (manual entry)" >&2
        echo -e "     ${BLUE}Use if:${NC} Neither option is correct or testing" >&2
        echo "" >&2
        read -r -p "Enter your choice [1-3]: " ip_choice

        case "$ip_choice" in
            1) echo "$local_ip" ;;
            2) echo "$public_ip" ;;
            3) read_custom_ip ;;
            *)
                echo "Invalid choice. Using local IP: ${local_ip}" >&2
                echo "$local_ip"
                ;;
        esac
    else
        echo -e "  ${BOLD}2) Custom IP${NC} (manual entry)" >&2
        echo -e "     ${BLUE}Use if:${NC} Detected IP is incorrect" >&2
        echo "" >&2
        read -r -p "Enter your choice [1-2]: " ip_choice

        case "$ip_choice" in
            1) echo "$local_ip" ;;
            2) read_custom_ip ;;
            *)
                echo "Invalid choice. Using local IP: ${local_ip}" >&2
                echo "$local_ip"
                ;;
        esac
    fi
}

read_custom_ip() {
    while true; do
        read -r -p "Enter IP address: " custom_ip
        if validate_ip "$custom_ip"; then
            echo "$custom_ip"
            return 0
        else
            log_error "Invalid IP address format. Please try again."
        fi
    done
}

validate_ip() {
    local ip="$1"
    local regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'

    if [[ $ip =~ $regex ]]; then
        IFS='.' read -ra octets <<< "$ip"
        for octet in "${octets[@]}"; do
            if [ "$octet" -gt 255 ]; then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

validate_instance_name() {
    local name="$1"

    if [ ${#name} -lt 3 ] || [ ${#name} -gt 20 ]; then
        log_error "Instance name must be 3-20 characters long."
        return 1
    fi

    if [[ ! "$name" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
        log_error "Instance name must start with a letter and contain only letters, numbers, dashes, and underscores."
        return 1
    fi

    local reserved_names=("default" "root" "admin" "test" "localhost" "server")
    for reserved in "${reserved_names[@]}"; do
        if [ "${name,,}" = "$reserved" ]; then
            log_error "Instance name '$name' is reserved. Please choose another."
            return 1
        fi
    done

    return 0
}

# The name shown in server browsers. Quotes and backslashes would break the
# quoted value in the .con files.
validate_server_name() {
    local n="$1"
    if [ -z "$n" ] || [ ${#n} -gt 32 ]; then
        log_error "Server name must be 1-32 characters."
        return 1
    fi
    if [[ "$n" == *'"'* ]] || [[ "$n" == *'\'* ]] || [[ "$n" =~ [[:cntrl:]] ]]; then
        log_error "Server name cannot contain quotes, backslashes or control characters."
        return 1
    fi
    return 0
}

# Value of a quoted setting, e.g. game.serverName "My Server" -> My Server
con_get_quoted() {
    local file="$1" key="${2//./\\.}"
    sed -n "s/^[[:space:]]*${key}[[:space:]][[:space:]]*\"\(.*\)\".*/\1/p" "$file" 2>/dev/null | head -1 | tr -d '\r'
}

# Set a quoted setting; the value must already be validated (no quotes).
con_set_quoted() {
    local file="$1" key="$2" value esc
    value="$3"
    esc=$(printf '%s' "$value" | sed 's/[\/&]/\\&/g')
    sed -i "s/${key//./\\.} .*/${key} \"${esc}\"/" "$file"
}

apply_server_name() {
    if [ -n "$SERVER_NAME" ] && [ "$SERVER_NAME" != "$CURRENT_SERVER_NAME" ]; then
        con_set_quoted "$1" game.serverName "$SERVER_NAME"
    fi
    return 0
}

# Repairs keep a copy next to the edited file instead of replacing the
# original-install .bak.
backup_con() {
    if [ "$EXISTING_ACTION" = "repair" ]; then
        cp -f "$1" "${1}.pre-repair"
    else
        cp -f "$1" "${1}.bak"
    fi
}

# GameSpy status query - prints "host|map|players|max" when the game server
# answers. Same probe as 'bf1942_manager.sh status'.
query_server() {
    local ip="$1" port="$2" reply
    reply=$(timeout 2 bash -c '
        exec 3<>"/dev/udp/$1/$2" || exit 1
        printf "\\status\\" >&3
        dd bs=65535 count=1 status=none <&3
    ' _ "$ip" "$port" 2>/dev/null | tr -d '\000') || true
    [[ "$reply" == *'\hostname\'* ]] || return 1

    local -A kv=()
    local key val rest="${reply#\\}"
    while [ -n "$rest" ]; do
        key="${rest%%\\*}"; rest="${rest#*\\}"
        [ "$rest" = "${key}" ] && break
        val="${rest%%\\*}"
        if [ "$rest" = "$val" ]; then rest=""; else rest="${rest#*\\}"; fi
        kv["$key"]="$val"
    done
    echo "${kv[hostname]:-?}|${kv[mapname]:-?}|${kv[numplayers]:-?}|${kv[maxplayers]:-?}"
}

# Poll until the game server answers queries. Sets GAME_STATE to up,
# starting (service running, no answer yet) or failed, plus GAME_INFO.
wait_for_game() {
    local service="$1" ip="$2" port="$3" limit="$4"
    local start=$SECONDS frame=0 frames='|/-\'
    GAME_STATE="starting"
    GAME_INFO=""
    if [ ! -t 1 ]; then
        log_info "Waiting up to ${limit}s for the game server to answer on ${ip}:${port}..."
    fi
    while [ $((SECONDS - start)) -lt "$limit" ]; do
        # is-failed only once systemd has given up restarting it.
        if systemctl is-failed --quiet "$service"; then
            break
        fi
        if GAME_INFO=$(query_server "$ip" "$port"); then
            GAME_STATE="up"
            break
        fi
        if [ -t 1 ]; then
            echo -ne "\r  ${C_OLIVE}${frames:frame%4:1}${NC} Waiting for the game server to answer on ${ip}:${port}... ${DIM}$((SECONDS - start))s${NC} "
            frame=$((frame + 1))
        fi
        sleep 1
    done
    if [ -t 1 ]; then
        echo -ne "\r\033[K"
    fi
    if [ "$GAME_STATE" != "up" ] && ! systemctl is-active --quiet "$service"; then
        GAME_STATE="failed"
    fi
    return 0
}

check_resources() {
    log_step "Checking system resources..."

    local total_ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_ram_mb=$((total_ram_kb / 1024))

    if [ "$total_ram_mb" -lt 1024 ]; then
        log_warn "Low RAM: ${total_ram_mb}MB (recommended: 1024MB)"
        if ! confirm_continue; then
            log_info "Installation cancelled."
            exit 0
        fi
    else
        log_success "RAM: ${total_ram_mb}MB"
    fi

    local available_space_kb=$(df -P /home | tail -1 | awk '{print $4}')
    local available_space_gb=$((available_space_kb / 1024 / 1024))

    if [ "$available_space_gb" -lt 5 ]; then
        log_warn "Low disk space: ${available_space_gb}GB available (recommended: 5GB)"
        if ! confirm_continue; then
            log_info "Installation cancelled."
            exit 0
        fi
    else
        log_success "Disk space: ${available_space_gb}GB available"
    fi

    local cpu_cores=$(nproc)
    log_success "CPU cores: ${cpu_cores}"

    local instance_count=0
    if [ -d "${BF_HOME}/instances" ]; then
        instance_count=$(find "${BF_HOME}/instances" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
    fi

    local recommended_max=$((cpu_cores * 2))
    if [ "$instance_count" -ge "$recommended_max" ]; then
        log_warn "You have $instance_count instances. Recommended maximum: $recommended_max"
        echo "  Based on: ${cpu_cores} CPU cores × 2 = ${recommended_max} instances"
        if ! confirm_continue; then
            log_info "Installation cancelled."
            exit 0
        fi
    fi

    echo ""
    return 0
}

check_port_available() {
    local port="$1"
    local protocol="${2:-tcp}"

    if command -v ss >/dev/null 2>&1; then
        if [ "$protocol" = "tcp" ]; then
            ! ss -tlnp 2>/dev/null | grep -F ":${port} " >/dev/null
        else
            ! ss -ulnp 2>/dev/null | grep -F ":${port} " >/dev/null
        fi
    elif command -v netstat >/dev/null 2>&1; then
        if [ "$protocol" = "tcp" ]; then
            ! netstat -tlnp 2>/dev/null | grep -F ":${port} " >/dev/null
        else
            ! netstat -ulnp 2>/dev/null | grep -F ":${port} " >/dev/null
        fi
    else
        return 0
    fi
}

validate_ports() {
    local game_port="$1"
    local query_port="$2"
    local mgmt_port="$3"
    local lan_port="$4"
    local ase_port="$5"
    local console_port="$6"

    log_info "Checking port availability..."

    if ! check_port_available "$game_port" "udp"; then
        log_error "Game port $game_port (UDP) is already in use"
        return 1
    fi

    if ! check_port_available "$query_port" "udp"; then
        log_error "Query port $query_port (UDP) is already in use"
        return 1
    fi

    if ! check_port_available "$mgmt_port" "tcp"; then
        log_error "Management port $mgmt_port (TCP) is already in use"
        return 1
    fi

    if ! check_port_available "$lan_port" "udp"; then
        log_error "GameSpy LAN port $lan_port (UDP) is already in use"
        return 1
    fi

    if ! check_port_available "$ase_port" "udp"; then
        log_error "ASE port $ase_port (UDP) is already in use"
        return 1
    fi

    if ! check_port_available "$console_port" "tcp"; then
        log_error "Remote console port $console_port (TCP) is already in use"
        return 1
    fi

    log_success "All ports available"
    return 0
}

calculate_cpu_affinity() {
    local instance_num="$1"
    local total_cores=$(nproc)
    local cores_per_instance=2

    if [ "$total_cores" -ge "$cores_per_instance" ]; then
        local start_core=$(( (instance_num * cores_per_instance) % total_cores ))
        local end_core=$(( (start_core + cores_per_instance - 1) % total_cores ))

        if [ "$start_core" -le "$end_core" ]; then
            echo "${start_core}-${end_core}"
        else
            echo "${start_core},${end_core}"
        fi
    else
        echo "0-$((total_cores - 1))"
    fi
}

save_credentials() {
    local instance="$1"
    local username="$2"
    local password="$3"
    local mgmt_port="$4"
    local server_ip="$5"

    local cred_file="/root/.bf1942_credentials_${instance}.txt"

    cat > "$cred_file" << EOF
═══════════════════════════════════════════════════════════
  BF1942 Instance Credentials - ${instance}
═══════════════════════════════════════════════════════════

⚠  CRITICAL: These are DEFAULT PUBLIC credentials!
   CHANGE PASSWORD IMMEDIATELY via BFRM after first login!

Instance: ${instance}
Server IP: ${server_ip}
Management Port: ${mgmt_port}

Default BFRM Login:
  Username: ${username}
  Password: ${password}

⚠  SECURITY WARNING:
These credentials are publicly known defaults!
Anyone can connect with these until you change them!

To Change Password:
  1. Connect to BFRM with above credentials
  2. Go to Admin tab
  3. Click "Change Password"
  4. Set a strong unique password

Connection: ${server_ip}:${mgmt_port}

Security Recommendations:
  1. CHANGE PASSWORD IMMEDIATELY
  2. Use SSH tunnel: ssh -L ${mgmt_port}:${server_ip}:${mgmt_port} <you>@<server address>
     then connect BFRM to localhost:${mgmt_port}
  3. Restrict firewall to trusted IPs
  4. Monitor logs for unauthorized access

Generated: $(date)
═══════════════════════════════════════════════════════════
EOF

    chmod 600 "$cred_file"

    local master_file="/root/.bf1942_all_credentials.txt"
    {
        echo ""
        echo "----------------------------------------"
        echo "Instance: ${instance}"
        echo "Username: ${username}"
        echo "Password: ${password}"
        echo "Server IP: ${server_ip}:${mgmt_port}"
        echo "Created: $(date)"
        echo "----------------------------------------"
    } >> "$master_file"
    chmod 600 "$master_file" 2>/dev/null || true

    echo "$cred_file"
}

# Every port the server listens on, and whether it has to be reachable.
# Only game + query must be open to players; the rest are admin-only or
# legacy (see firewall_guide.md).
print_port_table() {
    echo " Port Configuration:"
    if [ "$INSTALL_MODE" = "standalone" ]; then
        echo "   Game Port      : 14567 (UDP)  public - players connect here"
        echo "   Query Port     : 23000 (UDP)  public - server browsers"
        echo "   GameSpy LAN    : 22000 (UDP)  LAN discovery only"
        echo "   ASE Port       : 14690 (UDP)  legacy, not needed"
        return 0
    fi
    echo "   Game Port      : ${GAME_PORT} (UDP)  public - players connect here"
    echo "   Query Port     : ${QUERY_PORT} (UDP)  public - server browsers"
    echo "   Management Port: ${MGMT_PORT} (TCP)  BFRM admin - restrict or SSH-tunnel"
    echo "   Remote Console : ${CONSOLE_PORT} (TCP)  admin only - keep closed"
    echo "   GameSpy LAN    : ${LAN_PORT} (UDP)  LAN discovery only"
    echo "   ASE Port       : ${ASE_PORT} (UDP)  legacy, not needed"
}

# Called just before a firewall that was OFF gets switched on: every server
# installed earlier without firewall rules would be cut off from players, so
# open their game + query ports first (read from their own config).
allow_existing_server_ports() {
    local fw="$1" dir name con game query p
    local -a ports=()
    if [ -f /etc/systemd/system/bf1942.service ] && [ -d "${BF_HOME}/bf1942" ]; then
        ports+=("14567/udp" "23000/udp")
    fi
    for dir in "${BF_HOME}"/instances/*/; do
        [ -d "$dir" ] || continue
        name=$(basename "$dir")
        if [ "$name" = "$INSTANCE_NAME" ]; then
            continue
        fi
        con="${dir}mods/bf1942/settings/servermanager.con"
        if [ ! -f "$con" ]; then
            continue
        fi
        game=$(awk '$1=="game.serverPort"{print $2; exit}' "$con" | tr -d '\r')
        query=$(awk '$1=="game.gameSpyPort"{print $2; exit}' "$con" | tr -d '\r')
        if [[ "$game" =~ ^[0-9]+$ ]]; then ports+=("${game}/udp"); fi
        if [[ "$query" =~ ^[0-9]+$ ]]; then ports+=("${query}/udp"); fi
    done
    if [ ${#ports[@]} -eq 0 ]; then
        return 0
    fi
    log_info "Firewall was off - also opening existing servers' ports: ${ports[*]}"
    for p in "${ports[@]}"; do
        if [ "$fw" = "ufw" ]; then
            ufw allow "$p" comment "BF1942 existing server" >/dev/null
        else
            firewall-cmd --permanent --add-port="$p" >/dev/null
        fi
    done
    return 0
}

# ------------------------------------------------------------
# ARGUMENT PARSING
# ------------------------------------------------------------

# Interactive firewall setup: ask who may reach the BFSMD management port.
# Turns FIREWALL_MODE "ask" into open / tunnel / restrict=ADDR.
choose_mgmt_access() {
    local mgmt_choice trusted
    if [ "$FIREWALL_MODE" != "ask" ]; then
        return 0
    fi
    echo ""
    echo "Management Port Security:"
    echo "  1) Open to all IPs (easier, less secure)"
    echo "  2) Restrict to specific IP (more secure)"
    echo "  3) Skip (use SSH tunnel instead - most secure)"
    read -r -p "Choice [1-3, default: 1]: " mgmt_choice || true
    case "$mgmt_choice" in
        2)
            read -r -p "Enter trusted IP address: " trusted || true
            if validate_ip "$trusted"; then
                FIREWALL_MODE="restrict=${trusted}"
            else
                log_warn "Invalid IP, opening to all"
                FIREWALL_MODE="open"
            fi
            ;;
        3) FIREWALL_MODE="tunnel" ;;
        *) FIREWALL_MODE="open" ;;
    esac
}

print_fw_open_commands() {
    local fw_port
    for fw_port in $FW_PORTS; do
        if [ "$FW_ACTIVE" = "ufw" ]; then
            echo "    sudo ufw allow ${fw_port}"
        else
            echo "    sudo firewall-cmd --permanent --add-port=${fw_port}"
        fi
    done
    if [ "$FW_ACTIVE" = "firewalld" ]; then
        echo "    sudo firewall-cmd --reload"
    fi
}

show_help() {
    cat <<EOF
Usage: sudo $0 [instance_name] [options]

Interactive by default; pass --yes for fully unattended installs.

Options:
  --mode <standalone|bfsmd>  Installation mode. Default: bfsmd when an
                             instance name is given, otherwise asked.
  --ip <local|public|ADDR>   IP to bind (BFSMD). Default with --yes: local.
  --version <2.0|2.01>       BFSMD manager version. Default: 2.0.
  --firewall <skip|open|tunnel|restrict=ADDR>
                             skip    = leave the firewall alone (default with --yes,
                                       unless ufw/firewalld is already active - then tunnel)
                             open    = game/query + management port open to all
                             tunnel  = game/query only; management via SSH tunnel
                             restrict=ADDR = game/query open, management from ADDR only
  --name <text>              Server name shown in server browsers (max 32
                             chars). Default: "BF1942 <instance>"; standalone
                             keeps the shipped name.
  --repair                   Instance already installed: keep its server files,
                             maps and settings; rewrite the service, sudo and
                             firewall rules and reset its ports. Default with
                             --yes when the instance exists.
  --reinstall                Instance already installed: fresh server files
                             (the old settings folder is kept as a backup).
  --patches / --no-patches   Apply the community CTF bug fixes to the server
                             binary, or don't (asked when interactive; --yes
                             alone skips them). Don't use with the bfstats.io
                             replay recorder - it needs the unmodified binary.
  --yes, -y                  Never prompt: accept warnings/confirmations and
                             use the defaults above for anything not given.
  --verbose, -v              Show full package-manager output on screen (it
                             always goes to /var/log/bf1942-install.log).
  --allow-unverified-downloads
                             With --yes, continue after a checksum warning.
                             Interactive use always requires typing
                             UNVERIFIED at a checksum mismatch.
  --help, -h                 Show this help.

Unattended example:
  sudo $0 server1 --yes --ip public --firewall tunnel
EOF
}

# ------------------------------------------------------------
# OPTIONAL BUG-FIX PATCHES
# ------------------------------------------------------------
# Same location bf1942_manager.sh uses, so 'bf1942_manager.sh patch' reuses
# these files later instead of downloading them again.
PATCH_CACHE="/opt/bf1942-linux/patches"
PATCH_FILES="apply_patches.sh patch_ctf_flags_map.py patch_ctf_respawn.py patch-existing-logging.sh install-replay-recorder.sh"
PATCH_RESULT=""

# Download the patch files and apply them to this instance. Never fatal:
# on any failure the server is left as installed (PATCH_RESULT=failed).
install_patches() {
    local ref="${BF1942_LINUX_REF:-main}" f tmp target
    if [[ ! "$ref" =~ ^[A-Za-z0-9._/-]+$ ]]; then
        log_warn "BF1942_LINUX_REF has unexpected characters - patches skipped."
        return 1
    fi
    local raw="https://raw.githubusercontent.com/hootmeow/bf1942-linux/${ref}/patches"

    if ! command -v python3 >/dev/null 2>&1; then
        local -a py=()
        if command -v apt-get >/dev/null 2>&1; then py=(apt-get -o DPkg::Lock::Timeout=300 install -y python3)
        elif command -v dnf >/dev/null 2>&1; then py=(dnf install -y python3)
        elif command -v pacman >/dev/null 2>&1; then py=(pacman -S --needed --noconfirm python)
        elif command -v zypper >/dev/null 2>&1; then py=(env ZYPP_LOCK_TIMEOUT=300 zypper --non-interactive install python3)
        fi
        if [ ${#py[@]} -eq 0 ]; then
            log_warn "python3 is needed for the patches and couldn't be installed automatically."
            return 1
        fi
        run_quiet --soft "Installing python3 (for the patches)" "${py[@]}" || return 1
    fi

    mkdir -p "$PATCH_CACHE" && chmod 755 "$PATCH_CACHE" || return 1
    for f in $PATCH_FILES; do
        tmp="${PATCH_CACHE}/.${f}.part"
        if curl -fsSL --retry 2 --max-time 60 -o "$tmp" "${raw}/${f}" &&
           head -1 "$tmp" | grep -qE '^#!/usr/bin/env (bash|python3)'; then
            chmod 755 "$tmp"
            mv -f "$tmp" "${PATCH_CACHE}/${f}"
        else
            rm -f "$tmp"
            log_warn "Couldn't download patches/${f} - patches skipped."
            return 1
        fi
    done
    date +%s > "${PATCH_CACHE}/.fetched"

    target="$INSTANCE_NAME"
    [ "$INSTALL_MODE" = "standalone" ] && target="standalone"
    run_quiet --soft "Applying bug-fix patches" bash "${PATCH_CACHE}/apply_patches.sh" "$target" --yes
}

# Ask to continue past a warning; --yes always continues.
confirm_continue() {
    if [ "$ASSUME_YES" -eq 1 ]; then
        log_warn "--yes given - continuing anyway."
        return 0
    fi
    local confirm
    read -r -p "Continue anyway? [y/N] " confirm
    [[ "$confirm" =~ ^([yY][eE][sS]|[yY])$ ]]
}

INSTANCE_NAME=""
OPT_MODE=""
OPT_IP=""
OPT_VERSION=""
OPT_FIREWALL=""
OPT_SERVER_NAME=""
OPT_EXISTING=""
OPT_PATCHES=""
ASSUME_YES=0
ALLOW_UNVERIFIED_DOWNLOADS=0
ORIG_ARGS=""
if [ $# -gt 0 ]; then
    ORIG_ARGS=$(printf '%q ' "$@")
fi

while [ $# -gt 0 ]; do
    case "$1" in
        --mode|--ip|--version|--firewall|--name)
            if [ $# -lt 2 ]; then
                log_error "$1 requires a value (see --help)"
                exit 1
            fi
            case "$1" in
                --mode)     OPT_MODE="$2" ;;
                --ip)       OPT_IP="$2" ;;
                --version)  OPT_VERSION="$2" ;;
                --firewall) OPT_FIREWALL="$2" ;;
                --name)     OPT_SERVER_NAME="$2" ;;
            esac
            shift 2
            ;;
        --repair|--reinstall)
            OPT_EXISTING="${1#--}"
            shift
            ;;
        --verbose|-v)
            VERBOSE=1
            shift
            ;;
        --patches|--no-patches)
            if [ "$1" = "--patches" ]; then OPT_PATCHES="yes"; else OPT_PATCHES="no"; fi
            shift
            ;;
        --allow-unverified-downloads)
            ALLOW_UNVERIFIED_DOWNLOADS=1
            shift
            ;;
        --yes|-y)
            ASSUME_YES=1
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        -*)
            log_error "Unknown option: $1 (see --help)"
            exit 1
            ;;
        *)
            if [ -n "$INSTANCE_NAME" ]; then
                log_error "Unexpected argument: $1 (instance name is already '${INSTANCE_NAME}')"
                exit 1
            fi
            INSTANCE_NAME="$1"
            shift
            ;;
    esac
done

case "$OPT_MODE" in
    ""|standalone|bfsmd) ;;
    *) log_error "Invalid --mode '${OPT_MODE}' (use standalone or bfsmd)"; exit 1 ;;
esac
case "$OPT_VERSION" in
    ""|2.0|2.01) ;;
    *) log_error "Invalid --version '${OPT_VERSION}' (use 2.0 or 2.01)"; exit 1 ;;
esac
case "$OPT_FIREWALL" in
    ""|skip|open|tunnel) ;;
    restrict=*)
        if ! validate_ip "${OPT_FIREWALL#restrict=}"; then
            log_error "Invalid IP in '--firewall ${OPT_FIREWALL}'"
            exit 1
        fi
        ;;
    *) log_error "Invalid --firewall '${OPT_FIREWALL}' (use skip, open, tunnel, or restrict=ADDR)"; exit 1 ;;
esac
if [ -n "$OPT_IP" ] && [ "$OPT_IP" != "local" ] && [ "$OPT_IP" != "public" ] && ! validate_ip "$OPT_IP"; then
    log_error "Invalid --ip '${OPT_IP}' (use local, public, or a literal IPv4 address)"
    exit 1
fi
if [ -n "$OPT_SERVER_NAME" ] && ! validate_server_name "$OPT_SERVER_NAME"; then
    exit 1
fi

# ------------------------------------------------------------
# CLEANUP TRAP
# ------------------------------------------------------------
TEMP_DIR=""
REGISTRY_ENTRY_ADDED=0
INSTALL_COMPLETE=0
INSTANCE_DIR_CREATED=0

cleanup() {
    # Ctrl-C during a quiet command: don't leave apt/dnf running unseen.
    if [ -n "${QUIET_PID:-}" ] && kill -0 "$QUIET_PID" 2>/dev/null; then
        kill "$QUIET_PID" 2>/dev/null || true
    fi
    if [ -n "${TEMP_DIR:-}" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
    if [ "$INSTANCE_DIR_CREATED" -eq 1 ] && [ "$INSTALL_COMPLETE" -eq 0 ]; then
        rmdir -- "$BF_ROOT" 2>/dev/null || true
    fi
    # Give the instance ID back if the install never got as far as creating
    # the instance (cancelled prompt, failed download, port conflict, ...).
    if [ "$REGISTRY_ENTRY_ADDED" -eq 1 ] && [ "$INSTALL_COMPLETE" -eq 0 ]; then
        sed -i "/^${INSTANCE_NAME}=/d" "${INSTANCE_REGISTRY:-/etc/bf1942_instances.conf}" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# ------------------------------------------------------------
# PRE-FLIGHT CHECKS
# ------------------------------------------------------------

if [[ $EUID -ne 0 ]]; then
   log_error "This script requires admin privileges. Please run with sudo:"
   echo "        sudo $0 ${ORIG_ARGS}"
   exit 1
fi

# Full output of package installs and other noisy steps (see run_quiet).
if ! { touch "$INSTALL_LOG" && chmod 600 "$INSTALL_LOG"; } 2>/dev/null; then
    INSTALL_LOG="/var/tmp/bf1942-install.log"
    touch "$INSTALL_LOG" 2>/dev/null || INSTALL_LOG="/dev/null"
fi
echo "==== $(date '+%F %T') $0 ${ORIG_ARGS}" >> "$INSTALL_LOG"

if ! command -v apt-get &> /dev/null; then
    log_error "This script requires apt-get (Debian)."
    exit 1
fi

# Warn (but allow continuing) when run on another distro or release.
# OS_TARGET_IDS may list several IDs (e.g. a distro and its rebuilds).
OS_TARGET_IDS=" debian "
OS_TARGET_VERSION=""
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$OS_TARGET_IDS" != *" ${ID:-unknown} "* ]]; then
        log_warn "This script is intended for Debian. Detected: ${PRETTY_NAME:-unknown}"
        if ! confirm_continue; then exit 1; fi
    elif [ -n "$OS_TARGET_VERSION" ] && [[ "${VERSION_ID:-}" != "$OS_TARGET_VERSION"* ]]; then
        log_warn "This script targets Debian ${OS_TARGET_VERSION}. Detected: ${PRETTY_NAME:-unknown}"
        if ! confirm_continue; then exit 1; fi
    else
        log_info "Detected: ${PRETTY_NAME:-$ID}"
    fi
fi

if ! check_resources; then
    log_error "System does not meet minimum requirements."
    exit 1
fi

# ------------------------------------------------------------
# BANNER
# ------------------------------------------------------------
cls
echo ""
echo -e "${C_SAND}   ██████╗ ███████╗ ██╗ █████╗  ██╗  ██╗██████╗${NC}"
echo -e "${C_SAND}   ██╔══██╗██╔════╝███║██╔══██╗ ██║  ██║╚════██╗${NC}"
echo -e "${C_KHAKI}   ██████╔╝█████╗  ╚██║╚██████║ ███████║ █████╔╝${NC}"
echo -e "${C_KHAKI}   ██╔══██╗██╔══╝   ██║ ╚═══██║ ╚════██║██╔═══╝${NC}"
echo -e "${C_OLIVE}   ██████╔╝██║      ██║ █████╔╝      ██║███████╗${NC}"
echo -e "${C_OLIVE}   ╚═════╝ ╚═╝      ╚═╝ ╚════╝       ╚═╝╚══════╝${NC}"
echo ""
echo -e "${C_ARMY}   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "   ${YELLOW}★${NC} ${BOLD}BATTLEFIELD 1942 · DEDICATED SERVER${NC} ${YELLOW}★${NC}  ${C_STEEL}[Debian]${NC}"
echo -e "   ${DIM}enhanced multi-instance setup — smart · secure · optimized${NC}"
echo -e "${C_ARMY}   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "   ${DIM}by${NC} ${BOLD}OWLCAT${NC}  ${DIM}·${NC}  ${CYAN}github.com/hootmeow/bf1942-linux${NC}  ${DIM}·${NC}  ${C_KHAKI}captheflag.com${NC}"
echo ""

# ------------------------------------------------------------
# INSTALLATION MODE
# ------------------------------------------------------------
if [ -n "$INSTANCE_NAME" ] && [ "$OPT_MODE" = "standalone" ]; then
    log_error "Standalone mode does not take an instance name."
    exit 1
fi

INSTALL_MODE="$OPT_MODE"

if [ -z "$INSTALL_MODE" ] && [ -n "$INSTANCE_NAME" ]; then
    INSTALL_MODE="bfsmd"
fi

if [ -z "$INSTALL_MODE" ] && [ "$ASSUME_YES" -eq 1 ]; then
    log_error "--yes needs --mode standalone, or an instance name for a BFSMD install."
    exit 1
fi

if [ -z "$INSTALL_MODE" ]; then
    echo "Select installation mode:"
    echo ""
    echo -e "  ${BOLD}1) Standalone Server${NC} (no remote management)"
    echo "     • Simple dedicated server"
    echo "     • Command-line configuration only"
    echo "     • Lower resource usage"
    echo ""
    echo -e "  ${BOLD}2) BFSMD-Managed Instance${NC} (with remote management)"
    echo "     • Full GUI remote management via BFRM client"
    echo "     • Supports multiple instances"
    echo "     • Advanced server management"
    echo ""
    echo -e "  ${BOLD}3) Exit${NC} (install nothing)"
    echo ""
    read -r -p "Enter your choice [1-3]: " mode_choice

    case "$mode_choice" in
        1) INSTALL_MODE="standalone" ;;
        2) INSTALL_MODE="bfsmd" ;;
        3|q|Q)
            log_info "Installation cancelled - nothing was changed."
            exit 0
            ;;
        *)
            log_error "Invalid choice. Exiting."
            exit 1
            ;;
    esac
fi

if [ "$INSTALL_MODE" = "bfsmd" ]; then
    if [ -n "$INSTANCE_NAME" ]; then
        if ! validate_instance_name "$INSTANCE_NAME"; then
            exit 1
        fi
    else
        if [ "$ASSUME_YES" -eq 1 ]; then
            log_error "BFSMD mode needs an instance name (e.g. sudo $0 server1 --yes)."
            exit 1
        fi
        while true; do
            echo ""
            read -r -p "Enter instance name (3-20 chars, or q to quit): " INSTANCE_NAME
            if [ "$INSTANCE_NAME" = "q" ] || [ "$INSTANCE_NAME" = "Q" ]; then
                log_info "Installation cancelled - nothing was changed."
                exit 0
            fi
            if validate_instance_name "$INSTANCE_NAME"; then
                break
            fi
        done
    fi
else
    INSTANCE_NAME="default"
fi

# ------------------------------------------------------------
# ALREADY INSTALLED? Repair or reinstall
# ------------------------------------------------------------
if [ "$INSTALL_MODE" = "standalone" ]; then
    TARGET_DIR="${BF_HOME}/bf1942"
    TARGET_SERVICE="bf1942.service"
    TARGET_LABEL="The standalone server"
else
    TARGET_DIR="${BF_HOME}/instances/${INSTANCE_NAME}"
    TARGET_SERVICE="bfsmd-${INSTANCE_NAME}.service"
    TARGET_LABEL="Instance '${INSTANCE_NAME}'"
fi
EXISTING_ACTION=""
if [ -d "$TARGET_DIR" ] && [ -n "$(ls -A "$TARGET_DIR" 2>/dev/null)" ]; then
    CAN_REPAIR=0
    if [ -f "${TARGET_DIR}/bf1942_lnxded.dynamic" ] && [ -d "${TARGET_DIR}/mods/bf1942/settings" ] &&
        { [ "$INSTALL_MODE" = "standalone" ] || [ -f "${TARGET_DIR}/bfsmd.static" ]; }; then
        CAN_REPAIR=1
    fi
    echo ""
    log_warn "${TARGET_LABEL} is already installed at ${TARGET_DIR}."
    if [ -n "$OPT_EXISTING" ]; then
        EXISTING_ACTION="$OPT_EXISTING"
    elif [ "$ASSUME_YES" -eq 1 ]; then
        if [ "$CAN_REPAIR" -eq 1 ]; then
            EXISTING_ACTION="repair"
        else
            EXISTING_ACTION="reinstall"
        fi
        log_info "--yes given - doing a ${EXISTING_ACTION} (choose with --repair / --reinstall)."
    else
        echo ""
        if [ "$CAN_REPAIR" -eq 1 ]; then
            echo -e "  ${BOLD}1) Repair${NC} (recommended) - keep server files, maps and settings;"
            echo "     rewrite the service, sudo and firewall rules, reset the ports"
        else
            echo -e "  ${DIM}1) Repair - not possible, the server files are incomplete${NC}"
        fi
        echo -e "  ${BOLD}2) Reinstall${NC} - fresh server files; the current settings folder is"
        echo "     kept as mods/bf1942/settings.pre-reinstall-<date>"
        echo -e "  ${BOLD}3) Cancel${NC}"
        echo ""
        if [ "$CAN_REPAIR" -eq 1 ]; then
            read -r -p "Choice [1-3, Enter = 1]: " existing_choice
        else
            read -r -p "Choice [2-3]: " existing_choice
        fi
        case "$existing_choice" in
            1|"")
                if [ "$CAN_REPAIR" -eq 0 ]; then
                    log_info "Installation cancelled - nothing was changed."
                    exit 0
                fi
                EXISTING_ACTION="repair"
                ;;
            2) EXISTING_ACTION="reinstall" ;;
            *)
                log_info "Installation cancelled - nothing was changed."
                exit 0
                ;;
        esac
    fi
    if [ "$EXISTING_ACTION" = "repair" ] && [ "$CAN_REPAIR" -eq 0 ]; then
        log_error "Cannot repair: the server files in ${TARGET_DIR} are incomplete. Use --reinstall."
        exit 1
    fi
elif [ "$OPT_EXISTING" = "repair" ]; then
    log_error "Nothing to repair: ${TARGET_DIR} does not exist."
    exit 1
fi

# ------------------------------------------------------------
# SERVER NAME (shown in server browsers)
# ------------------------------------------------------------
CURRENT_SERVER_NAME=""
if [ -n "$EXISTING_ACTION" ]; then
    if [ "$INSTALL_MODE" = "bfsmd" ]; then
        name_files="servermanager.con serversettings.con"
    else
        name_files="serversettings.con"
    fi
    for name_file in $name_files; do
        CURRENT_SERVER_NAME=$(con_get_quoted "${TARGET_DIR}/mods/bf1942/settings/${name_file}" game.serverName)
        if [ -n "$CURRENT_SERVER_NAME" ]; then
            break
        fi
    done
fi

if [ "$EXISTING_ACTION" = "repair" ]; then
    DEFAULT_SERVER_NAME="$CURRENT_SERVER_NAME"
elif [ "$INSTALL_MODE" = "bfsmd" ]; then
    DEFAULT_SERVER_NAME="BF1942 ${INSTANCE_NAME}"
else
    DEFAULT_SERVER_NAME=""
fi

SERVER_NAME="$OPT_SERVER_NAME"
if [ -z "$SERVER_NAME" ] && [ "$ASSUME_YES" -eq 0 ]; then
    echo ""
    while true; do
        read -r -p "Server name shown in the server browser [${DEFAULT_SERVER_NAME:-keep the default}]: " SERVER_NAME
        # Trim surrounding whitespace.
        SERVER_NAME="${SERVER_NAME#"${SERVER_NAME%%[![:space:]]*}"}"
        SERVER_NAME="${SERVER_NAME%"${SERVER_NAME##*[![:space:]]}"}"
        if [ -z "$SERVER_NAME" ]; then
            SERVER_NAME="$DEFAULT_SERVER_NAME"
            break
        fi
        if validate_server_name "$SERVER_NAME"; then
            break
        fi
    done
elif [ -z "$SERVER_NAME" ]; then
    SERVER_NAME="$DEFAULT_SERVER_NAME"
fi

APPLY_PATCHES=0
if [ "$OPT_PATCHES" = "yes" ]; then
    APPLY_PATCHES=1
elif [ -z "$OPT_PATCHES" ] && [ "$ASSUME_YES" -eq 0 ]; then
    echo ""
    echo -e " ${BOLD}Optional bug fixes${NC} for the server binary (uuuzbf/bf1942-patches):"
    echo "   - a dropped CTF flag lands on buildings/bridges instead of falling through"
    echo "   - the CTF flag's 30 s return timer resets every time it's picked up"
    echo -e "   ${DIM}Skip these if you'll use the bfstats.io replay recorder (it needs the unmodified binary).${NC}"
    echo -e "   ${DIM}You can apply them any time later with: sudo ./bf1942_manager.sh patch${NC}"
    read -r -p "Apply them? [y/N] " patch_answer || true
    [[ "${patch_answer:-}" =~ ^[yY] ]] && APPLY_PATCHES=1
fi

# ------------------------------------------------------------
# SET PATHS AND PORTS
# ------------------------------------------------------------
if [ "$INSTALL_MODE" = "standalone" ]; then
    BF_ROOT="${BF_HOME}/bf1942"
    SERVICE_NAME="bf1942"
    SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

    # Standalone always uses the stock ports - make sure nothing else
    # (including a stopped reinstall target) is holding them.
    log_info "Checking port availability..."
    if [ -n "$EXISTING_ACTION" ] && systemctl is-active --quiet "$TARGET_SERVICE"; then
        log_info "Ports are held by the running ${TARGET_SERVICE} - it is stopped for the ${EXISTING_ACTION}."
    elif ! check_port_available 14567 udp || ! check_port_available 23000 udp; then
        log_error "Port 14567/udp or 23000/udp is already in use."
        log_error "Stop the process using it (a running standalone server?) and re-run."
        exit 1
    else
        log_success "Ports 14567/udp and 23000/udp available"
    fi
else
    BF_BASE="${BF_HOME}/instances"
    BF_ROOT="${BF_BASE}/${INSTANCE_NAME}"
    SERVICE_NAME="bfsmd-${INSTANCE_NAME}"
    SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

    # Instance IDs are allocated once and persisted: the name hash can
    # collide for two different names, and a collision with a *stopped*
    # instance would pass the live-socket port check below unnoticed.
    INSTANCE_REGISTRY="/etc/bf1942_instances.conf"

    # Seed the registry with instances created before it existed.
    if [ -d "${BF_HOME}/instances" ]; then
        for existing_dir in "${BF_HOME}/instances"/*/; do
            [ -d "$existing_dir" ] || continue
            existing_name=$(basename "$existing_dir")
            grep -q "^${existing_name}=" "$INSTANCE_REGISTRY" 2>/dev/null && continue
            existing_hash=$(echo -n "$existing_name" | cksum | cut -d' ' -f1)
            echo "${existing_name}=$((existing_hash % 100))" >> "$INSTANCE_REGISTRY"
        done
    fi

    INSTANCE_ID=$(awk -F= -v n="$INSTANCE_NAME" '$1==n{print $2; exit}' "$INSTANCE_REGISTRY" 2>/dev/null || true)
    if [ -z "$INSTANCE_ID" ]; then
        INSTANCE_HASH=$(echo -n "$INSTANCE_NAME" | cksum | cut -d' ' -f1)
        INSTANCE_ID=$((INSTANCE_HASH % 100))
        ID_TRIES=0
        # ID 0 is never assigned: it would reproduce the standalone
        # server's default ports (14567/23000).
        while [ "$INSTANCE_ID" -eq 0 ] || grep -q "=${INSTANCE_ID}\$" "$INSTANCE_REGISTRY" 2>/dev/null; do
            INSTANCE_ID=$(( (INSTANCE_ID + 1) % 100 ))
            ID_TRIES=$((ID_TRIES + 1))
            if [ "$ID_TRIES" -gt 100 ]; then
                log_error "No free instance IDs left (see ${INSTANCE_REGISTRY})."
                exit 1
            fi
        done
        echo "${INSTANCE_NAME}=${INSTANCE_ID}" >> "$INSTANCE_REGISTRY"
        chmod 644 "$INSTANCE_REGISTRY" 2>/dev/null || true
        REGISTRY_ENTRY_ADDED=1
    fi

    GAME_PORT=$((14567 + INSTANCE_ID))
    QUERY_PORT=$((23000 + INSTANCE_ID))
    MGMT_PORT=$((14667 + INSTANCE_ID))
    LAN_PORT=$((22000 + INSTANCE_ID))
    ASE_PORT=$((14690 + INSTANCE_ID))
    CONSOLE_PORT=$((4711 + INSTANCE_ID))

    if [ -n "$EXISTING_ACTION" ] && systemctl is-active --quiet "$TARGET_SERVICE"; then
        log_info "Ports are held by the running ${TARGET_SERVICE} - it is stopped for the ${EXISTING_ACTION}."
    elif ! validate_ports "$GAME_PORT" "$QUERY_PORT" "$MGMT_PORT" "$LAN_PORT" "$ASE_PORT" "$CONSOLE_PORT"; then
        log_error "Port conflict detected. Free the ports or remove the conflicting instance."
        exit 1
    fi

    log_info "Calculating CPU affinity..."

    # Key the core assignment to the persistent instance ID - registry line
    # positions shift when an instance is removed, the ID never does.
    CPU_AFFINITY=$(calculate_cpu_affinity "$INSTANCE_ID")

    log_success "CPU affinity: ${CPU_AFFINITY}"
fi

SUDOERS_FILE="/etc/sudoers.d/bf1942_${INSTANCE_NAME}"

# ------------------------------------------------------------
# NETWORK CONFIGURATION
# ------------------------------------------------------------
if [ "$INSTALL_MODE" = "bfsmd" ]; then
    # A repair keeps the address the instance already binds to.
    if [ -z "$OPT_IP" ] && [ "$EXISTING_ACTION" = "repair" ] && [ -f "$SERVICE_FILE" ]; then
        EXISTING_IP=$(sed -n 's/.* -ip \([0-9.]*\) .*/\1/p' "$SERVICE_FILE" | head -1)
        if validate_ip "$EXISTING_IP"; then
            OPT_IP="$EXISTING_IP"
            log_info "Keeping the current bind IP ${EXISTING_IP} (pass --ip to change it)"
        fi
    fi
    if [ -z "$OPT_IP" ] && [ "$ASSUME_YES" -eq 1 ]; then
        OPT_IP="local"
    fi

    case "$OPT_IP" in
        "")
            log_info "Starting IP address selection..."
            SERVER_IP=$(select_ip_address)
            ;;
        local)
            SERVER_IP=$(detect_local_ip)
            ;;
        public)
            SERVER_IP=$(detect_ip_addresses | cut -d'|' -f2)
            ;;
        *)
            SERVER_IP="$OPT_IP"
            ;;
    esac

    if [ -z "$SERVER_IP" ]; then
        log_error "Failed to capture server IP"
        exit 1
    fi

    if ! validate_ip "$SERVER_IP"; then
        log_error "Invalid IP address captured: '${SERVER_IP}'"
        exit 1
    fi

    log_success "Selected IP: ${SERVER_IP}"
fi

# ------------------------------------------------------------
# SET DEFAULT CREDENTIALS
# ------------------------------------------------------------
if [ "$INSTALL_MODE" = "bfsmd" ]; then
    log_info "Preparing default admin credentials..."

    # BFSMD uses a proprietary hash format that cannot be generated
    # Users must change password via BFRM after first login
    ADMIN_USERNAME="bf1942"
    ADMIN_PASSWORD="battlefield"

    log_warn "Default credentials will be configured"
    log_warn "You MUST change the password via BFRM after installation"
fi

# ------------------------------------------------------------
# DISPLAY CONFIGURATION SUMMARY
# ------------------------------------------------------------
echo ""
hr
echo -e "   ${BOLD}Installation Configuration${NC}"
hr
echo " Mode             : ${INSTALL_MODE}"
if [ -n "$EXISTING_ACTION" ]; then
    echo " Action           : ${EXISTING_ACTION} the existing install"
fi
echo " Instance Name    : ${INSTANCE_NAME}"
echo " Server Name      : ${SERVER_NAME:-(keep the default)}"
echo " Install Path     : ${BF_ROOT}"
echo " Service Name     : ${SERVICE_NAME}"
if [ "$APPLY_PATCHES" -eq 1 ]; then
    echo " Bug-fix patches  : apply (CTF flag fixes)"
else
    echo " Bug-fix patches  : skip"
fi

if [ "$INSTALL_MODE" = "bfsmd" ]; then
    echo ""
    echo " Network:"
    echo "   Server IP      : ${SERVER_IP}"
    echo ""
    print_port_table
    echo ""
    echo " Performance:"
    echo "   CPU Affinity   : Cores ${CPU_AFFINITY}"
fi

hr
echo ""
if [ "$ASSUME_YES" -eq 1 ]; then
    log_info "--yes given - proceeding."
else
    read -r -p "Continue with this configuration? [y/N] " confirm
    if [[ ! "$confirm" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        log_warn "Installation cancelled."
        exit 0
    fi
fi

# ------------------------------------------------------------
# SAFETY: temp workspace (removed by the EXIT trap set at argument parsing)
# ------------------------------------------------------------
# Private, disk-backed space for the large server archive.
TEMP_DIR=$(mktemp -d /var/tmp/bf1942-install.XXXXXXXX)

if [ -n "$EXISTING_ACTION" ] && systemctl is-active --quiet "$TARGET_SERVICE"; then
    log_info "Stopping ${TARGET_SERVICE} for the ${EXISTING_ACTION}..."
    systemctl stop "$TARGET_SERVICE"
fi

# ------------------------------------------------------------
# STEP 1: User Management
# ------------------------------------------------------------
log_step "1/8: Configuring service user: ${BF_USER}"

if id "$BF_USER" >/dev/null 2>&1; then
    log_info "User ${BF_USER} already exists. Skipping creation."
else
    # Own same-name group: openSUSE (and some others) would otherwise put
    # the user in the shared "users" group, and everything is chowned to
    # ${BF_USER}:${BF_USER}.
    if getent group "$BF_USER" >/dev/null 2>&1; then
        useradd -m -s /bin/bash -g "$BF_USER" "$BF_USER"
    else
        useradd -m -s /bin/bash -U "$BF_USER"
    fi
    log_success "User created."

    # A password is not needed to run the server, and a login-locked
    # service account is the safer default - admins can still get a
    # shell with: sudo su - bf1942_user
    set_user_password="n"
    if [ "$ASSUME_YES" -eq 0 ]; then
        echo ""
        read -r -p "Set a login password for ${BF_USER}? (not required) [y/N] " set_user_password
    fi
    if [[ "$set_user_password" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        if ! passwd "$BF_USER"; then
            echo ""
            log_error "Password setup failed. Script aborted."
            exit 1
        fi
    else
        log_info "Password login for ${BF_USER} stays disabled (use: sudo su - ${BF_USER})."
    fi
fi

if [ ! -d "$BF_ROOT" ]; then
    mkdir -p "$BF_ROOT"
    INSTANCE_DIR_CREATED=1
fi

# ------------------------------------------------------------
# STEP 2: Dependencies
# ------------------------------------------------------------
log_step "2/8: Installing system dependencies"

if [ ! -f "/etc/bf1942_deps_installed" ]; then
    log_info "First-time setup: Installing i386 architecture and libraries..."

    # Fresh cloud VMs run unattended-upgrades on first boot: wait for its
    # dpkg lock instead of failing with "Could not get lock".
    APT_LOCK=(-o DPkg::Lock::Timeout=300)

    dpkg --add-architecture i386
    run_quiet "Updating package lists" apt-get "${APT_LOCK[@]}" update -y

    if ! apt-cache show libc6:i386 >/dev/null 2>&1; then
        log_error "This release has no i386 (32-bit) packages - Battlefield 1942 can't run on it."
        echo "  The server is a 32-bit program. Use a supported Ubuntu LTS (22.04 / 24.04 / 26.04) or Debian 12 / 13."
        exit 1
    fi

    # Ubuntu 24.04+ and Debian 13+ renamed libcurl4 to libcurl4t64 (64-bit
    # time_t ABI transition); older releases keep the original name.
    if apt-cache show libcurl4t64:i386 >/dev/null 2>&1; then
        LIBCURL_PKG="libcurl4t64:i386"
    else
        LIBCURL_PKG="libcurl4:i386"
    fi
    log_info "Using libcurl package: ${LIBCURL_PKG}"

    run_quiet "Installing 32-bit libraries" \
        env DEBIAN_FRONTEND=noninteractive apt-get "${APT_LOCK[@]}" install -y --no-install-recommends \
        libc6:i386 libstdc++6:i386 libgcc-s1:i386 \
        zlib1g:i386 "${LIBCURL_PKG}" libxext6:i386 \
        libx11-6:i386 libncurses6:i386 wget tar curl net-tools ufw

    log_info "Installing legacy libraries..."

    pushd "$TEMP_DIR" > /dev/null

    fetch_legacy_deb "pool/main/n/ncurses/libtinfo5_6.2+20201114-2+deb11u2_i386.deb" "$LIBTINFO5_SHA"
    fetch_legacy_deb "pool/main/n/ncurses/libncurses5_6.2+20201114-2+deb11u2_i386.deb" "$LIBNCURSES5_SHA"
    fetch_legacy_deb "pool/main/g/gcc-3.3/libstdc++5_3.3.6-34_i386.deb" "$LIBSTDC5_SHA"

    run_quiet "Installing legacy libraries" dpkg -i libtinfo5*.deb libncurses5*.deb libstdc++5*.deb || true
    ldconfig

    popd > /dev/null

    # The package steps above tolerate individual failures, so verify the
    # legacy libraries actually landed before recording success - otherwise
    # a broken install would be skipped forever on re-runs.
    if legacy_libs=$(ldconfig -p) &&
        grep -q 'libstdc++\.so\.5' <<< "$legacy_libs" &&
        grep -q 'libncurses\.so\.5' <<< "$legacy_libs"; then
        touch /etc/bf1942_deps_installed
        log_success "Dependencies installed."
    else
        log_error "Legacy 32-bit libraries missing (libstdc++.so.5 / libncurses.so.5)."
        log_error "Fix the failed package installs above and re-run the script."
        exit 1
    fi
else
    log_info "Dependencies already installed. Skipping."
fi

# ------------------------------------------------------------
# STEP 3: Server Version Selection
# ------------------------------------------------------------
log_step "3/8: Selecting server version"

if [ "$EXISTING_ACTION" = "repair" ]; then
    SERVER_TAR_URL=""
    log_info "Repair: keeping the installed server version."
elif [ "$INSTALL_MODE" = "bfsmd" ] && { [ -n "$OPT_VERSION" ] || [ "$ASSUME_YES" -eq 1 ]; }; then
    if [ "${OPT_VERSION:-2.0}" = "2.01" ]; then
        SERVER_TAR_URL="https://files.bf1942.online/server/linux/linux-bf1942-server-bfsm-hitreg-201patched.tar"
        log_info "Selected: v2.01 (Patched)"
    else
        SERVER_TAR_URL="https://files.bf1942.online/server/linux/linux-bf1942-server-bfsm-hitreg.tar"
        log_info "Selected: v2.0 (Final)"
    fi
elif [ "$INSTALL_MODE" = "bfsmd" ]; then
    echo ""
    echo "--------------------------------------------------"
    echo " SELECT SERVER MANAGER VERSION"
    echo "--------------------------------------------------"
    echo " 1) BF Remote Manager v2.0 (Final)"
    echo "    - Better support for special characters"
    echo "    - Recommended for most users"
    echo ""
    echo " 2) BF Remote Manager v2.01 (Patched)"
    echo "    - Fixes unauthorized admin bugs"
    echo "    - Fixes PunkBuster issues"
    echo "    - May truncate special characters"
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
            log_warn "Invalid input. Defaulting to v2.0 (Final)"
            SERVER_TAR_URL="https://files.bf1942.online/server/linux/linux-bf1942-server-bfsm-hitreg.tar"
            ;;
    esac
else
    SERVER_TAR_URL="https://files.bf1942.online/server/linux/linux-bf1942-server.tar"
    log_info "Using standalone server package."
fi

# ------------------------------------------------------------
# STEP 4: Download Server Files
# ------------------------------------------------------------
log_step "4/8: Downloading and installing server files"

if [ "$EXISTING_ACTION" = "repair" ]; then
    log_info "Repair: keeping the existing server files."
else
    case "$SERVER_TAR_URL" in
        */linux-bf1942-server-bfsm-hitreg-201patched.tar) SERVER_TAR_SHA256="$SERVER_SHA_BFSMD_201" ;;
        */linux-bf1942-server-bfsm-hitreg.tar) SERVER_TAR_SHA256="$SERVER_SHA_BFSMD_20" ;;
        */linux-bf1942-server.tar) SERVER_TAR_SHA256="$SERVER_SHA_STANDALONE" ;;
        *) log_error "No known SHA-256 hash for $SERVER_TAR_URL"; exit 1 ;;
    esac

    log_info "Downloading from: ${SERVER_TAR_URL}"

    SERVER_TAR="${TEMP_DIR}/server.tar"
    rm -f "$SERVER_TAR"

    if ! wget -q --show-progress -O "$SERVER_TAR" "$SERVER_TAR_URL"; then
        rm -f "$SERVER_TAR"
        log_error "Download failed."
        exit 1
    fi

    if ! verify_sha256 "$SERVER_TAR_SHA256" "$SERVER_TAR"; then
        if ! accept_unverified_download "$SERVER_TAR_SHA256" "$SERVER_TAR" "$SERVER_TAR_URL"; then
            exit 1
        fi
    fi

    if [ "$EXISTING_ACTION" = "reinstall" ] && [ -d "${BF_ROOT}/mods/bf1942/settings" ]; then
        SETTINGS_BACKUP="${BF_ROOT}/mods/bf1942/settings.pre-reinstall-$(date +%Y%m%d-%H%M%S)"
        cp -a "${BF_ROOT}/mods/bf1942/settings" "$SETTINGS_BACKUP"
        log_success "Current settings saved to ${SETTINGS_BACKUP}"
    fi

    log_info "Extracting..."
    if ! tar -x --no-same-owner --strip-components=1 -C "$BF_ROOT" -f "$SERVER_TAR"; then
        rm -f "$SERVER_TAR"
        log_error "Extraction failed."
        exit 1
    fi
    rm -f "$SERVER_TAR"

    log_success "Files extracted to ${BF_ROOT}"
fi

# ------------------------------------------------------------
# STEP 5: Post-Installation Configuration
# ------------------------------------------------------------
log_step "5/8: Configuring server files"

cd "$BF_ROOT"

if [ -f "bf1942_lnxded.dynamic" ]; then
    ln -sf bf1942_lnxded.dynamic bf1942_lnxded
    log_success "Symlink created"
else
    log_error "Server binary not found"
    exit 1
fi

chmod +x start.sh bf1942_lnxded.dynamic bf1942_lnxded.static fixinstall.sh 2>/dev/null || true

if [ "$INSTALL_MODE" = "bfsmd" ]; then
    chmod +x bfsmd bfsmd.static 2>/dev/null || true
fi

# fixinstall.sh lower-cases the file names; a repair already has them.
if [ "$EXISTING_ACTION" != "repair" ] && [ -f "fixinstall.sh" ]; then
    run_quiet "Running fixinstall.sh" ./fixinstall.sh
fi

if [ "$INSTALL_MODE" = "standalone" ]; then
    SETTINGS_DIR="${BF_ROOT}/mods/bf1942/settings"
    # fixinstall.sh lower-cases every filename, so it's serversettings.con.
    if [ -f "${SETTINGS_DIR}/serversettings.con" ]; then
        log_info "Enabling XML event logging..."
        backup_con "${SETTINGS_DIR}/serversettings.con"
        sed -i "s/game\.serverEventLogging [0-9]*/game.serverEventLogging 1/" "${SETTINGS_DIR}/serversettings.con"
        sed -i "s/game\.serverEventLogCompression [0-9]*/game.serverEventLogCompression 0/" "${SETTINGS_DIR}/serversettings.con"
        apply_server_name "${SETTINGS_DIR}/serversettings.con"
        log_success "Event logging enabled"
    fi
fi

if [ "$INSTALL_MODE" = "bfsmd" ]; then
    SETTINGS_DIR="${BF_ROOT}/mods/bf1942/settings"
    # fixinstall.sh lower-cases every filename, so the settings files are
    # serversettings.con / servermanager.con from here on.
    if [ -d "$SETTINGS_DIR" ] && [ -f "${SETTINGS_DIR}/serversettings.con" ]; then
        log_info "Updating server settings..."

        backup_con "${SETTINGS_DIR}/serversettings.con"

        sed -i "s/game\.serverPort [0-9]*/game.serverPort ${GAME_PORT}/" "${SETTINGS_DIR}/serversettings.con"
        apply_server_name "${SETTINGS_DIR}/serversettings.con"
        sed -i "s/game\.serverEventLogging [0-9]*/game.serverEventLogging 1/" "${SETTINGS_DIR}/serversettings.con"
        sed -i "s/game\.serverEventLogCompression [0-9]*/game.serverEventLogCompression 0/" "${SETTINGS_DIR}/serversettings.con"

        log_success "Server settings updated"
    fi

    # servermanager.con is the file BFSMD actually reads when launching the
    # game server. Without these edits every instance keeps the default ports
    # (14567/23000/22000/14690/4711) and collides with other servers on the
    # box, and BFSMD refuses to start an Internet server while the remote
    # console still has the default UserName/Password credentials.
    SM_CON="${SETTINGS_DIR}/servermanager.con"
    if [ -f "$SM_CON" ]; then
        log_info "Updating server manager settings..."

        backup_con "$SM_CON"

        # A repair keeps console credentials that were already changed from
        # the shipped UserName/Password defaults.
        KEEP_CONSOLE_CREDS=0
        if [ "$EXISTING_ACTION" = "repair" ]; then
            existing_console_user=$(con_get_quoted "$SM_CON" manager.consoleUsername)
            existing_console_pw=$(con_get_quoted "$SM_CON" manager.consolePassword)
            if [ -n "$existing_console_user" ] && [ "${existing_console_user,,}" != "username" ] &&
                [ -n "$existing_console_pw" ] && [ "${existing_console_pw,,}" != "password" ]; then
                CONSOLE_USER="$existing_console_user"
                CONSOLE_PASSWORD="$existing_console_pw"
                KEEP_CONSOLE_CREDS=1
            fi
        fi

        if [ "$KEEP_CONSOLE_CREDS" -eq 0 ]; then
            # Keep drawing random bytes until 12 alphanumerics are available.
            CONSOLE_PASSWORD=""
            while [ "${#CONSOLE_PASSWORD}" -lt 12 ]; do
                CONSOLE_PASSWORD+="$(dd if=/dev/urandom bs=256 count=1 2>/dev/null | tr -dc 'A-Za-z0-9')"
            done
            CONSOLE_PASSWORD="${CONSOLE_PASSWORD:0:12}"
            CONSOLE_USER="bfadmin"
        fi

        sed -i "s/game\.serverPort [0-9]*/game.serverPort ${GAME_PORT}/" "$SM_CON"
        sed -i "s/game\.gameSpyPort [0-9]*/game.gameSpyPort ${QUERY_PORT}/" "$SM_CON"
        sed -i "s/game\.gameSpyLANPort [0-9]*/game.gameSpyLANPort ${LAN_PORT}/" "$SM_CON"
        sed -i "s/game\.ASEPort [0-9]*/game.ASEPort ${ASE_PORT}/" "$SM_CON"
        sed -i "s/manager\.consolePort [0-9]*/manager.consolePort ${CONSOLE_PORT}/" "$SM_CON"
        apply_server_name "$SM_CON"
        sed -i "s/game\.serverEventLogging [0-9]*/game.serverEventLogging 1/" "$SM_CON"
        sed -i "s/game\.serverEventLogCompression [0-9]*/game.serverEventLogCompression 0/" "$SM_CON"

        if [ "$KEEP_CONSOLE_CREDS" -eq 0 ]; then
            sed -i "s/manager\.consoleUsername .*/manager.consoleUsername \"bfadmin\"/" "$SM_CON"
            sed -i "s/manager\.consolePassword .*/manager.consolePassword \"${CONSOLE_PASSWORD}\"/" "$SM_CON"
            echo "Remote console (instance ${INSTANCE_NAME}): port ${CONSOLE_PORT}, user bfadmin, password ${CONSOLE_PASSWORD}" >> /root/.bf1942_all_credentials.txt
            chmod 600 /root/.bf1942_all_credentials.txt 2>/dev/null || true
        fi

        log_success "Server manager settings updated"
    fi

    # Seed the BFSMD map rotation - it ships empty and BFSMD refuses to
    # start the game server without at least one level in it.
    if [ ! -s "${SETTINGS_DIR}/servermaplist.con" ]; then
        printf 'game.addLevel berlin GPM_CQ bf1942
game.setCurrentLevel berlin GPM_CQ bf1942
' > "${SETTINGS_DIR}/servermaplist.con"
        log_success "Seeded default map rotation (berlin GPM_CQ)"
    fi


    # Don't modify useraccess.con - it already has the correct default hash
    # Just set credentials for display to user
    ADMIN_USERNAME="bf1942"
    ADMIN_PASSWORD="battlefield"

    log_info "Default admin credentials: bf1942/battlefield"
    log_warn "CRITICAL: Change password via BFRM immediately after first login!"
fi

# Scope ownership to this install - a recursive chown of the whole home
# directory would touch other instances while they are running.
chown -R "${BF_USER}:${BF_USER}" "${BF_ROOT}"
if [ "$INSTALL_MODE" = "bfsmd" ]; then
    chown "${BF_USER}:${BF_USER}" "${BF_BASE}"
fi

# The instance now exists on disk, so its registry entry must survive even
# if a later optional step (firewall prompt, ...) is interrupted.
INSTALL_COMPLETE=1

# ------------------------------------------------------------
# STEP 6: Systemd Service
# ------------------------------------------------------------
log_step "6/8: Creating systemd service"

if [ "$INSTALL_MODE" = "standalone" ]; then
    log_info "Creating standalone server service..."

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

else
    log_info "Creating BFSMD service for '${INSTANCE_NAME}'..."

    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Battlefield 1942 Server Manager Daemon (${INSTANCE_NAME})
After=network.target

[Service]
Type=simple
WorkingDirectory=${BF_ROOT}
Environment=TERM=xterm
ExecStart=${BF_ROOT}/bfsmd.static -path ${BF_ROOT} -ip ${SERVER_IP} -port ${MGMT_PORT} -restart -start -nodelay
Restart=on-failure
RestartSec=5
User=${BF_USER}
Group=${BF_USER}

# Performance Tuning
CPUAffinity=${CPU_AFFINITY}
Nice=-5
IOSchedulingClass=best-effort
IOSchedulingPriority=0
MemoryHigh=1800M
MemoryMax=2G

[Install]
WantedBy=multi-user.target
EOF

fi

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}.service" || true
log_success "Systemd service created: ${SERVICE_NAME}.service"

# ------------------------------------------------------------
# STEP 7: Sudoers Configuration
# ------------------------------------------------------------
log_step "7/8: Configuring sudo permissions"

# Write to a staging file and validate it first: a broken file in
# /etc/sudoers.d makes sudo refuse to run at all.
SUDOERS_TMP="${TEMP_DIR}/sudoers_${INSTANCE_NAME}"
cat > "$SUDOERS_TMP" <<EOF
# Battlefield 1942 Server Management (${INSTANCE_NAME})
${BF_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl start ${SERVICE_NAME}.service
${BF_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop ${SERVICE_NAME}.service
${BF_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart ${SERVICE_NAME}.service
${BF_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl status ${SERVICE_NAME}.service
${BF_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl status ${SERVICE_NAME}.service -l
${BF_USER} ALL=(ALL) NOPASSWD: /usr/bin/journalctl -u ${SERVICE_NAME}.service
EOF
# Older visudo builds also check the file mode, so match the final one.
chmod 440 "$SUDOERS_TMP"

if ! command -v visudo >/dev/null 2>&1; then
    install -m 440 -o root -g root "$SUDOERS_TMP" "$SUDOERS_FILE"
    log_warn "visudo not found - installed ${SUDOERS_FILE} without validation"
elif visudo -c -f "$SUDOERS_TMP" >/dev/null; then
    install -m 440 -o root -g root "$SUDOERS_TMP" "$SUDOERS_FILE"
    log_success "Sudoers configured (validated with visudo)"
else
    log_warn "Generated sudoers rules failed validation - not installed."
    log_warn "The server runs normally; ${BF_USER} just cannot manage it via sudo."
fi
rm -f "$SUDOERS_TMP"

# Patch while the server is stopped (apply_patches.sh restarts it only
# if it was running, e.g. on a repair).
if [ "$APPLY_PATCHES" -eq 1 ]; then
    echo ""
    log_info "Bug-fix patches"
    if install_patches; then
        PATCH_RESULT="applied"
    else
        PATCH_RESULT="failed"
        log_warn "The server is installed unpatched. Retry later: sudo ./bf1942_manager.sh patch"
    fi
fi

# ------------------------------------------------------------
# STEP 8: Start Service
# ------------------------------------------------------------
log_step "8/8: Starting server"

# restart also covers a repair/reinstall of a server that was running.
systemctl restart "${SERVICE_NAME}.service"

if [ "$INSTALL_MODE" = "standalone" ]; then
    QUERY_IP="127.0.0.1"
    QUERY_TARGET_PORT=23000
else
    QUERY_IP="$SERVER_IP"
    QUERY_TARGET_PORT="$QUERY_PORT"
fi
G_HOST=""; G_MAP=""; G_PLAYERS=""; G_MAX=""
wait_for_game "${SERVICE_NAME}.service" "$QUERY_IP" "$QUERY_TARGET_PORT" 90

case "$GAME_STATE" in
    up)
        IFS='|' read -r G_HOST G_MAP G_PLAYERS G_MAX <<< "$GAME_INFO"
        log_success "Game server is up: ${G_HOST} - ${G_MAP}, ${G_PLAYERS}/${G_MAX} players"
        ;;
    starting)
        log_warn "The service is running but the game server has not answered on ${QUERY_IP}:${QUERY_TARGET_PORT} yet."
        log_info "It may still be loading - check again shortly: ./bf1942_manager.sh health"
        ;;
    *)
        log_error "${SERVICE_NAME}.service is not running. Recent log lines:"
        journalctl -u "${SERVICE_NAME}.service" -n 15 --no-pager 2>/dev/null | sed 's/^/      /' || true
        ;;
esac

# ------------------------------------------------------------
# OPTIONAL: Firewall
# ------------------------------------------------------------
echo ""
log_info "Firewall Configuration"

# An already-active firewall (often enabled by an earlier install) blocks
# this instance's generated ports until rules are added for them.
FW_ACTIVE=""
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    FW_ACTIVE="ufw"
elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    FW_ACTIVE="firewalld"
fi
if [ "$INSTALL_MODE" = "standalone" ]; then
    FW_PORTS="14567/udp 23000/udp"
else
    FW_PORTS="${GAME_PORT}/udp ${QUERY_PORT}/udp"
fi

FW_APPLIED=""
FIREWALL_MODE="$OPT_FIREWALL"
if [ -z "$FIREWALL_MODE" ]; then
    if [ -n "$FW_ACTIVE" ]; then
        log_warn "${FW_ACTIVE} is active - players cannot reach ${FW_PORTS} until they are opened."
        if [ "$ASSUME_YES" -eq 1 ]; then
            FIREWALL_MODE="tunnel"
            log_info "--yes given - opening the game ports (management port stays closed; use an SSH tunnel)."
        else
            read -r -p "Open this server's ports in ${FW_ACTIVE}? [Y/n] " response
            if [[ "$response" =~ ^([nN][oO]|[nN])$ ]]; then
                FIREWALL_MODE="skip"
            else
                FIREWALL_MODE="ask"
            fi
        fi
    elif [ "$ASSUME_YES" -eq 1 ]; then
        FIREWALL_MODE="skip"
    else
        read -r -p "Configure firewall rules? [y/N] " response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            FIREWALL_MODE="ask"
        else
            FIREWALL_MODE="skip"
        fi
    fi
fi

if [ "$FIREWALL_MODE" = "skip" ]; then
    log_info "Skipping firewall configuration"
    if [ -n "$FW_ACTIVE" ]; then
        log_warn "${FW_ACTIVE} is active and these ports are still blocked: ${FW_PORTS}"
        log_info "Open them with:"
        print_fw_open_commands
    fi
elif ! command -v ufw >/dev/null; then
    log_warn "UFW not found - skipping firewall configuration"
else
    log_info "Configuring firewall..."

    if [ "$INSTALL_MODE" = "standalone" ]; then
        ufw allow 14567/udp comment 'BF1942 Game'
        ufw allow 23000/udp comment 'BF1942 Query'
    else
        ufw allow ${GAME_PORT}/udp comment "BF1942 ${INSTANCE_NAME} Game"
        ufw allow ${QUERY_PORT}/udp comment "BF1942 ${INSTANCE_NAME} Query"

        choose_mgmt_access

        case "$FIREWALL_MODE" in
            restrict=*)
                trusted_ip="${FIREWALL_MODE#restrict=}"
                ufw allow from ${trusted_ip} to any port ${MGMT_PORT} proto tcp comment "BFSMD ${INSTANCE_NAME} Mgmt"
                log_success "Management port restricted to ${trusted_ip}"
                ;;
            tunnel)
                log_info "Management port NOT opened (use SSH tunnel)"
                ;;
            *)
                ufw allow ${MGMT_PORT}/tcp comment "BFSMD ${INSTANCE_NAME} Mgmt"
                log_warn "Management port open to all IPs - consider using SSH tunnel"
                ;;
        esac
    fi

    # Keep SSH reachable: ufw blocks all incoming traffic by default,
    # so enabling it without an SSH rule would drop a remote session.
    SSH_PORT=$(sshd -T 2>/dev/null | awk '$1=="port"{print $2; exit}' || true)
    ufw allow "${SSH_PORT:-22}/tcp" comment 'SSH'

    if [ -z "$FW_ACTIVE" ]; then
        allow_existing_server_ports ufw
    fi
    ufw --force enable
    ufw reload
    FW_APPLIED="ufw"
    log_success "Firewall configured"
fi
# ------------------------------------------------------------
# SAVE CREDENTIALS
# ------------------------------------------------------------
CRED_FILE=""
if [ "$INSTALL_MODE" = "bfsmd" ]; then
    CRED_FILE="/root/.bf1942_credentials_${INSTANCE_NAME}.txt"
    # A repair keeps the existing file (and doesn't repeat the master entry).
    if [ "$EXISTING_ACTION" != "repair" ] || [ ! -f "$CRED_FILE" ]; then
        CRED_FILE=$(save_credentials "$INSTANCE_NAME" "$ADMIN_USERNAME" "$ADMIN_PASSWORD" "$MGMT_PORT" "$SERVER_IP")
    fi
fi

# Where players connect: the bound address, plus the public address in
# front of it when that one is private (NAT / cloud VPC).
if [ "$INSTALL_MODE" = "standalone" ]; then
    PLAYER_PORT=14567
    PLAYER_QUERY_PORT=23000
    HOST_IP=$(detect_local_ip)
else
    PLAYER_PORT="$GAME_PORT"
    PLAYER_QUERY_PORT="$QUERY_PORT"
    HOST_IP="$SERVER_IP"
fi
PUBLIC_IP=""
if [ -n "$HOST_IP" ] && is_private_ip "$HOST_IP"; then
    PUBLIC_IP=$(detect_public_ip)
fi

# Is the management port reachable directly, or only through a tunnel?
MGMT_DIRECT=1
if [ -n "$FW_APPLIED" ]; then
    case "$FIREWALL_MODE" in
        open|restrict=*) MGMT_DIRECT=1 ;;
        *) MGMT_DIRECT=0 ;;
    esac
elif [ -n "$FW_ACTIVE" ]; then
    MGMT_DIRECT=0
fi

# ------------------------------------------------------------
# FINAL SCREEN
# ------------------------------------------------------------
cls
echo ""
case "$GAME_STATE" in
    up)
        echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║${NC}                  ${GREEN}${BOLD}✔  MISSION ACCOMPLISHED${NC}                   ${GREEN}║${NC}"
        echo -e "${GREEN}║${NC}               ${DIM}server is up and answering${NC}                   ${GREEN}║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
        ;;
    starting)
        echo -e "${YELLOW}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${YELLOW}║${NC}              ${YELLOW}${BOLD}✔  INSTALLED - SERVER STARTING${NC}                ${YELLOW}║${NC}"
        echo -e "${YELLOW}║${NC}            ${DIM}not answering yet, check in a minute${NC}            ${YELLOW}║${NC}"
        echo -e "${YELLOW}╚════════════════════════════════════════════════════════════╝${NC}"
        ;;
    *)
        echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║${NC}             ${RED}${BOLD}⚠  INSTALLED - SERVER NOT RUNNING${NC}              ${RED}║${NC}"
        echo -e "${RED}║${NC}                 ${DIM}see the service log below${NC}                  ${RED}║${NC}"
        echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
        ;;
esac

DISPLAY_NAME="${G_HOST:-${SERVER_NAME:-${CURRENT_SERVER_NAME:-BF1942 server}}}"
echo ""
hr
echo -e "   ${BOLD}${DISPLAY_NAME}${NC}"
echo -e "   ${DIM}${INSTALL_MODE} · ${SERVICE_NAME}.service · ${BF_ROOT}${NC}"
hr
case "$GAME_STATE" in
    up)       echo -e " ${GREEN}●${NC} Online    ${G_MAP}, ${G_PLAYERS}/${G_MAX} players" ;;
    starting) echo -e " ${YELLOW}●${NC} Starting  service is running, the game is not answering yet" ;;
    *)        echo -e " ${RED}●${NC} Stopped   journalctl -u ${SERVICE_NAME}.service -n 50" ;;
esac

echo ""
echo -e " ${BOLD}PLAYERS CONNECT TO${NC}"
if [ -n "$PUBLIC_IP" ]; then
    echo -e "   ${CYAN}${PUBLIC_IP}:${PLAYER_PORT}${NC}   internet"
    echo -e "   ${CYAN}${HOST_IP}:${PLAYER_PORT}${NC}   same network"
    echo -e "   ${DIM}Behind a router/cloud firewall? Forward UDP ${PLAYER_PORT} and ${PLAYER_QUERY_PORT} to ${HOST_IP}.${NC}"
elif [ -n "$HOST_IP" ]; then
    echo -e "   ${CYAN}${HOST_IP}:${PLAYER_PORT}${NC}"
else
    echo -e "   ${CYAN}<server address>:${PLAYER_PORT}${NC}"
fi

if [ "$INSTALL_MODE" = "bfsmd" ]; then
    echo ""
    echo -e " ${BOLD}ADMIN - BF Remote Manager (BFRM)${NC}"
    TUNNEL_HOST="${PUBLIC_IP:-$SERVER_IP}"
    if [ "$MGMT_DIRECT" -eq 1 ]; then
        echo -e "   Connect  ${CYAN}${SERVER_IP}:${MGMT_PORT}${NC}"
        echo -e "   ${DIM}or tunnel: ssh -L ${MGMT_PORT}:${SERVER_IP}:${MGMT_PORT} <you>@${TUNNEL_HOST}, then localhost:${MGMT_PORT}${NC}"
    else
        echo -e "   Connect  ${CYAN}localhost:${MGMT_PORT}${NC} after opening the tunnel (management port is closed):"
        echo -e "            ${CYAN}ssh -L ${MGMT_PORT}:${SERVER_IP}:${MGMT_PORT} <you>@${TUNNEL_HOST}${NC}"
    fi
    if [ "$EXISTING_ACTION" = "repair" ]; then
        echo -e "   Login    unchanged ${DIM}(default ${ADMIN_USERNAME} / ${ADMIN_PASSWORD} unless you changed it)${NC}"
    else
        echo -e "   Login    ${YELLOW}${ADMIN_USERNAME} / ${ADMIN_PASSWORD}${NC}  ${RED}${BOLD}⚠ public default - change it now${NC}"
        echo -e "            ${DIM}BFRM: Admin tab > Change Password${NC}"
    fi
    if [ -n "${CONSOLE_PASSWORD:-}" ]; then
        echo -e "   Console  port ${CONSOLE_PORT}, user ${CONSOLE_USER:-bfadmin}, password ${YELLOW}${CONSOLE_PASSWORD}${NC} ${DIM}(admin only - keep closed)${NC}"
    fi
fi

echo ""
echo -e " ${BOLD}FIREWALL${NC}"
if [ -n "$FW_APPLIED" ]; then
    echo -e "   ${GREEN}✔${NC} ${FW_APPLIED}: opened ${FW_PORTS// /, }"
    if [ "$INSTALL_MODE" = "bfsmd" ]; then
        case "$FIREWALL_MODE" in
            open)       echo -e "   ${YELLOW}⚠${NC} management ${MGMT_PORT}/tcp open to all IPs" ;;
            restrict=*) echo -e "   ${GREEN}✔${NC} management ${MGMT_PORT}/tcp only from ${FIREWALL_MODE#restrict=}" ;;
            *)          echo -e "   ${GREEN}✔${NC} management ${MGMT_PORT}/tcp closed (use the SSH tunnel)" ;;
        esac
    fi
elif [ -n "$FW_ACTIVE" ]; then
    echo -e "   ${YELLOW}⚠${NC} ${FW_ACTIVE} is active and still blocks ${FW_PORTS// /, }. Open them with:"
    print_fw_open_commands
else
    echo "   Not changed - no firewall is active on this machine."
    if [ "$INSTALL_MODE" = "bfsmd" ]; then
        echo -e "   ${YELLOW}⚠${NC} management ${MGMT_PORT}/tcp is reachable from anywhere"
    fi
    echo -e "   ${DIM}Cloud providers often add their own firewall: allow UDP ${PLAYER_PORT} and ${PLAYER_QUERY_PORT} there.${NC}"
fi

echo ""
print_port_table

if [ "$INSTALL_MODE" = "standalone" ]; then
    REPAIR_CMD="sudo $0 --mode standalone --repair"
else
    REPAIR_CMD="sudo $0 ${INSTANCE_NAME} --repair"
fi
echo ""
echo -e " ${BOLD}NEXT STEPS${NC}"
echo "   ./bf1942_manager.sh status ${INSTANCE_NAME}     live status of this server"
echo "   ./bf1942_manager.sh health             check every server"
echo "   journalctl -u ${SERVICE_NAME}.service -f"
if [ "$INSTALL_MODE" = "bfsmd" ]; then
    echo "   sudo $0 <name>     add another server"
fi
echo "   ${REPAIR_CMD}     fix this one later"
case "$PATCH_RESULT" in
    applied) ;;
    failed)  echo -e "   sudo ./bf1942_manager.sh patch     ${YELLOW}patches failed - retry${NC}" ;;
    *)       echo "   sudo ./bf1942_manager.sh patch     optional CTF bug fixes" ;;
esac
echo "   ./bf1942_manager.sh                interactive menu (patches, recorder, backups)"

if [ "$INSTALL_MODE" = "bfsmd" ]; then
    echo ""
    echo -e " ${BLUE}ℹ${NC} 'Internal error!' lines in the BFSMD log at startup are normal (known BFSMD bug)."
fi

echo ""
if [ -n "$CRED_FILE" ]; then
    echo -e " ${DIM}Credentials: ${CRED_FILE}${NC}"
fi
echo -e " ${DIM}Install log: ${INSTALL_LOG}${NC}"
hr
echo ""
echo "For support: https://github.com/hootmeow/bf1942-linux"
echo "Community:   https://captheflag.com"
echo ""
echo -e "${C_SAND}${BOLD}Happy gaming!${NC} 🎮"
echo ""

if [ "$GAME_STATE" = "failed" ]; then
    exit 1
fi
