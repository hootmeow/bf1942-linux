#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  Battlefield 1942 Linux Server - Unified Setup Script (Fedora)
#
#  Tested on:
#    - Fedora 40
#    - Fedora 41
#
#  Features:
#    ✓ Smart IP detection (LAN, NAT, public scenarios)
#    ✓ Comprehensive input validation
#    ✓ CPU affinity & performance tuning
#    ✓ Multi-instance support
#    ✓ Standalone or BFSMD modes
#
#  Usage:
#    Interactive: sudo ./fed_40_bfsmd_setup.sh [instance_name]
#    Unattended:  sudo ./fed_40_bfsmd_setup.sh <instance_name> --yes [options]
#    All options: sudo ./fed_40_bfsmd_setup.sh --help
#
#  Author: OWLCAT (https://github.com/hootmeow / www.bf1942.online)
# ---------------------------------------------------------------------------

set -euo pipefail

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
    echo ""
    echo -e "${C_KHAKI}${BOLD}▶ $1${NC}"
    echo -e "${C_ARMY}${HR_LINE}${NC}"
}

# ------------------------------------------------------------
# UTILITY FUNCTIONS
# ------------------------------------------------------------

# Note: Password generation removed - BFSMD uses proprietary hash format
# that cannot be generated externally. Default credentials must be used.

detect_ip_addresses() {
    local local_ip=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "")
    echo "Detecting public IP address..." >&2
    local public_ip=$(timeout 5 curl -s https://api.ipify.org 2>/dev/null || \
                      timeout 5 curl -s https://ifconfig.me 2>/dev/null || \
                      timeout 5 curl -s https://icanhazip.com 2>/dev/null || echo "")
    echo "${local_ip}|${public_ip}"
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

    if [ -d "${BF_HOME}/instances/${name}" ]; then
        log_error "Instance '$name' already exists."
        log_info "To reinstall it, remove it first: sudo ./bf1942_manager.sh remove $name"
        return 1
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

    local available_space_kb=$(df /home | tail -1 | awk '{print $4}')
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
            ! ss -tlnp 2>/dev/null | grep -q ":${port} "
        else
            ! ss -ulnp 2>/dev/null | grep -q ":${port} "
        fi
    elif command -v netstat >/dev/null 2>&1; then
        if [ "$protocol" = "tcp" ]; then
            ! netstat -tlnp 2>/dev/null | grep -q ":${port} "
        else
            ! netstat -ulnp 2>/dev/null | grep -q ":${port} "
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
  2. Use SSH tunnel: ssh -L ${mgmt_port}:localhost:${mgmt_port} user@${server_ip}
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

display_credentials() {
    local username="$1"
    local password="$2"
    local server_ip="$3"
    local mgmt_port="$4"
    local cred_file="$5"

    cls
    echo ""
    echo -e "${YELLOW}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║${NC}             ${BOLD}🔐 IMPORTANT: DEFAULT CREDENTIALS${NC}              ${YELLOW}║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════════════════════╝${NC}"

    echo ""
    echo -e "${BOLD}${RED}⚠  CHANGE PASSWORD IMMEDIATELY AFTER FIRST LOGIN  ⚠${NC}"
    echo ""
    echo -e "${BOLD}Connection Details:${NC}"
    echo -e "  Server IP: ${CYAN}${server_ip}${NC}"
    echo -e "  Port:      ${CYAN}${mgmt_port}${NC}"
    echo ""
    echo -e "${BOLD}Default BFRM Login:${NC}"
    echo -e "  Username: ${YELLOW}${username}${NC}"
    echo -e "  Password: ${YELLOW}${password}${NC}"
    echo ""
    echo -e "${RED}${BOLD}SECURITY WARNING:${NC}"
    echo -e "${RED}These are PUBLIC default credentials!${NC}"
    echo -e "${RED}Anyone can connect with these credentials!${NC}"
    echo ""
    echo -e "${BOLD}To change password:${NC}"
    echo "  1. Connect to BFRM with credentials above"
    echo "  2. Go to: Admin tab"
    echo "  3. Click: 'Change Password'"
    echo "  4. Set a strong unique password"
    echo ""
    echo -e "Credentials also saved to: ${CYAN}${cred_file}${NC}"
    echo ""
    echo -e "${BOLD}To connect via SSH tunnel (recommended):${NC}"
    echo -e "  ${CYAN}ssh -L ${mgmt_port}:localhost:${mgmt_port} user@${server_ip}${NC}"
    echo -e "  Then connect BFRM to: ${CYAN}localhost:${mgmt_port}${NC}"
    echo ""
    if [ "$ASSUME_YES" -eq 0 ]; then
        echo "Press ENTER to continue..."
        read -r
    fi
}

# ------------------------------------------------------------
# ARGUMENT PARSING
# ------------------------------------------------------------

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
                             skip    = leave the firewall alone (default with --yes)
                             open    = game/query + management port open to all
                             tunnel  = game/query only; management via SSH tunnel
                             restrict=ADDR = game/query open, management from ADDR only
  --yes, -y                  Never prompt: accept warnings/confirmations and
                             use the defaults above for anything not given.
  --help, -h                 Show this help.

Unattended example:
  sudo $0 server1 --yes --ip public --firewall tunnel
EOF
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
ASSUME_YES=0
ORIG_ARGS="$*"

while [ $# -gt 0 ]; do
    case "$1" in
        --mode|--ip|--version|--firewall)
            if [ $# -lt 2 ]; then
                log_error "$1 requires a value (see --help)"
                exit 1
            fi
            case "$1" in
                --mode)     OPT_MODE="$2" ;;
                --ip)       OPT_IP="$2" ;;
                --version)  OPT_VERSION="$2" ;;
                --firewall) OPT_FIREWALL="$2" ;;
            esac
            shift 2
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

# ------------------------------------------------------------
# CLEANUP TRAP
# ------------------------------------------------------------
TEMP_DIR=""
REGISTRY_ENTRY_ADDED=0
INSTALL_COMPLETE=0

cleanup() {
    if [ -n "${TEMP_DIR:-}" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
    rm -f "${BF_HOME}/.bf1942_server_download.tar" 2>/dev/null || true
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

if ! command -v dnf &> /dev/null; then
    log_error "This script requires dnf (Fedora)."
    exit 1
fi

if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [ "$ID" != "fedora" ]; then
        log_warn "This script is intended for Fedora. Detected: ${PRETTY_NAME:-unknown}"
        if ! confirm_continue; then exit 1; fi
    else
        log_info "Detected: ${PRETTY_NAME}"
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
echo -e "   ${YELLOW}★${NC} ${BOLD}BATTLEFIELD 1942 · DEDICATED SERVER${NC} ${YELLOW}★${NC}  ${C_STEEL}[Fedora]${NC}"
echo -e "   ${DIM}enhanced multi-instance setup — smart · secure · optimized${NC}"
echo -e "${C_ARMY}   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "   ${DIM}by${NC} ${BOLD}OWLCAT${NC}  ${DIM}·${NC}  ${CYAN}github.com/hootmeow/bf1942-linux${NC}  ${DIM}·${NC}  ${C_KHAKI}www.bf1942.online${NC}"
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
    read -r -p "Enter your choice [1 or 2]: " mode_choice

    case "$mode_choice" in
        1) INSTALL_MODE="standalone" ;;
        2) INSTALL_MODE="bfsmd" ;;
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
            read -r -p "Enter instance name (3-20 chars): " INSTANCE_NAME
            if validate_instance_name "$INSTANCE_NAME"; then
                break
            fi
        done
    fi
else
    INSTANCE_NAME="default"
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
    if ! check_port_available 14567 udp || ! check_port_available 23000 udp; then
        log_error "Port 14567/udp or 23000/udp is already in use."
        log_error "Stop the process using it (a running standalone server?) and re-run."
        exit 1
    fi
    log_success "Ports 14567/udp and 23000/udp available"
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

    if ! validate_ports "$GAME_PORT" "$QUERY_PORT" "$MGMT_PORT" "$LAN_PORT" "$ASE_PORT" "$CONSOLE_PORT"; then
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
    if [ -z "$OPT_IP" ] && [ "$ASSUME_YES" -eq 1 ]; then
        OPT_IP="local"
    fi

    case "$OPT_IP" in
        "")
            log_info "Starting IP address selection..."
            SERVER_IP=$(select_ip_address)
            ;;
        local)
            SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "")
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
echo " Instance Name    : ${INSTANCE_NAME}"
echo " Install Path     : ${BF_ROOT}"
echo " Service Name     : ${SERVICE_NAME}"

if [ "$INSTALL_MODE" = "bfsmd" ]; then
    echo ""
    echo " Network:"
    echo "   Server IP      : ${SERVER_IP}"
    echo ""
    echo " Port Configuration:"
    echo "   Game Port      : ${GAME_PORT} (UDP)"
    echo "   Query Port     : ${QUERY_PORT} (UDP)"
    echo "   Management Port: ${MGMT_PORT} (TCP)"
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
TEMP_DIR=$(mktemp -d)

if [ -d "$BF_ROOT" ] && [ "$(ls -A "$BF_ROOT" 2>/dev/null)" ]; then
    log_warn "Target directory '$BF_ROOT' already exists and is not empty."
    if [ "$ASSUME_YES" -eq 1 ]; then
        log_warn "--yes given - overwriting."
    else
        read -r -p "Overwrite? [y/N] " confirm
        if [[ ! "$confirm" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            exit 0
        fi
    fi
fi

# ------------------------------------------------------------
# STEP 1: User Management
# ------------------------------------------------------------
log_step "1/8: Configuring service user: ${BF_USER}"

if id "$BF_USER" >/dev/null 2>&1; then
    log_info "User ${BF_USER} already exists. Skipping creation."
else
    useradd -m -s /bin/bash "$BF_USER"
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

mkdir -p "$BF_ROOT"

# ------------------------------------------------------------
# STEP 2: Dependencies
# ------------------------------------------------------------
log_step "2/8: Installing system dependencies"

if [ ! -f "/etc/bf1942_deps_installed" ]; then
    log_info "First-time setup: Installing 32-bit libraries..."

    # Detect zlib package name — Fedora 36+ ships zlib-ng; fall back to zlib
    if dnf info zlib.i686 &>/dev/null; then
        ZLIB_PKG="zlib.i686"
    else
        ZLIB_PKG="zlib-ng-compat.i686"
    fi
    log_info "Using zlib package: ${ZLIB_PKG}"

    log_info "Installing modern 32-bit libraries..."
    dnf install -y \
        glibc.i686 libstdc++.i686 libgcc.i686 \
        "${ZLIB_PKG}" libcurl.i686 libX11.i686 \
        libXext.i686 ncurses-libs.i686 \
        ncurses-compat-libs.i686 \
        wget tar curl net-tools binutils

    log_info "Installing legacy libstdc++5 (GCC 3.3 compatibility)..."

    pushd "$TEMP_DIR" > /dev/null

    # These exact builds rotate off the main mirror when Debian archives an
    # old release, so fall back to archive.debian.org before giving up.
    fetch_legacy_deb() {
        local path="$1"
        local file="${path##*/}"
        wget -q "http://deb.debian.org/debian/${path}" && return 0
        log_warn "${file} not found on deb.debian.org - trying archive.debian.org..."
        wget -q "http://archive.debian.org/debian/${path}" && return 0
        log_error "Could not download ${file} from deb.debian.org or archive.debian.org."
        return 1
    }

    fetch_legacy_deb "pool/main/g/gcc-3.3/libstdc++5_3.3.6-34_i386.deb"

    ar x libstdc++5_3.3.6-34_i386.deb
    if [ -f data.tar.xz ]; then
        tar xJf data.tar.xz
    elif [ -f data.tar.gz ]; then
        tar xzf data.tar.gz
    fi
    find . -name "libstdc++.so.5*" -not -type d -exec cp -a {} /usr/lib/ \;

    popd > /dev/null

    ldconfig

    # Restore SELinux file contexts
    if command -v restorecon >/dev/null 2>&1; then
        restorecon -Rv "${BF_HOME}" 2>/dev/null || true
    fi

    # The package steps above tolerate individual failures, so verify the
    # legacy libraries actually landed before recording success - otherwise
    # a broken install would be skipped forever on re-runs.
    if ldconfig -p | grep -q 'libstdc++\.so\.5' && ldconfig -p | grep -q 'libncurses\.so\.5'; then
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

if [ "$INSTALL_MODE" = "bfsmd" ] && { [ -n "$OPT_VERSION" ] || [ "$ASSUME_YES" -eq 1 ]; }; then
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

log_info "Downloading from: ${SERVER_TAR_URL}"

# Download to a file first (under /home, not tmpfs - the archive is large)
# so a dropped connection can't leave a half-extracted install behind.
SERVER_TAR="${BF_HOME}/.bf1942_server_download.tar"
rm -f "$SERVER_TAR"

if ! wget -q --show-progress -O "$SERVER_TAR" "$SERVER_TAR_URL"; then
    rm -f "$SERVER_TAR"
    log_error "Download failed."
    exit 1
fi

log_info "Extracting..."
if ! tar -x --strip-components=1 -C "$BF_ROOT" -f "$SERVER_TAR"; then
    rm -f "$SERVER_TAR"
    log_error "Extraction failed."
    exit 1
fi
rm -f "$SERVER_TAR"

log_success "Files extracted to ${BF_ROOT}"

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

if [ -f "fixinstall.sh" ]; then
    log_info "Executing fixinstall.sh..."
    ./fixinstall.sh
    log_success "fixinstall.sh executed."
fi

if [ "$INSTALL_MODE" = "standalone" ]; then
    SETTINGS_DIR="${BF_ROOT}/mods/bf1942/settings"
    # fixinstall.sh lower-cases every filename, so it's serversettings.con.
    if [ -f "${SETTINGS_DIR}/serversettings.con" ]; then
        log_info "Enabling XML event logging..."
        cp "${SETTINGS_DIR}/serversettings.con" "${SETTINGS_DIR}/serversettings.con.bak"
        sed -i "s/game\.serverEventLogging [0-9]*/game.serverEventLogging 1/" "${SETTINGS_DIR}/serversettings.con"
        sed -i "s/game\.serverEventLogCompression [0-9]*/game.serverEventLogCompression 0/" "${SETTINGS_DIR}/serversettings.con"
        log_success "Event logging enabled"
    fi
    # XML event logs (ev_*.xml) land here; pre-creating it lets stats
    # collectors watch the path immediately.
    mkdir -p "${BF_ROOT}/mods/bf1942/logs"
fi

if [ "$INSTALL_MODE" = "bfsmd" ]; then
    SETTINGS_DIR="${BF_ROOT}/mods/bf1942/settings"
    # fixinstall.sh lower-cases every filename, so the settings files are
    # serversettings.con / servermanager.con from here on.
    if [ -d "$SETTINGS_DIR" ] && [ -f "${SETTINGS_DIR}/serversettings.con" ]; then
        log_info "Updating server settings..."

        cp "${SETTINGS_DIR}/serversettings.con" "${SETTINGS_DIR}/serversettings.con.bak"

        sed -i "s/game\.serverPort [0-9]*/game.serverPort ${GAME_PORT}/" "${SETTINGS_DIR}/serversettings.con"
        sed -i "s/game\.serverName .*/game.serverName \"BF1942 ${INSTANCE_NAME}\"/" "${SETTINGS_DIR}/serversettings.con"
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

        cp "$SM_CON" "${SM_CON}.bak"

        # 256 random bytes so that at least 12 alphanumerics always survive
        # the tr filter (64 bytes fell short roughly one run in eight).
        CONSOLE_PASSWORD=$(dd if=/dev/urandom bs=256 count=1 2>/dev/null | tr -dc 'A-Za-z0-9' | head -c 12)

        sed -i "s/game\.serverPort [0-9]*/game.serverPort ${GAME_PORT}/" "$SM_CON"
        sed -i "s/game\.gameSpyPort [0-9]*/game.gameSpyPort ${QUERY_PORT}/" "$SM_CON"
        sed -i "s/game\.gameSpyLANPort [0-9]*/game.gameSpyLANPort ${LAN_PORT}/" "$SM_CON"
        sed -i "s/game\.ASEPort [0-9]*/game.ASEPort ${ASE_PORT}/" "$SM_CON"
        sed -i "s/manager\.consolePort [0-9]*/manager.consolePort ${CONSOLE_PORT}/" "$SM_CON"
        sed -i "s/game\.serverName .*/game.serverName \"BF1942 ${INSTANCE_NAME}\"/" "$SM_CON"
        sed -i "s/manager\.consoleUsername .*/manager.consoleUsername \"bfadmin\"/" "$SM_CON"
        sed -i "s/manager\.consolePassword .*/manager.consolePassword \"${CONSOLE_PASSWORD}\"/" "$SM_CON"
        sed -i "s/game\.serverEventLogging [0-9]*/game.serverEventLogging 1/" "$SM_CON"
        sed -i "s/game\.serverEventLogCompression [0-9]*/game.serverEventLogCompression 0/" "$SM_CON"

        echo "Remote console (instance ${INSTANCE_NAME}): port ${CONSOLE_PORT}, user bfadmin, password ${CONSOLE_PASSWORD}" >> /root/.bf1942_all_credentials.txt
        chmod 600 /root/.bf1942_all_credentials.txt 2>/dev/null || true

        log_success "Server manager settings updated"
        log_warn "Remote console: port ${CONSOLE_PORT}, user bfadmin, password ${CONSOLE_PASSWORD}"
    fi

    # Seed the BFSMD map rotation - it ships empty and BFSMD refuses to
    # start the game server without at least one level in it.
    if [ ! -s "${SETTINGS_DIR}/servermaplist.con" ]; then
        printf 'game.addLevel berlin GPM_CQ bf1942
game.setCurrentLevel berlin GPM_CQ bf1942
' > "${SETTINGS_DIR}/servermaplist.con"
        log_success "Seeded default map rotation (berlin GPM_CQ)"
    fi

    # XML event logs (ev_*.xml) land here; the engine creates it on first
    # start, but pre-creating it lets stats collectors watch it immediately.
    mkdir -p "${BF_ROOT}/mods/bf1942/logs"

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

# Restore SELinux file contexts so systemd can execute binaries in /home
if command -v restorecon >/dev/null 2>&1; then
    log_info "Restoring SELinux file contexts..."
    restorecon -Rv "${BF_HOME}" 2>/dev/null || true
fi

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

cat > "$SUDOERS_FILE" <<EOF
# Battlefield 1942 Server Management (${INSTANCE_NAME})
${BF_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl start ${SERVICE_NAME}.service
${BF_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop ${SERVICE_NAME}.service
${BF_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart ${SERVICE_NAME}.service
${BF_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl status ${SERVICE_NAME}.service
${BF_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl status ${SERVICE_NAME}.service -l
${BF_USER} ALL=(ALL) NOPASSWD: /usr/bin/journalctl -u ${SERVICE_NAME}.service
EOF

chmod 440 "$SUDOERS_FILE"
log_success "Sudoers configured"

# ------------------------------------------------------------
# STEP 8: Start Service
# ------------------------------------------------------------
log_step "8/8: Starting server"

systemctl start "${SERVICE_NAME}.service"

sleep 3

if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
    log_success "Service started successfully!"
else
    log_warn "Service may have issues. Check: systemctl status ${SERVICE_NAME}.service"
fi

# ------------------------------------------------------------
# OPTIONAL: Firewall
# ------------------------------------------------------------
echo ""
log_info "Firewall Configuration"

FIREWALL_MODE="$OPT_FIREWALL"
if [ -z "$FIREWALL_MODE" ]; then
    if [ "$ASSUME_YES" -eq 1 ]; then
        FIREWALL_MODE="skip"
    else
        read -r -p "Configure firewalld rules? [y/N] " response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            FIREWALL_MODE="ask"
        else
            FIREWALL_MODE="skip"
        fi
    fi
fi

if [ "$FIREWALL_MODE" = "skip" ]; then
    log_info "Skipping firewall configuration"
elif ! command -v firewall-cmd >/dev/null 2>&1; then
    log_warn "firewalld not found - skipping firewall configuration"
else
    if ! systemctl is-active --quiet firewalld; then
        log_info "Starting firewalld..."
        systemctl enable --now firewalld
    fi
    log_info "Configuring firewall..."

    # Keep SSH reachable in case it is missing from the active zone.
    firewall-cmd --permanent --add-service=ssh >/dev/null 2>&1 || true

    if [ "$INSTALL_MODE" = "standalone" ]; then
        firewall-cmd --permanent --add-port=14567/udp
        firewall-cmd --permanent --add-port=23000/udp
    else
        firewall-cmd --permanent --add-port=${GAME_PORT}/udp
        firewall-cmd --permanent --add-port=${QUERY_PORT}/udp

        if [ "$FIREWALL_MODE" = "ask" ]; then
            echo ""
            echo "Management Port Security:"
            echo "  1) Open to all IPs (easier, less secure)"
            echo "  2) Restrict to specific IP (more secure)"
            echo "  3) Skip (use SSH tunnel instead - most secure)"
            read -r -p "Choice [1-3, default: 1]: " mgmt_choice

            case "$mgmt_choice" in
                2)
                    read -r -p "Enter trusted IP address: " trusted_ip
                    if validate_ip "$trusted_ip"; then
                        FIREWALL_MODE="restrict=${trusted_ip}"
                    else
                        log_warn "Invalid IP, opening to all"
                        FIREWALL_MODE="open"
                    fi
                    ;;
                3) FIREWALL_MODE="tunnel" ;;
                *) FIREWALL_MODE="open" ;;
            esac
        fi

        case "$FIREWALL_MODE" in
            restrict=*)
                trusted_ip="${FIREWALL_MODE#restrict=}"
                firewall-cmd --permanent --add-rich-rule="rule family='ipv4' source address='${trusted_ip}' port protocol='tcp' port='${MGMT_PORT}' accept"
                log_success "Management port restricted to ${trusted_ip}"
                ;;
            tunnel)
                log_info "Management port NOT opened (use SSH tunnel)"
                ;;
            *)
                firewall-cmd --permanent --add-port=${MGMT_PORT}/tcp
                log_warn "Management port open to all IPs - consider using SSH tunnel"
                ;;
        esac
    fi

    firewall-cmd --reload
    log_success "Firewall configured"
fi

# ------------------------------------------------------------
# SAVE & DISPLAY CREDENTIALS
# ------------------------------------------------------------
if [ "$INSTALL_MODE" = "bfsmd" ]; then
    CRED_FILE=$(save_credentials "$INSTANCE_NAME" "$ADMIN_USERNAME" "$ADMIN_PASSWORD" "$MGMT_PORT" "$SERVER_IP")
    display_credentials "$ADMIN_USERNAME" "$ADMIN_PASSWORD" "$SERVER_IP" "$MGMT_PORT" "$CRED_FILE"
fi

# ------------------------------------------------------------
# FINAL SUMMARY
# ------------------------------------------------------------
cls
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║${NC}                  ${GREEN}${BOLD}✔  MISSION ACCOMPLISHED${NC}                   ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}                   ${DIM}installation complete${NC}                    ${GREEN}║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"

echo ""
hr
echo -e "   ${BOLD}BF1942 Server Installation Summary${NC}"
hr
echo " Installation Mode: ${INSTALL_MODE}"
echo " Instance Name    : ${INSTANCE_NAME}"
echo " Install Path     : ${BF_ROOT}"
echo " Service Name     : ${SERVICE_NAME}"
echo " Service User     : ${BF_USER}"

if [ "$INSTALL_MODE" = "bfsmd" ]; then
    echo ""
    echo " Server IP        : ${SERVER_IP}"
    echo " CPU Affinity     : Cores ${CPU_AFFINITY}"
    echo ""
    echo " Port Configuration:"
    echo "   Game Port      : ${GAME_PORT} (UDP)"
    echo "   Query Port     : ${QUERY_PORT} (UDP)"
    echo "   Management Port: ${MGMT_PORT} (TCP)"
    echo ""
    echo -e " ${GREEN}✓${NC} Default credentials configured"
    echo -e " ${CYAN}Credentials file: ${CRED_FILE}${NC}"
fi

echo ""
echo " Management Commands:"
echo "   sudo systemctl status ${SERVICE_NAME}.service"
echo "   sudo systemctl restart ${SERVICE_NAME}.service"
echo "   journalctl -u ${SERVICE_NAME}.service -f"

if [ "$INSTALL_MODE" = "bfsmd" ]; then
    echo ""
    echo -e " ${BLUE}ℹ NOTE${NC}"
    echo " 'Internal error!' messages during startup are normal"
    echo " and can be safely ignored (known BFSMD bug)."
fi

if [ "$INSTALL_MODE" = "bfsmd" ]; then
    echo ""
    echo " To create additional instances:"
    echo "   sudo $0 [instance_name]"
fi

hr
echo ""
echo "For support: https://github.com/hootmeow/bf1942-linux"
echo ""
echo -e "${C_SAND}${BOLD}Happy gaming!${NC} 🎮"
echo ""
