#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  Battlefield 1942 Linux Server - Unified Setup Script
#
#  Features:
#    ✓ Smart IP detection (LAN, NAT, public scenarios)
#    ✓ Comprehensive input validation
#    ✓ CPU affinity & performance tuning
#    ✓ Multi-instance support
#    ✓ Standalone or BFSMD modes
#
#  Usage: 
#    Standalone: sudo ./bf1942_unified_setup.sh
#    BFSMD:      sudo ./bf1942_unified_setup.sh [instance_name]
#
#  Author: OWLCAT (https://github.com/hootmeow / www.bf1942.online)
# ---------------------------------------------------------------------------

set -euo pipefail
umask 022

# Configuration
BF_USER="bf1942_user"
BF_HOME="/home/${BF_USER}"

# Colors
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\e[34m'
CYAN='\e[36m'
MAGENTA='\e[35m'
BOLD='\e[1m'
NC='\e[0m'

log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_step() { echo -e "${CYAN}${BOLD}[STEP]${NC} $1"; }

# ------------------------------------------------------------
# V2.5 UTILITY FUNCTIONS
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
    echo "==================================================" >&2
    echo "   IP Address Configuration" >&2
    echo "==================================================" >&2
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
        return 1
    fi
    
    return 0
}

check_resources() {
    log_step "Checking system resources..."
    
    local total_ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_ram_mb=$((total_ram_kb / 1024))
    
    if [ "$total_ram_mb" -lt 1024 ]; then
        log_error "Insufficient RAM: ${total_ram_mb}MB (minimum: 1024MB)"
        return 1
    else
        log_success "RAM: ${total_ram_mb}MB"
    fi
    
    local available_space_kb=$(df /home | tail -1 | awk '{print $4}')
    local available_space_gb=$((available_space_kb / 1024 / 1024))
    
    if [ "$available_space_gb" -lt 5 ]; then
        log_error "Insufficient disk space: ${available_space_gb}GB (minimum: 5GB)"
        return 1
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
        read -r -p "Continue anyway? [y/N] " confirm
        if [[ ! "$confirm" =~ ^([yY][eE][sS]|[yY])$ ]]; then
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
    
    local cred_dir="${BF_HOME}/credentials"
    mkdir -p "$cred_dir"
    chmod 700 "$cred_dir"

    local cred_file="${cred_dir}/${instance}.txt"
    
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
    
    local master_file="${cred_dir}/all_credentials.txt"
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
    chown -R "${BF_USER}:${BF_USER}" "$cred_dir" 2>/dev/null || true

    echo "$cred_file"
}

display_credentials() {
    local username="$1"
    local password="$2"
    local server_ip="$3"
    local mgmt_port="$4"
    local cred_file="$5"
    
    clear
    cat << "EOF"
╔════════════════════════════════════════════════════════════╗
║                                                            ║
║              🔐 IMPORTANT: DEFAULT CREDENTIALS             ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝
EOF
    
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
    echo "Press ENTER to continue..."
    read -r
}

download_file() {
    local url="$1"
    local output="$2"

    if command -v curl >/dev/null 2>&1; then
        curl --fail --location --silent --show-error \
            --proto '=https' --tlsv1.2 --retry 3 --retry-delay 2 \
            -o "$output" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget --https-only --secure-protocol=TLSv1_2 --tries=3 -q -O "$output" "$url"
    else
        log_error "Neither curl nor wget is available for downloading files."
        return 1
    fi
}

# ------------------------------------------------------------
# PRE-FLIGHT CHECKS
# ------------------------------------------------------------

if [[ $EUID -ne 0 ]]; then
   log_error "This script requires admin privileges. Please run with sudo:"
   echo "        sudo $0 $*"
   exit 1
fi

if ! command -v apt-get &> /dev/null; then
    log_error "This script requires apt-get (Ubuntu/Debian)."
    exit 1
fi

if ! check_resources; then
    log_error "System does not meet minimum requirements."
    exit 1
fi

# ------------------------------------------------------------
# BANNER
# ------------------------------------------------------------
clear
cat << "EOF"
╔════════════════════════════════════════════════════════════╗
║                                                            ║
║   ██████╗ ███████╗ ██╗ █████╗  ██╗  ██╗██████╗             ║
║   ██╔══██╗██╔════╝███║██╔══██╗ ██║  ██║╚════██╗            ║
║   ██████╔╝█████╗  ╚██║╚██████║ ███████║ █████╔╝            ║
║   ██╔══██╗██╔══╝   ██║ ╚═══██║ ╚════██║██╔═══╝             ║
║   ██████╔╝██║      ██║ █████╔╝      ██║███████╗            ║
║   ╚═════╝ ╚═╝      ╚═╝ ╚════╝       ╚═╝╚══════╝            ║
║                                                            ║
║           Enhanced Multi-Instance Setup                    ║
║        Smart • Secure • Optimized                          ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝
EOF
echo ""

# ------------------------------------------------------------
# INSTALLATION MODE
# ------------------------------------------------------------
INSTANCE_NAME="${1:-}"
INSTALL_MODE=""

if [ -z "$INSTANCE_NAME" ]; then
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
        1)
            INSTALL_MODE="standalone"
            INSTANCE_NAME="default"
            ;;
        2)
            INSTALL_MODE="bfsmd"
            while true; do
                echo ""
                read -r -p "Enter instance name (3-20 chars): " INSTANCE_NAME
                if validate_instance_name "$INSTANCE_NAME"; then
                    break
                fi
            done
            ;;
        *)
            log_error "Invalid choice. Exiting."
            exit 1
            ;;
    esac
else
    INSTALL_MODE="bfsmd"
    if ! validate_instance_name "$INSTANCE_NAME"; then
        exit 1
    fi
fi

# ------------------------------------------------------------
# SET PATHS AND PORTS
# ------------------------------------------------------------
if [ "$INSTALL_MODE" = "standalone" ]; then
    BF_ROOT="${BF_HOME}/bf1942"
    SERVICE_NAME="bf1942"
    SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
else
    BF_BASE="${BF_HOME}/instances"
    BF_ROOT="${BF_BASE}/${INSTANCE_NAME}"
    SERVICE_NAME="bfsmd-${INSTANCE_NAME}"
    SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
    
    INSTANCE_HASH=$(echo -n "$INSTANCE_NAME" | cksum | cut -d' ' -f1)
    INSTANCE_ID=$((INSTANCE_HASH % 100))
    GAME_PORT=$((14567 + INSTANCE_ID))
    QUERY_PORT=$((23000 + INSTANCE_ID))
    MGMT_PORT=$((14667 + INSTANCE_ID))
    
    if ! validate_ports "$GAME_PORT" "$QUERY_PORT" "$MGMT_PORT"; then
        log_error "Port conflict detected. Try a different instance name."
        exit 1
    fi
    
    log_info "Calculating CPU affinity..."
    
    # Calculate CPU affinity
    INSTANCE_NUM=0
    if [ -d "${BF_HOME}/instances" ]; then
        INSTANCE_NUM=$(find "${BF_HOME}/instances" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
    fi
    CPU_AFFINITY=$(calculate_cpu_affinity "$INSTANCE_NUM")
    
    log_success "CPU affinity: ${CPU_AFFINITY}"
fi

SUDOERS_FILE="/etc/sudoers.d/bf1942_${INSTANCE_NAME}"

# ------------------------------------------------------------
# NETWORK CONFIGURATION
# ------------------------------------------------------------
if [ "$INSTALL_MODE" = "bfsmd" ]; then
    log_info "Starting IP address selection..."
    
    SERVER_IP=$(select_ip_address)
    
    # Debug: verify IP was captured correctly
    if [ -z "$SERVER_IP" ]; then
        log_error "Failed to capture server IP"
        echo "Debug: SERVER_IP is empty" >&2
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
echo "=================================================="
echo "   Installation Configuration"
echo "=================================================="
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

echo "=================================================="
echo ""
read -r -p "Continue with this configuration? [y/N] " confirm
if [[ ! "$confirm" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    log_warn "Installation cancelled."
    exit 0
fi

# ------------------------------------------------------------
# SAFETY: Cleanup Trap
# ------------------------------------------------------------
TEMP_DIR=$(mktemp -d)

cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
}
trap cleanup EXIT

if [ -d "$BF_ROOT" ] && [ "$(ls -A "$BF_ROOT" 2>/dev/null)" ]; then
    log_warn "Target directory '$BF_ROOT' already exists and is not empty."
    read -r -p "Overwrite? [y/N] " confirm
    if [[ ! "$confirm" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        exit 0
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
    
    echo ""
    log_warn "You must set a password for ${BF_USER} to allow manual login."
    
    if ! passwd "$BF_USER"; then
        echo ""
        log_error "Password setup failed. Script aborted."
        exit 1
    fi
fi

mkdir -p "$BF_ROOT"

# ------------------------------------------------------------
# STEP 2: Dependencies
# ------------------------------------------------------------
log_step "2/8: Installing system dependencies"

if [ ! -f "/etc/bf1942_deps_installed" ]; then
    log_info "First-time setup: Installing i386 architecture and libraries..."
    
    dpkg --add-architecture i386
    apt-get update -y
    
    log_info "Installing modern 32-bit libraries..."
    apt-get install -y --no-install-recommends \
        libc6:i386 libstdc++6:i386 libgcc-s1:i386 \
        zlib1g:i386 libcurl4t64:i386 libxext6:i386 \
        libx11-6:i386 libncurses6:i386 wget tar curl net-tools
    
    log_info "Installing legacy libraries..."
    
    pushd "$TEMP_DIR" > /dev/null
    
    DEB_NCURSES="https://deb.debian.org/debian/pool/main/n/ncurses"
    DEB_GCC="https://deb.debian.org/debian/pool/main/g/gcc-3.3"

    download_file "${DEB_NCURSES}/libtinfo5_6.2+20201114-2+deb11u2_i386.deb" "libtinfo5.deb"
    download_file "${DEB_NCURSES}/libncurses5_6.2+20201114-2+deb11u2_i386.deb" "libncurses5.deb"
    download_file "${DEB_GCC}/libstdc++5_3.3.6-34_i386.deb" "libstdc++5.deb"
    
    dpkg -i libtinfo5.deb libncurses5.deb libstdc++5.deb || true
    ldconfig
    
    popd > /dev/null
    
    touch /etc/bf1942_deps_installed
    log_success "Dependencies installed."
else
    log_info "Dependencies already installed. Skipping."
fi

# ------------------------------------------------------------
# STEP 3: Server Version Selection
# ------------------------------------------------------------
log_step "3/8: Selecting server version"

if [ "$INSTALL_MODE" = "bfsmd" ]; then
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

SERVER_TAR_PATH="${TEMP_DIR}/server.tar"
if ! download_file "$SERVER_TAR_URL" "$SERVER_TAR_PATH"; then
    log_error "Download failed."
    exit 1
fi

if ! tar -xf "$SERVER_TAR_PATH" --strip-components=1 --no-same-owner -C "$BF_ROOT"; then
    log_error "Extraction failed."
    exit 1
fi

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

if [ "$INSTALL_MODE" = "bfsmd" ]; then
    SETTINGS_DIR="${BF_ROOT}/mods/bf1942/settings"
    if [ -d "$SETTINGS_DIR" ] && [ -f "${SETTINGS_DIR}/ServerSettings.con" ]; then
        log_info "Updating server settings..."
        
        cp "${SETTINGS_DIR}/ServerSettings.con" "${SETTINGS_DIR}/ServerSettings.con.bak"
        
        sed -i "s/game\.serverPort [0-9]*/game.serverPort ${GAME_PORT}/" "${SETTINGS_DIR}/ServerSettings.con"
        sed -i "s/game\.serverName .*/game.serverName \"BF1942 ${INSTANCE_NAME}\"/" "${SETTINGS_DIR}/ServerSettings.con"
        
        log_success "Server settings updated"
    fi
    
    # Don't modify useraccess.con - it already has the correct default hash
    # Just set credentials for display to user
    ADMIN_USERNAME="bf1942"
    ADMIN_PASSWORD="battlefield"
    
    log_info "Default admin credentials: bf1942/battlefield"
    log_warn "CRITICAL: Change password via BFRM immediately after first login!"
fi

chown -R "${BF_USER}:${BF_USER}" "${BF_HOME}"

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
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths=${BF_ROOT}
ProtectKernelTunables=true
ProtectControlGroups=true
RestrictSUIDSGID=true
LockPersonality=true

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
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths=${BF_ROOT}
ProtectKernelTunables=true
ProtectControlGroups=true
RestrictSUIDSGID=true
LockPersonality=true

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
${BF_USER} ALL=(ALL) NOPASSWD: /usr/bin/journalctl -u ${SERVICE_NAME}.service -f
${BF_USER} ALL=(ALL) NOPASSWD: /usr/bin/journalctl -u ${SERVICE_NAME}.service -n [0-9]*
${BF_USER} ALL=(ALL) NOPASSWD: /usr/bin/journalctl -u ${SERVICE_NAME}.service --no-pager
${BF_USER} ALL=(ALL) NOPASSWD: /usr/bin/journalctl -u ${SERVICE_NAME}.service -f --no-pager
${BF_USER} ALL=(ALL) NOPASSWD: /usr/bin/journalctl -u ${SERVICE_NAME}.service -n [0-9]* --no-pager
EOF

chmod 440 "$SUDOERS_FILE"
if visudo -cf "$SUDOERS_FILE" >/dev/null; then
    log_success "Sudoers configured"
else
    log_error "Generated sudoers file is invalid. Removing it for safety."
    rm -f "$SUDOERS_FILE"
    exit 1
fi

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
read -r -p "Configure UFW firewall rules? [y/N] " response

if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    if command -v ufw >/dev/null; then
        log_info "Configuring firewall..."
        
        if [ "$INSTALL_MODE" = "standalone" ]; then
            ufw allow 14567/udp comment 'BF1942 Game'
            ufw allow 23000/udp comment 'BF1942 Query'
        else
            ufw allow ${GAME_PORT}/udp comment "BF1942 ${INSTANCE_NAME} Game"
            ufw allow ${QUERY_PORT}/udp comment "BF1942 ${INSTANCE_NAME} Query"
            
            # Management port configuration
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
                        ufw allow from ${trusted_ip} to any port ${MGMT_PORT} proto tcp comment "BFSMD ${INSTANCE_NAME} Mgmt"
                        log_success "Management port restricted to ${trusted_ip}"
                    else
                        log_warn "Invalid IP, opening to all"
                        ufw allow ${MGMT_PORT}/tcp comment "BFSMD ${INSTANCE_NAME} Mgmt"
                    fi
                    ;;
                3)
                    log_info "Management port NOT opened (use SSH tunnel)"
                    ;;
                *)
                    ufw allow ${MGMT_PORT}/tcp comment "BFSMD ${INSTANCE_NAME} Mgmt"
                    log_warn "Management port open to all IPs - consider using SSH tunnel"
                    ;;
            esac
        fi
        
        ufw --force enable
        ufw reload
        log_success "Firewall configured"
    else
        log_warn "UFW not installed"
    fi
else
    log_info "Skipping firewall configuration"
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
clear
cat << "EOF"
╔════════════════════════════════════════════════════════════╗
║                                                            ║
║              ✓ Installation Complete!                     ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝
EOF

echo ""
echo "=================================================="
echo "   BF1942 Server Installation Summary"
echo "=================================================="
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

echo "=================================================="
echo ""
echo "For support: https://github.com/hootmeow/bf1942-linux"
echo ""
echo "Happy gaming! 🎮"
echo ""
