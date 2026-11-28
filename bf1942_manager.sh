#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  BF1942 Multi-Instance Manager
#
#  Purpose:
#    Manage multiple BF1942 server instances on a single machine
#
#  Usage: ./bf1942_manager.sh [command] [instance_name]
#         ./bf1942_manager.sh          (no command: interactive menu)
#
# ---------------------------------------------------------------------------

set -euo pipefail

VERSION="2.1"

BF_USER="bf1942_user"
BF_BASE="/home/${BF_USER}/instances"
BF_STANDALONE="/home/${BF_USER}/bf1942"

# Colors & formatting: use ANSI-C quoting ($'\e[...') so escape codes render properly in terminals
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != "dumb" ]; then
    RED=$'\e[31m'
    GREEN=$'\e[32m'
    YELLOW=$'\e[33m'
    BLUE=$'\e[34m'
    CYAN=$'\e[36m'
    BOLD=$'\e[1m'
    NC=$'\e[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    BOLD=''
    NC=''
fi

log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }

# Check if running as root when needed
require_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This operation requires root privileges. Please run with sudo."
        exit 1
    fi
}

# Match the installer's naming rules before using a name in paths or units.
validate_instance_name() {
    local name="$1"
    if [ "$name" = "default" ] || [[ "$name" =~ ^[a-zA-Z][a-zA-Z0-9_-]{2,19}$ ]]; then
        return 0
    fi
    log_error "Invalid instance name '$name' (expected 3-20 letters, digits, dashes, or underscores, starting with a letter)."
    return 1
}

# Written by the installer: one "name=id" line per instance
INSTANCE_REGISTRY="/etc/bf1942_instances.conf"

# First hash field of the stock useraccess.con shipped in the server tar.
# Its presence means the default bf1942/battlefield account is still active
# (the file stores hashes, so the plaintext password never appears in it).
DEFAULT_ACCESS_HASH="0C9CB6FC1E3B366C190BA57A52498A5162913A0D4C29B31A0A7A5B432F9884F0"

# Get instance ID: prefer the persistent registry, fall back to the legacy
# name hash for instances created before the registry existed.
get_instance_id() {
    local name="$1"
    local id=""
    if [ -f "$INSTANCE_REGISTRY" ]; then
        id=$(awk -F= -v n="$name" '$1==n{print $2; exit}' "$INSTANCE_REGISTRY")
    fi
    if [ -z "$id" ]; then
        local hash=$(echo -n "$name" | cksum | cut -d' ' -f1)
        id=$((hash % 100))
    fi
    echo "$id"
}

# Read ports from the instance's actual configuration (servermanager.con and
# the systemd unit); fall back to ID-derived defaults for anything missing,
# so manual port edits are reported truthfully.
# Prints: game query mgmt lan ase console
get_ports() {
    local name="$1"
    local con="${BF_BASE}/${name}/mods/bf1942/settings/servermanager.con"
    local unit="/etc/systemd/system/bfsmd-${name}.service"
    local game="" query="" mgmt="" lan="" ase="" console=""

    if [ -f "$con" ]; then
        game=$(con_value "$con" game.serverPort)
        query=$(con_value "$con" game.gameSpyPort)
        lan=$(con_value "$con" game.gameSpyLANPort)
        ase=$(con_value "$con" game.ASEPort)
        console=$(con_value "$con" manager.consolePort)
    fi
    if [ -f "$unit" ]; then
        mgmt=$(sed -n 's/.*-port \([0-9]\{1,\}\).*/\1/p' "$unit" | head -1)
    fi

    local id
    id=$(get_instance_id "$name")
    echo "${game:-$((14567 + id))} ${query:-$((23000 + id))} ${mgmt:-$((14667 + id))}" \
         "${lan:-$((22000 + id))} ${ase:-$((14690 + id))} ${console:-$((4711 + id))}"
}

# First numeric value of a "key value" line in a .con file.
con_value() {
    awk -v k="$2" '$1==k && $2 ~ /^[0-9]+\r?$/ {sub(/\r$/, "", $2); print $2; exit}' "$1"
}

# IP the instance's BFSMD is bound to (the -ip flag in its unit).
get_bind_ip() {
    local unit="/etc/systemd/system/bfsmd-${1}.service" ip=""
    if [ -f "$unit" ]; then
        ip=$(sed -n 's/.*-ip \([0-9.]\{7,15\}\).*/\1/p' "$unit" | head -1)
    fi
    echo "${ip:-127.0.0.1}"
}

# Ask the game server itself for its status via the GameSpy query port.
# Prints "hostname|map|players|maxplayers" and returns 0 when it answers.
# A running systemd unit only proves BFSMD is up - the game server it
# launches can still be crashed, stuck loading, or refusing to start.
query_server() {
    local ip="$1" port="$2" reply
    reply=$(timeout 3 bash -c '
        exec 3<>"/dev/udp/$1/$2" || exit 1
        printf "\\status\\" >&3
        # One datagram is enough: GameSpy sends the server info first.
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

# Check if service file exists
service_exists() {
    local service="$1"
    [ -f "/etc/systemd/system/${service}" ]
}

# Discover all instance names across filesystem, registry, and systemd units
get_instance_names() {
    local -A seen
    local names=()

    # 1. From directory if accessible
    if [ -d "$BF_BASE" ] && [ -r "$BF_BASE" ]; then
        for instance_dir in "$BF_BASE"/*; do
            if [ -d "$instance_dir" ]; then
                local iname
                iname=$(basename "$instance_dir")
                if [ -n "$iname" ] && [ -z "${seen[$iname]:-}" ]; then
                    seen["$iname"]=1
                    names+=("$iname")
                fi
            fi
        done
    fi

    # 2. From registry file (/etc/bf1942_instances.conf)
    if [ -f "$INSTANCE_REGISTRY" ] && [ -r "$INSTANCE_REGISTRY" ]; then
        while IFS='=' read -r iname iid || [ -n "$iname" ]; do
            [[ "$iname" =~ ^#.*$ || -z "$iname" ]] && continue
            if [ -z "${seen[$iname]:-}" ]; then
                seen["$iname"]=1
                names+=("$iname")
            fi
        done < "$INSTANCE_REGISTRY"
    fi

    # 3. From active systemd services (bfsmd-*.service)
    for service_unit in /etc/systemd/system/bfsmd-*.service; do
        if [ -f "$service_unit" ]; then
            local iname
            iname=$(basename "$service_unit" .service | sed 's/^bfsmd-//')
            if [ -n "$iname" ] && [ "$iname" != "*" ] && [ -z "${seen[$iname]:-}" ]; then
                seen["$iname"]=1
                names+=("$iname")
            fi
        fi
    done

    echo "${names[@]:-}"
}

# Port block shared by status and config.
print_instance_ports() {
    echo "  Game Port      : $1 (UDP)  public - players connect here"
    echo "  Query Port     : $2 (UDP)  public - server browsers"
    echo "  Management Port: $3 (TCP)  BFRM admin - restrict or SSH-tunnel"
    echo "  Remote Console : $6 (TCP)  admin only - keep closed"
    echo "  GameSpy LAN    : $4 (UDP)  LAN discovery only"
    echo "  ASE Port       : $5 (UDP)  legacy, not needed"
}

# One health line for a service that systemd reports as running.
report_game_health() {
    local label="$1" ip="$2" port="$3" reply
    if reply=$(query_server "$ip" "$port"); then
        IFS='|' read -r q_host q_map q_players q_max <<< "$reply"
        echo -e "  ${GREEN}✓${NC} $label - Running, ${q_players}/${q_max} players on ${q_map}"
        return 0
    fi
    echo -e "  ${YELLOW}⚠${NC} $label - Service up, but the game server is not answering on ${ip}:${port}/udp"
    echo "      (still loading after a restart, crashed, or BFSMD could not start it - check BFRM / logs)"
    return 1
}

# List all instances
list_instances() {
    echo -e "${BOLD}BF1942 Server Instances${NC}"
    echo ""
    
    local found=0
    
    # Check for standalone server
    if [ -d "$BF_STANDALONE" ] && service_exists "bf1942.service"; then
        local status=$(systemctl is-active bf1942.service 2>/dev/null || echo "inactive")
        local enabled=$(systemctl is-enabled bf1942.service 2>/dev/null || echo "disabled")
        
        local status_color="${RED}"
        [ "$status" == "active" ] && status_color="${GREEN}"
        
        printf "  ${CYAN}%-20s${NC} ${status_color}%-10s${NC} (${enabled}) ${YELLOW}[STANDALONE]${NC}\n" \
            "default" "$status"
        found=1
    fi
    
    # Check for BFSMD instances
    local instance_names=($(get_instance_names))
    for name in "${instance_names[@]}"; do
        [ -z "$name" ] && continue
        local service="bfsmd-${name}.service"
        
        if service_exists "$service"; then
            local status=$(systemctl is-active "$service" 2>/dev/null || echo "inactive")
            local enabled=$(systemctl is-enabled "$service" 2>/dev/null || echo "disabled")
            
            local status_color="${RED}"
            [ "$status" == "active" ] && status_color="${GREEN}"
            
            read -r game_port query_port mgmt_port lan_port ase_port console_port <<< "$(get_ports "$name")"
            
            printf "  ${CYAN}%-20s${NC} ${status_color}%-10s${NC} (${enabled}) [Game:%-5s Query:%-5s Mgmt:%-5s]\n" \
                "$name" "$status" "$game_port" "$query_port" "$mgmt_port"
            found=1
        else
            printf "  ${CYAN}%-20s${NC} ${RED}%-10s${NC} (no service)\n" "$name" "ERROR"
            found=1
        fi
    done
    
    if [ $found -eq 0 ]; then
        log_warn "No instances found."
        echo ""
        echo "To create an instance (detects your distro automatically):"
        echo "  sudo bash install.sh [instance_name]"
        echo ""
        echo "Or run the installer for your distro directly:"
        echo "  sudo ./installers/arch/arch_bfsmd_setup.sh         [instance_name]"
        echo "  sudo ./installers/ubuntu/ubu_24.0.3_bfsmd_setup.sh [instance_name]"
        echo "  sudo ./installers/ubuntu/ubu_22.04_bfsmd_setup.sh  [instance_name]"
        echo "  sudo ./installers/debian/deb_12_bfsmd_setup.sh     [instance_name]"
        echo "  sudo ./installers/fedora/fed_44_bfsmd_setup.sh     [instance_name]"
        echo "  sudo ./installers/rhel/rhel_9_bfsmd_setup.sh       [instance_name]"
        echo "  sudo ./installers/centos/centos_stream9_bfsmd_setup.sh [instance_name]"
    fi
    
    echo ""
}

# Show port assignments
show_ports() {
    echo -e "${BOLD}Port Assignments${NC}"
    echo ""
    local fmt="%-20s %-9s %-9s %-9s %-9s %-9s %-9s\n"
    printf "$fmt" "Instance" "Game" "Query" "Mgmt" "Console" "LAN" "ASE"
    printf "$fmt" "" "udp" "udp" "tcp" "tcp" "udp" "udp"
    printf "$fmt" "--------" "----" "-----" "----" "-------" "---" "---"

    # Standalone
    if [ -d "$BF_STANDALONE" ] && service_exists "bf1942.service"; then
        printf "$fmt" "default" "14567" "23000" "-" "-" "22000" "14690"
    fi

    # BFSMD instances
    local instance_names=($(get_instance_names))
    for name in "${instance_names[@]}"; do
        [ -z "$name" ] && continue
        read -r game_port query_port mgmt_port lan_port ase_port console_port <<< "$(get_ports "$name")"
        printf "$fmt" "$name" "$game_port" "$query_port" "$mgmt_port" "$console_port" "$lan_port" "$ase_port"
    done

    echo ""
    echo "Players need Game + Query open. Mgmt (BFRM) and Console are admin-only:"
    echo "restrict them to trusted IPs or use an SSH tunnel. LAN/ASE can stay closed."
    echo ""
}

# Show detailed status
show_status() {
    local name="${1:-}"
    
    if [ -z "$name" ]; then
        list_instances
        return
    fi
    
    # Check if standalone
    if [ "$name" = "default" ] && [ -d "$BF_STANDALONE" ]; then
        if ! service_exists "bf1942.service"; then
            log_error "Standalone service not found."
            exit 1
        fi
        
        echo ""
        systemctl status bf1942.service --no-pager -l
        echo ""
        log_info "Configuration: $BF_STANDALONE/mods/bf1942/settings/"
        return
    fi
    
    # Check BFSMD instance
    local service="bfsmd-${name}.service"
    
    if ! service_exists "$service"; then
        log_error "Instance '$name' not found or service file missing."
        echo ""
        log_info "Available instances:"
        list_instances
        exit 1
    fi
    
    echo ""
    systemctl status "$service" --no-pager -l
    echo ""
    
    read -r game_port query_port mgmt_port lan_port ase_port console_port <<< "$(get_ports "$name")"
    log_info "Port Configuration:"
    print_instance_ports "$game_port" "$query_port" "$mgmt_port" "$lan_port" "$ase_port" "$console_port"
    echo ""
    local reply
    if reply=$(query_server "$(get_bind_ip "$name")" "$query_port"); then
        IFS='|' read -r q_host q_map q_players q_max <<< "$reply"
        log_success "Game server answering: \"${q_host}\" - ${q_map}, ${q_players}/${q_max} players"
    elif systemctl is-active --quiet "$service"; then
        log_warn "Game server not answering on query port ${query_port} (still loading, or crashed - see BFRM / logs)"
    fi
    echo ""
    log_info "Configuration: ${BF_BASE}/${name}/mods/bf1942/settings/"
}

# Show configuration info
show_config() {
    local name="$1"
    
    if [ "$name" = "default" ] && [ -d "$BF_STANDALONE" ]; then
        echo -e "${BOLD}Configuration for: default (standalone)${NC}"
        echo ""
        echo "Install Path: $BF_STANDALONE"
        echo "Settings:     $BF_STANDALONE/mods/bf1942/settings/"
        echo "Service File: /etc/systemd/system/bf1942.service"
        echo ""
        echo "Key Files:"
        echo "  - serversettings.con (game settings)"
        echo "  - maplist.con (map rotation)"
        echo ""
        return
    fi
    
    if [ ! -d "${BF_BASE}/${name}" ]; then
        log_error "Instance '$name' not found."
        exit 1
    fi
    
    echo -e "${BOLD}Configuration for: ${name}${NC}"
    echo ""
    echo "Install Path: ${BF_BASE}/${name}"
    echo "Settings:     ${BF_BASE}/${name}/mods/bf1942/settings/"
    echo "Service File: /etc/systemd/system/bfsmd-${name}.service"
    echo ""
    
    read -r game_port query_port mgmt_port lan_port ase_port console_port <<< "$(get_ports "$name")"
    echo "Ports:"
    print_instance_ports "$game_port" "$query_port" "$mgmt_port" "$lan_port" "$ase_port" "$console_port"
    echo ""
    echo "Key Files:"
    echo "  - servermanager.con (BFSMD settings)"
    echo "  - useraccess.con (admin accounts)"
    echo "  - serversettings.con (game settings)"
    echo "  - servermaplist.con (map rotation - BFSMD reads this, not maplist.con)"
    echo ""
}

# Health check
health_check() {
    echo -e "${BOLD}Health Check${NC}"
    echo ""
    
    local total=0
    local active=0
    local issues=0
    
    # Check standalone
    if [ -d "$BF_STANDALONE" ] && service_exists "bf1942.service"; then
        total=$((total + 1))
        if systemctl is-active --quiet bf1942.service; then
            if report_game_health "default (standalone)" "127.0.0.1" 23000; then
                active=$((active + 1))
            else
                issues=$((issues + 1))
            fi
        else
            issues=$((issues + 1))
            echo -e "  ${RED}✗${NC} default (standalone) - Not running"
        fi
    fi
    
    # Check BFSMD instances
    local instance_names=($(get_instance_names))
    for name in "${instance_names[@]}"; do
        [ -z "$name" ] && continue
        local service="bfsmd-${name}.service"
        
        if service_exists "$service"; then
            total=$((total + 1))
            if systemctl is-active --quiet "$service"; then
                local query_port
                query_port=$(get_ports "$name" | awk '{print $2}')
                if report_game_health "$name" "$(get_bind_ip "$name")" "$query_port"; then
                    active=$((active + 1))
                else
                    issues=$((issues + 1))
                fi
            else
                issues=$((issues + 1))
                echo -e "  ${RED}✗${NC} $name - Not running"
            fi
        fi
    done
    
    echo ""
    echo "Summary: $active/$total game servers running and answering queries"
    
    if [ $issues -gt 0 ]; then
        log_warn "$issues instance(s) have issues"
    else
        log_success "All instances healthy"
    fi
    echo ""
    patch_hint
}

# Security audit
security_audit() {
    echo -e "${BOLD}Security Audit${NC}"
    echo ""
    
    local issues=0
    local warnings=0
    
    # Check if running as root
    echo -e "${CYAN}Process Ownership Check:${NC}"
    if [ -d "$BF_BASE" ]; then
        for instance_dir in "$BF_BASE"/*; do
            if [ -d "$instance_dir" ]; then
                local name=$(basename "$instance_dir")
                local service="bfsmd-${name}.service"
                
                if service_exists "$service" && systemctl is-active --quiet "$service"; then
                    local pid=$(systemctl show -p MainPID --value "$service")
                    if [ "$pid" -gt 0 ]; then
                        local proc_user=$(ps -o user= -p "$pid" 2>/dev/null || echo "unknown")
                        if [ "$proc_user" = "root" ]; then
                            echo -e "  ${RED}✗${NC} $name - Running as ROOT (SECURITY RISK!)"
                            issues=$((issues + 1))
                        elif [ "$proc_user" = "$BF_USER" ]; then
                            echo -e "  ${GREEN}✓${NC} $name - Running as $BF_USER"
                        else
                            echo -e "  ${YELLOW}⚠${NC} $name - Running as $proc_user (unexpected)"
                            warnings=$((warnings + 1))
                        fi
                    fi
                fi
            fi
        done
    fi
    
    # Check standalone
    if service_exists "bf1942.service" && systemctl is-active --quiet bf1942.service; then
        local pid=$(systemctl show -p MainPID --value bf1942.service)
        if [ "$pid" -gt 0 ]; then
            local proc_user=$(ps -o user= -p "$pid" 2>/dev/null || echo "unknown")
            if [ "$proc_user" = "root" ]; then
                echo -e "  ${RED}✗${NC} default - Running as ROOT (SECURITY RISK!)"
                issues=$((issues + 1))
            elif [ "$proc_user" = "$BF_USER" ]; then
                echo -e "  ${GREEN}✓${NC} default - Running as $BF_USER"
            else
                echo -e "  ${YELLOW}⚠${NC} default - Running as $proc_user (unexpected)"
                warnings=$((warnings + 1))
            fi
        fi
    fi
    
    echo ""
    echo -e "${CYAN}File Ownership Check:${NC}"
    
    # Check directory ownership
    if [ -d "$BF_BASE" ]; then
        for instance_dir in "$BF_BASE"/*; do
            if [ -d "$instance_dir" ]; then
                local name=$(basename "$instance_dir")
                local owner=$(stat -c '%U' "$instance_dir")
                
                if [ "$owner" = "root" ]; then
                    echo -e "  ${RED}✗${NC} $name - Owned by ROOT (should be $BF_USER)"
                    issues=$((issues + 1))
                elif [ "$owner" = "$BF_USER" ]; then
                    echo -e "  ${GREEN}✓${NC} $name - Owned by $BF_USER"
                else
                    echo -e "  ${YELLOW}⚠${NC} $name - Owned by $owner"
                    warnings=$((warnings + 1))
                fi
            fi
        done
    fi
    
    if [ -d "$BF_STANDALONE" ]; then
        local owner=$(stat -c '%U' "$BF_STANDALONE")
        if [ "$owner" = "root" ]; then
            echo -e "  ${RED}✗${NC} default - Owned by ROOT (should be $BF_USER)"
            issues=$((issues + 1))
        elif [ "$owner" = "$BF_USER" ]; then
            echo -e "  ${GREEN}✓${NC} default - Owned by $BF_USER"
        else
            echo -e "  ${YELLOW}⚠${NC} default - Owned by $owner"
            warnings=$((warnings + 1))
        fi
    fi
    
    echo ""
    echo -e "${CYAN}Default Password Check:${NC}"
    
    # Check for default passwords
    if [ -d "$BF_BASE" ]; then
        for instance_dir in "$BF_BASE"/*; do
            if [ -d "$instance_dir" ]; then
                local name=$(basename "$instance_dir")
                local access_file="${instance_dir}/mods/bf1942/settings/useraccess.con"
                
                if [ -f "$access_file" ]; then
                    if grep -qi "$DEFAULT_ACCESS_HASH" "$access_file" 2>/dev/null; then
                        echo -e "  ${RED}✗${NC} $name - Default credentials (bf1942/battlefield) still in use!"
                        issues=$((issues + 1))
                    else
                        echo -e "  ${GREEN}✓${NC} $name - Default password changed"
                    fi
                else
                    echo -e "  ${YELLOW}⚠${NC} $name - Cannot check (file not found)"
                    warnings=$((warnings + 1))
                fi
            fi
        done
    fi
    
    echo ""
    echo -e "${CYAN}Firewall Check:${NC}"
    
    if command -v ufw >/dev/null 2>&1; then
        if ufw status | grep -q "Status: active"; then
            echo -e "  ${GREEN}✓${NC} UFW firewall is active"
            
            # Check each instance's real management port. A port-range regex
            # also matched game ports (14568-14666) and gave false warnings.
            local ufw_rules name game_port query_port mgmt_port lan_port ase_port console_port
            ufw_rules=$(ufw status 2>/dev/null || true)
            for name in $(get_instance_names); do
                [ -f "/etc/systemd/system/bfsmd-${name}.service" ] || continue
                read -r game_port query_port mgmt_port lan_port ase_port console_port <<< "$(get_ports "$name")"
                if grep -Eq "^${mgmt_port}(/tcp)?[[:space:]].*ALLOW[[:space:]]+(IN[[:space:]]+)?Anywhere" <<< "$ufw_rules"; then
                    echo -e "  ${YELLOW}⚠${NC} $name - Management port ${mgmt_port}/tcp open to the world"
                    echo "    Consider restricting to trusted IPs or using an SSH tunnel"
                    warnings=$((warnings + 1))
                fi
            done
        else
            echo -e "  ${YELLOW}⚠${NC} UFW firewall is not active"
            warnings=$((warnings + 1))
        fi
    else
        echo -e "  ${YELLOW}⚠${NC} UFW not installed"
        warnings=$((warnings + 1))
    fi
    
    echo ""
    echo "Summary:"
    if [ $issues -eq 0 ] && [ $warnings -eq 0 ]; then
        log_success "No security issues found"
    else
        [ $issues -gt 0 ] && log_error "$issues critical security issue(s) found"
        [ $warnings -gt 0 ] && log_warn "$warnings warning(s) found"
    fi
    echo ""
}

# Start instance
start_instance() {
    require_root
    local name="$1"
    
    local service
    if [ "$name" = "default" ]; then
        service="bf1942.service"
    else
        service="bfsmd-${name}.service"
    fi
    
    if ! service_exists "$service"; then
        log_error "Service $service not found."
        exit 1
    fi
    
    log_info "Starting instance '$name'..."
    systemctl start "$service"
    sleep 2
    
    if systemctl is-active --quiet "$service"; then
        log_success "Instance started successfully."
    else
        log_error "Failed to start instance. Check logs with:"
        echo "  journalctl -u $service -n 50"
    fi
}

# Stop instance
stop_instance() {
    require_root
    local name="$1"
    
    local service
    if [ "$name" = "default" ]; then
        service="bf1942.service"
    else
        service="bfsmd-${name}.service"
    fi
    
    if ! service_exists "$service"; then
        log_error "Service $service not found."
        exit 1
    fi
    
    log_info "Stopping instance '$name'..."
    systemctl stop "$service"
    log_success "Instance stopped."
}

# Restart instance
restart_instance() {
    require_root
    local name="$1"
    
    local service
    if [ "$name" = "default" ]; then
        service="bf1942.service"
    else
        service="bfsmd-${name}.service"
    fi
    
    if ! service_exists "$service"; then
        log_error "Service $service not found."
        exit 1
    fi
    
    log_info "Restarting instance '$name'..."
    systemctl restart "$service"
    sleep 2
    
    if systemctl is-active --quiet "$service"; then
        log_success "Instance restarted successfully."
    else
        log_error "Failed to restart instance. Check logs."
    fi
}

# Show logs
show_logs() {
    local name="$1"
    
    local service
    if [ "$name" = "default" ]; then
        service="bf1942.service"
    else
        service="bfsmd-${name}.service"
    fi
    
    if ! service_exists "$service"; then
        log_error "Service $service not found."
        exit 1
    fi
    
    log_info "Showing logs for instance '$name' (Press Ctrl+C to exit)..."
    sleep 1
    journalctl -u "$service" -f
}

# Remove instance
remove_instance() {
    require_root
    local name="$1"
    
    if [ "$name" = "default" ]; then
        log_error "Cannot remove default standalone instance using this command."
        log_info "To remove, manually delete /home/bf1942_user/bf1942 and service files."
        exit 1
    fi
    
    local service="bfsmd-${name}.service"
    local instance_path="${BF_BASE}/${name}"

    # Only remove a real directory directly under the instances directory.
    if [ ! -d "$instance_path" ] || [ -L "$instance_path" ]; then
        log_error "Instance '$name' is not a regular instance directory."
        exit 1
    fi
    local base_real target_real
    base_real=$(realpath -e -- "$BF_BASE")
    target_real=$(realpath -e -- "$instance_path")
    if [ "$(dirname -- "$target_real")" != "$base_real" ]; then
        log_error "Instance '$name' resolves outside $BF_BASE."
        exit 1
    fi
    
    log_warn "You are about to PERMANENTLY remove instance '$name'."
    echo "  Service: $service"
    echo "  Path: $instance_path"
    echo ""
    echo -e "${RED}${BOLD}This action CANNOT be undone!${NC}"
    echo ""
    read -r -p "Type 'yes' to confirm deletion: " confirm
    
    if [ "$confirm" != "yes" ]; then
        log_info "Removal cancelled."
        exit 0
    fi

    # Keep the base directory open so a path rename cannot redirect rm.
    pushd "$BF_BASE" >/dev/null
    if [ "$(pwd -P)" != "$base_real" ] || [ ! -d "$name" ] || [ -L "$name" ]; then
        log_error "Instance directory changed during removal; refusing to delete it."
        exit 1
    fi

    # Read the ports now - get_ports needs the config and unit files that
    # are deleted below.
    local game_port query_port mgmt_port lan_port ase_port console_port
    read -r game_port query_port mgmt_port lan_port ase_port console_port <<< "$(get_ports "$name")"

    log_info "Stopping service..."
    systemctl stop "$service" 2>/dev/null || true
    
    log_info "Disabling service..."
    systemctl disable "$service" 2>/dev/null || true
    
    log_info "Removing service file..."
    rm -f "/etc/systemd/system/$service"
    
    log_info "Removing sudoers file..."
    rm -f "/etc/sudoers.d/bf1942_${name}"

    log_info "Removing saved credentials..."
    rm -f "/root/.bf1942_credentials_${name}.txt"

    if [ -f "$INSTANCE_REGISTRY" ]; then
        log_info "Releasing instance ID..."
        sed -i "/^${name}=/d" "$INSTANCE_REGISTRY"
    fi
    
    log_info "Removing instance files..."
    rm -rf -- "$name"
    popd >/dev/null

    # Best effort: removes the plain allow rules the installer created.
    # An IP-restricted management rule ("allow from X to any port N") has to
    # be removed manually - see firewall_guide.md.
    log_info "Removing firewall rules..."
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
        ufw --force delete allow "${game_port}/udp" >/dev/null 2>&1 || true
        ufw --force delete allow "${query_port}/udp" >/dev/null 2>&1 || true
        ufw --force delete allow "${mgmt_port}/tcp" >/dev/null 2>&1 || true
    fi
    if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        firewall-cmd --permanent --remove-port="${game_port}/udp" >/dev/null 2>&1 || true
        firewall-cmd --permanent --remove-port="${query_port}/udp" >/dev/null 2>&1 || true
        firewall-cmd --permanent --remove-port="${mgmt_port}/tcp" >/dev/null 2>&1 || true
        firewall-cmd --reload >/dev/null 2>&1 || true
    fi

    log_info "Reloading systemd..."
    systemctl daemon-reload

    log_success "Instance '$name' has been removed."
}

# Backup instance
backup_instance() {
    require_root
    local name="${1:-}"

    if [ -z "$name" ]; then
        log_error "Instance name required."
        echo "Usage: $0 backup <instance_name>"
        exit 1
    fi
    
    local instance_dir="${BF_BASE}/${name}"
    
    if [ ! -d "$instance_dir" ]; then
        log_error "Instance '$name' not found."
        exit 1
    fi
    
    local backup_file="bf1942_${name}_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
    local backup_dir="/root/bf1942_backups"
    
    mkdir -p "$backup_dir"
    
    if systemctl is-active --quiet "bfsmd-${name}.service" 2>/dev/null; then
        log_warn "Instance '$name' is running - files can change mid-backup."
        log_warn "For a guaranteed-consistent backup: sudo $0 stop ${name}"
    fi

    log_info "Creating backup of instance '$name'..."
    log_info "This may take a minute..."

    # Stage the pieces that live outside the instance directory, so the
    # backup can rebuild the instance on a clean machine (or after remove).
    local meta_parent
    meta_parent=$(mktemp -d)
    local meta_dir="${meta_parent}/${name}.meta"
    mkdir "$meta_dir"
    cp "/etc/systemd/system/bfsmd-${name}.service" "$meta_dir/" 2>/dev/null || true
    cp "/etc/sudoers.d/bf1942_${name}" "$meta_dir/" 2>/dev/null || true
    grep "^${name}=" "$INSTANCE_REGISTRY" > "${meta_dir}/registry_entry" 2>/dev/null || true

    if tar -czf "${backup_dir}/${backup_file}" -C "${BF_BASE}" "${name}" -C "${meta_parent}" "${name}.meta"; then
        rm -rf "$meta_parent"
        local size=$(du -h "${backup_dir}/${backup_file}" | cut -f1)
        log_success "Backup created: ${backup_dir}/${backup_file} (${size})"
        echo ""
        echo "To restore it (here or on another machine, after 'remove' if it still exists):"
        echo "  sudo $0 restore ${backup_dir}/${backup_file}"
    else
        rm -rf "$meta_parent"
        log_error "Backup failed!"
        exit 1
    fi
}

# Restore an instance from a 'backup' archive: instance files, systemd unit,
# sudoers rules and registry entry. Refuses to overwrite an existing instance.
restore_instance() {
    require_root
    local archive="${1:-}"

    if [ -z "$archive" ] || [ ! -f "$archive" ]; then
        log_error "Backup file not found: ${archive:-<none>}"
        echo "Usage: sudo $0 restore /root/bf1942_backups/bf1942_<name>_backup_<date>.tar.gz"
        exit 1
    fi

    local entries
    if ! entries=$(tar -tzf "$archive" 2>/dev/null); then
        log_error "Not a readable .tar.gz archive: $archive"
        exit 1
    fi
    entries=$(sed 's#^\./##' <<< "$entries")

    # The archive holds exactly <name>/ and (since metadata support) <name>.meta/
    local name
    name=$(cut -d/ -f1 <<< "$entries" | grep -v '\.meta$' | sort -u || true)
    if [ -z "$name" ] || [ "$(wc -l <<< "$name")" -ne 1 ]; then
        log_error "Archive does not look like a bf1942_manager backup (expected one instance directory)."
        exit 1
    fi
    if [ "$name" = "default" ] || ! validate_instance_name "$name"; then
        log_error "Archive contains an unsupported instance name: '$name'"
        exit 1
    fi
    if grep -qvE "^(${name}|${name}\.meta)(/|$)" <<< "$entries" ||
        grep -qE '(^|/)\.\.(/|$)' <<< "$entries"; then
        log_error "Archive contains paths outside ${name}/ - refusing to extract it."
        exit 1
    fi

    local service="bfsmd-${name}.service"
    local unit_path="/etc/systemd/system/${service}"
    if [ -e "${BF_BASE}/${name}" ]; then
        log_error "Instance '$name' already exists at ${BF_BASE}/${name}."
        echo "  Back it up and remove it first:  sudo $0 backup $name && sudo $0 remove $name"
        exit 1
    fi
    if ! id "$BF_USER" >/dev/null 2>&1; then
        log_error "Service user '$BF_USER' does not exist on this machine."
        echo "  Run the installer for your distro once first - it installs the 32-bit"
        echo "  libraries and creates the user - then retry the restore."
        exit 1
    fi
    if ! grep -qE "^${name}\.meta/${service}$" <<< "$entries" && [ ! -f "$unit_path" ]; then
        log_error "This backup has no systemd unit (it predates restore support) and none exists here."
        echo "  Extract the files manually and recreate the service with the installer:"
        echo "  sudo tar -xzf $archive -C ${BF_BASE} ${name}"
        exit 1
    fi

    local meta_tmp
    meta_tmp=$(mktemp -d)
    tar -xzf "$archive" -C "$meta_tmp" "${name}.meta" 2>/dev/null || true
    local meta="${meta_tmp}/${name}.meta"

    # Registry: keep the instance's original ID, unless another instance
    # already holds it (they would share ports).
    if ! grep -q "^${name}=" "$INSTANCE_REGISTRY" 2>/dev/null && [ -s "${meta}/registry_entry" ]; then
        local entry id owner
        entry=$(head -1 "${meta}/registry_entry")
        id="${entry#*=}"
        if ! [[ "$entry" =~ ^${name}=[0-9]+$ ]]; then
            log_warn "Ignoring malformed registry entry in backup: $entry"
        else
            owner=$(awk -F= -v i="$id" '$2==i{print $1; exit}' "$INSTANCE_REGISTRY" 2>/dev/null || true)
            if [ -n "$owner" ]; then
                rm -rf "$meta_tmp"
                log_error "Instance ID ${id} (and its ports) is already used by '${owner}'."
                echo "  Remove or re-port '${owner}' first, or restore on another machine."
                exit 1
            fi
        fi
    fi

    log_info "Restoring instance '$name' from $(basename "$archive")..."
    mkdir -p "$BF_BASE"
    chown "${BF_USER}:${BF_USER}" "$BF_BASE"
    if ! tar -xzf "$archive" -C "$BF_BASE" "$name"; then
        rm -rf "$meta_tmp" "${BF_BASE:?}/${name}"
        log_error "Extraction failed."
        exit 1
    fi
    chown -R "${BF_USER}:${BF_USER}" "${BF_BASE}/${name}"
    log_success "Files restored to ${BF_BASE}/${name}"

    if [ -n "${entry:-}" ] && [[ "$entry" =~ ^${name}=[0-9]+$ ]]; then
        echo "$entry" >> "$INSTANCE_REGISTRY"
        chmod 644 "$INSTANCE_REGISTRY"
        log_success "Registry entry restored ($entry)"
    fi

    if [ -f "$unit_path" ]; then
        log_info "Keeping the existing ${unit_path}"
    else
        install -m 644 -o root -g root "${meta}/${service}" "$unit_path"
        log_success "Service unit restored"
    fi

    local sudoers_src="${meta}/bf1942_${name}" sudoers_dst="/etc/sudoers.d/bf1942_${name}"
    if [ -f "$sudoers_src" ] && [ ! -f "$sudoers_dst" ]; then
        if ! command -v visudo >/dev/null 2>&1 || visudo -cf "$sudoers_src" >/dev/null; then
            install -m 440 -o root -g root "$sudoers_src" "$sudoers_dst"
            log_success "Sudoers rules restored"
        else
            log_warn "Sudoers rules in the backup failed validation - skipped."
        fi
    fi
    rm -rf "$meta_tmp"

    if command -v restorecon >/dev/null 2>&1; then
        restorecon -R "${BF_BASE}/${name}" 2>/dev/null || true
    fi

    # The unit binds BFSMD to a fixed IP - flag it when restoring elsewhere.
    local bind_ip
    bind_ip=$(get_bind_ip "$name")
    if command -v ip >/dev/null 2>&1 && ! ip -4 addr show 2>/dev/null | grep -qF "inet ${bind_ip}/"; then
        log_warn "The service binds to ${bind_ip}, which is not an address on this machine."
        echo "  Edit '-ip ${bind_ip}' in ${unit_path}, then: sudo systemctl daemon-reload"
    fi

    systemctl daemon-reload
    systemctl enable "$service" >/dev/null 2>&1 || true

    local game_port query_port mgmt_port lan_port ase_port console_port
    read -r game_port query_port mgmt_port lan_port ase_port console_port <<< "$(get_ports "$name")"
    offer_open_game_ports "$name" "$game_port" "$query_port"

    local start_now="y"
    read -r -p "Start '$name' now? [Y/n] " start_now || true
    if [[ ! "$start_now" =~ ^([nN][oO]|[nN])$ ]]; then
        systemctl start "$service"
        sleep 2
        if systemctl is-active --quiet "$service"; then
            log_success "Instance '$name' restored and running."
        else
            log_error "Service failed to start. Check: journalctl -u $service -n 50"
        fi
    else
        log_success "Instance '$name' restored. Start it with: sudo $0 start $name"
    fi
}

# Open an instance's player-facing ports in an active firewall, on request.
offer_open_game_ports() {
    local name="$1" game="$2" query="$3" answer=""
    local fw=""
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
        fw="ufw"
    elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        fw="firewalld"
    fi
    [ -n "$fw" ] || return 0

    read -r -p "Open game ports ${game}/udp and ${query}/udp in ${fw}? [Y/n] " answer || true
    if [[ "$answer" =~ ^([nN][oO]|[nN])$ ]]; then
        log_warn "Players cannot connect until ${game}/udp and ${query}/udp are open."
        return 0
    fi
    if [ "$fw" = "ufw" ]; then
        ufw allow "${game}/udp" comment "BF1942 ${name} Game" >/dev/null
        ufw allow "${query}/udp" comment "BF1942 ${name} Query" >/dev/null
    else
        firewall-cmd --permanent --add-port="${game}/udp" >/dev/null
        firewall-cmd --permanent --add-port="${query}/udp" >/dev/null
        firewall-cmd --reload >/dev/null
    fi
    log_success "Opened ${game}/udp and ${query}/udp (management port left closed - use an SSH tunnel)"
}

# Start all instances
start_all() {
    require_root
    
    log_info "Starting all instances..."
    echo ""
    
    local count=0
    
    # Standalone
    if [ -f "/etc/systemd/system/bf1942.service" ]; then
        systemctl start bf1942.service
        ((count++)) || true
        echo "  Started: default (standalone)"
    fi
    
    # BFSMD instances
    for name in $(get_instance_names); do
        local service="bfsmd-${name}.service"
        if [ -f "/etc/systemd/system/${service}" ]; then
            systemctl start "${service}"
            ((count++)) || true
            echo "  Started: $name"
        fi
    done
    
    echo ""
    log_success "Started $count instance(s)"
}

# Stop all instances
stop_all() {
    require_root
    
    log_info "Stopping all instances..."
    echo ""
    
    local count=0
    
    # Standalone
    if [ -f "/etc/systemd/system/bf1942.service" ]; then
        systemctl stop bf1942.service
        ((count++)) || true
        echo "  Stopped: default (standalone)"
    fi
    
    # BFSMD instances
    for name in $(get_instance_names); do
        local service="bfsmd-${name}.service"
        if [ -f "/etc/systemd/system/${service}" ]; then
            systemctl stop "${service}"
            ((count++)) || true
            echo "  Stopped: $name"
        fi
    done
    
    echo ""
    log_success "Stopped $count instance(s)"
}

# Restart all instances
restart_all() {
    require_root
    
    log_info "Restarting all instances..."
    echo ""
    
    local count=0
    
    # Standalone
    if [ -f "/etc/systemd/system/bf1942.service" ]; then
        systemctl restart bf1942.service
        ((count++)) || true
        echo "  Restarted: default (standalone)"
    fi
    
    # BFSMD instances
    for name in $(get_instance_names); do
        local service="bfsmd-${name}.service"
        if [ -f "/etc/systemd/system/${service}" ]; then
            systemctl restart "${service}"
            ((count++)) || true
            echo "  Restarted: $name"
        fi
    done
    
    echo ""
    log_success "Restarted $count instance(s)"
}

# Show usage
# ---------------------------------------------------------------------------
# Patches, replay recorder and self-update
#
# install.sh only downloads the installer and this manager, so the patches/
# folder usually isn't on the server. When it isn't next to this script (a
# git clone has it), the patch files are downloaded to PATCH_CACHE and kept
# fresh from GitHub.
# ---------------------------------------------------------------------------

REPO_SLUG="hootmeow/bf1942-linux"
REPO_REF="${BF1942_LINUX_REF:-main}"
REPO_RAW="https://raw.githubusercontent.com/${REPO_SLUG}/${REPO_REF}"
PATCH_CACHE="/opt/bf1942-linux/patches"
SELF="$(readlink -f "${BASH_SOURCE[0]:-$0}" 2>/dev/null || echo "$0")"
SELF_DIR="$(dirname "$SELF")"
# Used when the GitHub API can't list the folder.
PATCH_FILES_DEFAULT="apply_patches.sh patch_ctf_flags_map.py patch_ctf_respawn.py patch-existing-logging.sh install-replay-recorder.sh"

# Local patches/ (git clone) wins; otherwise the downloaded copy.
patch_dir() {
    if [ -f "${SELF_DIR}/patches/apply_patches.sh" ]; then
        echo "${SELF_DIR}/patches"
    else
        echo "$PATCH_CACHE"
    fi
}

patch_dir_is_cache() { [ "$(patch_dir)" = "$PATCH_CACHE" ]; }

# Names of the files in the repo's patches/ folder (GitHub API), or the
# built-in list if the API can't be reached.
remote_patch_files() {
    local names
    names=$(curl -fsS --max-time 10 -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/${REPO_SLUG}/contents/patches?ref=${REPO_REF}" 2>/dev/null |
        awk -F'"' '/"name":/ {print $4}' |
        grep -E '^(apply_patches\.sh|patch[-_][A-Za-z0-9_-]+\.(sh|py)|install-[A-Za-z0-9_-]+\.sh)$' || true)
    if [ -n "$names" ]; then
        echo "$names"
    else
        tr ' ' '\n' <<< "$PATCH_FILES_DEFAULT"
    fi
}

# Download (or refresh) the patch files into PATCH_CACHE.
fetch_patches() {
    require_root
    command -v curl >/dev/null 2>&1 || { log_error "curl is required to download the patches."; return 1; }
    if [[ ! "$REPO_REF" =~ ^[A-Za-z0-9._/-]+$ ]]; then
        log_error "BF1942_LINUX_REF contains unexpected characters: $REPO_REF"; return 1
    fi
    local files f tmp got=0 failed=0
    files=$(remote_patch_files)
    mkdir -p "$PATCH_CACHE"
    chmod 755 "$PATCH_CACHE"
    log_info "Downloading patches (${REPO_REF}) to ${PATCH_CACHE}..."
    for f in $files; do
        tmp="${PATCH_CACHE}/.${f}.part"
        if curl -fsSL --retry 2 --max-time 60 -o "$tmp" "${REPO_RAW}/patches/${f}" &&
           head -1 "$tmp" | grep -qE '^#!/usr/bin/env (bash|python3)'; then
            chmod 755 "$tmp"
            mv -f "$tmp" "${PATCH_CACHE}/${f}"
            got=$((got + 1))
        else
            rm -f "$tmp"
            log_warn "Could not download patches/${f}"
            failed=$((failed + 1))
        fi
    done
    # Drop patches that were removed upstream (only when the list came from
    # GitHub - never on a failed download, which would empty the folder).
    if [ "$got" -gt 0 ] && [ "$failed" -eq 0 ]; then
        local have
        for have in "$PATCH_CACHE"/*; do
            [ -f "$have" ] || continue
            f=$(basename "$have")
            grep -qxF "$f" <<< "$files" || { rm -f "$have"; log_info "Removed ${f} (no longer in the repo)"; }
        done
    fi
    if [ ! -f "${PATCH_CACHE}/apply_patches.sh" ]; then
        log_error "Patch download failed - check your internet connection."
        return 1
    fi
    date +%s > "${PATCH_CACHE}/.fetched"
    if [ "$failed" -gt 0 ]; then
        log_warn "Downloaded ${got} file(s), ${failed} failed."
    else
        log_success "Downloaded ${got} patch file(s)."
    fi
}

# Make sure the patch files are present; refresh the downloaded copy once a
# day. A failed refresh keeps using the files already there.
ensure_patches() {
    patch_dir_is_cache || return 0
    local stamp age
    if [ ! -f "${PATCH_CACHE}/apply_patches.sh" ]; then
        fetch_patches
        return
    fi
    stamp=$(cat "${PATCH_CACHE}/.fetched" 2>/dev/null || echo 0)
    [[ "$stamp" =~ ^[0-9]+$ ]] || stamp=0
    age=$(( $(date +%s) - stamp ))
    if [ "$age" -gt 86400 ]; then
        fetch_patches || log_warn "Using the patch files downloaded earlier."
    fi
    return 0
}

# The binary patches are Python. Offer to install it with the distro's
# package manager rather than just failing.
ensure_python3() {
    command -v python3 >/dev/null 2>&1 && return 0
    local cmd=""
    if command -v apt-get >/dev/null 2>&1; then cmd="apt-get install -y python3"
    elif command -v dnf >/dev/null 2>&1; then cmd="dnf install -y python3"
    elif command -v pacman >/dev/null 2>&1; then cmd="pacman -S --noconfirm --needed python"
    fi
    log_warn "python3 is needed for the binary patches and isn't installed."
    if [ -z "$cmd" ]; then
        log_error "Install python3 with your package manager, then run this again."
        return 1
    fi
    if [ -t 0 ]; then
        local answer=""
        read -r -p "Install it now (${cmd})? [Y/n] " answer || true
        [[ "${answer:-y}" =~ ^[Yy] ]] || return 1
    else
        log_info "Installing python3 (${cmd})..."
    fi
    # shellcheck disable=SC2086
    $cmd >/dev/null || { log_error "python3 install failed: ${cmd}"; return 1; }
    log_success "python3 installed."
}

# bf1942_manager.sh patch [instances|all] [apply_patches.sh options]
cmd_patch() {
    require_root
    ensure_patches || return 1
    local dir; dir=$(patch_dir)
    if ls "$dir"/patch_*.py >/dev/null 2>&1; then
        ensure_python3 || return 1
    fi
    # The manager calls the standalone server 'default'; the runner, 'standalone'.
    local -a args=()
    local a
    for a in "$@"; do
        [ "$a" = "default" ] && a="standalone"
        args+=("$a")
    done
    bash "${dir}/apply_patches.sh" "${args[@]}"
}

# bf1942_manager.sh recorder [install-replay-recorder.sh options]
cmd_recorder() {
    require_root
    ensure_patches || return 1
    local script; script="$(patch_dir)/install-replay-recorder.sh"
    [ -f "$script" ] || { log_error "Replay recorder script not found: $script"; return 1; }
    bash "$script" "$@"
}

# bf1942_manager.sh update - refresh this manager and the patch files.
cmd_update() {
    require_root
    command -v curl >/dev/null 2>&1 || { log_error "curl is required."; return 1; }
    if [ -d "${SELF_DIR}/.git" ]; then
        log_info "This manager is in a git clone - update it with: git -C ${SELF_DIR} pull"
        return 0
    fi
    local tmp new_ver
    tmp="$(mktemp "${SELF_DIR}/.bf1942_manager.XXXXXX")" || { log_error "Can't write to ${SELF_DIR}"; return 1; }
    log_info "Checking for a newer bf1942_manager.sh (${REPO_REF})..."
    if ! curl -fsSL --retry 2 --max-time 60 -o "$tmp" "${REPO_RAW}/bf1942_manager.sh" ||
       ! head -1 "$tmp" | grep -q '^#!/usr/bin/env bash' || ! bash -n "$tmp" 2>/dev/null; then
        rm -f "$tmp"
        log_error "Download failed or the file isn't a valid script - nothing changed."
        return 1
    fi
    if cmp -s "$tmp" "$SELF"; then
        rm -f "$tmp"
        log_success "bf1942_manager.sh is up to date (v${VERSION})."
    else
        new_ver=$(sed -n 's/^VERSION="\(.*\)"/\1/p' "$tmp" | head -1)
        chmod --reference="$SELF" "$tmp" 2>/dev/null || chmod 755 "$tmp"
        chown --reference="$SELF" "$tmp" 2>/dev/null || true
        # mv swaps in a new file: the copy bash is reading right now is untouched.
        mv -f "$tmp" "$SELF"
        log_success "bf1942_manager.sh updated: v${VERSION} -> v${new_ver:-?}"
    fi
    if patch_dir_is_cache; then
        fetch_patches
    else
        log_info "Patches come from $(patch_dir) (git clone) - not downloaded."
    fi
}

# Health-check footer: which instances have patches waiting. Uses only the
# files already on disk (never downloads) and needs root to read binaries.
patch_hint() {
    [[ $EUID -eq 0 ]] || return 0
    local dir; dir=$(patch_dir)
    if [ ! -f "${dir}/apply_patches.sh" ]; then
        echo -e "  ${BLUE}ℹ${NC} Bug-fix patches (CTF flag fixes) are available: sudo $0 patch"
        echo ""
        return 0
    fi
    local name count any=0
    while read -r name count; do
        [[ "$name" =~ ^[A-Za-z0-9_-]+$ && "$count" =~ ^[0-9]+$ ]] || continue
        [ "$count" -gt 0 ] || continue
        [ "$name" = "standalone" ] && name="default"
        echo -e "  ${BLUE}ℹ${NC} ${name}: ${count} patch(es) available - sudo $0 patch ${name}"
        any=1
    done < <(timeout 60 bash "${dir}/apply_patches.sh" --summary 2>/dev/null || true)
    [ "$any" -eq 1 ] && echo ""
    return 0
}

# ---------------------------------------------------------------------------
# Interactive menu (no arguments, on a terminal)
# ---------------------------------------------------------------------------

menu_pause() { echo ""; read -r -p "Press Enter to continue..." _ || true; }

# Run a command in a subshell so its 'exit' (errors, require_root) returns
# to the menu instead of quitting it.
menu_run() { ( "$@" ) || true; menu_pause; }

menu_service() { if [ "$1" = "default" ]; then echo "bf1942.service"; else echo "bfsmd-$1.service"; fi; }

# Fills MENU_NAMES with every instance that has a service.
declare -a MENU_NAMES=()
menu_instances() {
    MENU_NAMES=()
    if [ -d "$BF_STANDALONE" ] && service_exists "bf1942.service"; then
        MENU_NAMES+=("default")
    fi
    local n
    for n in $(get_instance_names); do
        [ -n "$n" ] && service_exists "bfsmd-${n}.service" && MENU_NAMES+=("$n")
    done
    return 0
}

# One status line: service state plus a live game query when it's up.
menu_status_line() {
    local name="$1" svc ip port reply
    svc=$(menu_service "$name")
    if ! systemctl is-active --quiet "$svc"; then
        echo -e "${RED}●${NC} stopped"
        return 0
    fi
    if [ "$name" = "default" ]; then
        ip="127.0.0.1"; port=23000
    else
        ip=$(get_bind_ip "$name"); port=$(get_ports "$name" | awk '{print $2}')
    fi
    if reply=$(query_server "$ip" "$port"); then
        IFS='|' read -r q_host q_map q_players q_max <<< "$reply"
        echo -e "${GREEN}●${NC} online    ${q_map}, ${q_players}/${q_max} players"
    else
        echo -e "${YELLOW}●${NC} running, game not answering yet"
    fi
}

menu_server() {
    local name="$1" c
    while true; do
        clear 2>/dev/null || true
        echo -e "${BOLD}${name}${NC}   $(menu_status_line "$name")"
        echo ""
        echo "  1) Status            2) Start             3) Stop"
        echo "  4) Restart           5) Live log          6) Config files"
        if [ "$name" != "default" ]; then
            echo "  7) Back up           8) Patches           9) Remove server"
        else
            echo "                       8) Patches"
        fi
        echo "  b) Back"
        echo ""
        read -r -p "Choose: " c || return 0
        case "$c" in
            1) menu_run show_status "$name" ;;
            2) menu_run start_instance "$name" ;;
            3) menu_run stop_instance "$name" ;;
            4) menu_run restart_instance "$name" ;;
            5) echo "Ctrl+C returns to the menu."; ( show_logs "$name" ) || true ;;
            6) menu_run show_config "$name" ;;
            7) [ "$name" = "default" ] || menu_run backup_instance "$name" ;;
            8) menu_run cmd_patch "$name" ;;
            9) if [ "$name" != "default" ]; then
                   ( remove_instance "$name" ) || true
                   menu_pause
                   service_exists "$(menu_service "$name")" || return 0
               fi ;;
            b|B|"") return 0 ;;
        esac
    done
}

menu_patches() {
    local c targets
    while true; do
        clear 2>/dev/null || true
        echo -e "${BOLD}Bug-fix patches${NC}"
        ( cmd_patch ) || true
        echo "  a) Apply everything needed, on every server"
        echo "  s) Apply to specific servers"
        echo "  u) Re-download the latest patches"
        echo "  b) Back"
        echo ""
        read -r -p "Choose: " c || return 0
        case "$c" in
            a|A) menu_run cmd_patch all ;;
            s|S) read -r -p "Server names (space-separated, default = standalone): " targets || continue
                 # shellcheck disable=SC2086
                 [ -z "$targets" ] || menu_run cmd_patch $targets ;;
            u|U) menu_run fetch_patches ;;
            b|B|"") return 0 ;;
        esac
    done
}

menu_restore() {
    local -a files=()
    local f c i
    for f in /root/bf1942_backups/*.tar.gz; do [ -f "$f" ] && files+=("$f"); done
    if [ ${#files[@]} -eq 0 ]; then
        log_warn "No backups in /root/bf1942_backups (or not readable - run with sudo)."
        menu_pause; return 0
    fi
    echo -e "${BOLD}Backups${NC}"
    for i in "${!files[@]}"; do printf "  %2d) %s\n" "$((i + 1))" "$(basename "${files[$i]}")"; done
    read -r -p "Restore which? (Enter = cancel) " c || return 0
    if [[ "$c" =~ ^[0-9]+$ ]] && [ "$c" -ge 1 ] && [ "$c" -le ${#files[@]} ]; then
        menu_run restore_instance "${files[$((c - 1))]}"
    fi
}

interactive_menu() {
    # Ctrl+C stops the running command (e.g. a live log), not the menu.
    trap ':' INT
    local c i name
    while true; do
        clear 2>/dev/null || true
        echo -e "${BOLD}BF1942 Server Manager v${VERSION}${NC}   ${CYAN}captheflag.com${NC}"
        [[ $EUID -eq 0 ]] || echo -e "${YELLOW}Not root - start/stop, patches and backups need: sudo $0${NC}"
        echo ""
        menu_instances
        if [ ${#MENU_NAMES[@]} -eq 0 ]; then
            echo "  No servers installed yet. Create one with: sudo bash install.sh [name]"
        else
            for i in "${!MENU_NAMES[@]}"; do
                name="${MENU_NAMES[$i]}"
                printf "  ${BOLD}%2d)${NC} %-20s %s\n" "$((i + 1))" "$name" "$(menu_status_line "$name")"
            done
        fi
        echo ""
        echo "  h) Health check        p) Patches            r) Replay recorder (bfstats.io)"
        echo "  l) Ports               x) Security audit     a) Start / stop / restart all"
        echo "  k) Restore a backup    u) Update manager     ?) Command-line help"
        echo "  q) Quit"
        echo ""
        read -r -p "Choose a server number or option: " c || { echo ""; break; }
        case "$c" in
            q|Q) break ;;
            h|H) menu_run health_check ;;
            p|P) menu_patches ;;
            r|R) ( cmd_recorder ) || menu_pause ;;
            l|L) menu_run show_ports ;;
            x|X) menu_run security_audit ;;
            a|A) read -r -p "Type start, stop or restart: " c || continue
                 case "$c" in
                     start)   menu_run start_all ;;
                     stop)    menu_run stop_all ;;
                     restart) menu_run restart_all ;;
                 esac ;;
            k|K) menu_restore ;;
            u|U) if ( cmd_update ); then
                     menu_pause
                     exec bash "$SELF" menu   # run the menu from the updated file
                 fi
                 menu_pause ;;
            \?) show_usage; menu_pause ;;
            *) if [[ "$c" =~ ^[0-9]+$ ]] && [ "$c" -ge 1 ] && [ "$c" -le ${#MENU_NAMES[@]} ]; then
                   menu_server "${MENU_NAMES[$((c - 1))]}"
               fi ;;
        esac
    done
    trap - INT
}

show_usage() {
    echo -e "${BOLD}BF1942 Multi-Instance Manager v${VERSION}${NC}

${BOLD}Usage:${NC} $0 [command] [instance_name]

${BOLD}Commands:${NC}
  ${CYAN}list${NC}              - List all instances and their status
  ${CYAN}ports${NC}             - Show port assignments for all instances
  ${CYAN}status${NC} [name]     - Show detailed status of instance(s)
  ${CYAN}config${NC} <n>        - Show configuration paths for instance
  ${CYAN}health${NC}            - Check every instance's game server actually answers
  ${CYAN}security${NC}          - Run security audit on all instances
  ${CYAN}backup${NC} <n>        - Back up an instance (files, service, sudoers, registry)
  ${CYAN}restore${NC} <file>    - Restore an instance from a backup archive
  ${CYAN}start${NC} <n>         - Start an instance
  ${CYAN}stop${NC} <n>          - Stop an instance
  ${CYAN}restart${NC} <n>       - Restart an instance
  ${CYAN}start-all${NC}         - Start all instances
  ${CYAN}stop-all${NC}          - Stop all instances
  ${CYAN}restart-all${NC}       - Restart all instances
  ${CYAN}logs${NC} <n>          - View logs for an instance (tail -f)
  ${CYAN}remove${NC} <n>        - Remove an instance (requires confirmation)
  ${CYAN}patch${NC} [n|all]     - Bug-fix patches: status, or apply (downloads them if needed)
  ${CYAN}recorder${NC}          - bfstats.io replay recorder: install / update / remove
  ${CYAN}update${NC}            - Update this manager and the patch files
  ${CYAN}menu${NC}              - Interactive menu (also: run with no command)

${BOLD}Examples:${NC}
  $0 list
  $0 status server1
  $0 config server1
  $0 health
  $0 security
  $0 backup server1
  sudo $0 restore /root/bf1942_backups/bf1942_server1_backup_20261125_120000.tar.gz
  sudo $0 restart server1
  sudo $0 start-all
  sudo $0 remove server2
  sudo $0 patch              # which servers need which patches
  sudo $0 patch all          # apply them (add --check for a dry run)

${BOLD}Notes:${NC}
  - Commands that modify services require sudo
  - Use 'default' for standalone server instance
  - Instance names are case-sensitive
  - Run 'security' regularly to check for issues

Docs & issues: https://github.com/hootmeow/bf1942-linux
Community:     https://captheflag.com"
}

# Main command handler
main() {
    local command="${1:-}"

    case "$command" in
        status|config|start|stop|restart|backup|logs|remove)
            if [ -n "${2:-}" ]; then
                validate_instance_name "$2" || exit 1
            fi
            ;;
    esac
    
    case "$command" in
        list)
            list_instances
            ;;
        ports)
            show_ports
            ;;
        status)
            show_status "${2:-}"
            ;;
        config)
            if [ -z "${2:-}" ]; then
                log_error "Instance name required."
                echo "Usage: $0 config <instance_name>"
                exit 1
            fi
            show_config "$2"
            ;;
        health)
            health_check
            ;;
        security)
            security_audit
            ;;
        start)
            if [ -z "${2:-}" ]; then
                log_error "Instance name required."
                echo "Usage: sudo $0 start <instance_name>"
                exit 1
            fi
            start_instance "$2"
            ;;
        stop)
            if [ -z "${2:-}" ]; then
                log_error "Instance name required."
                echo "Usage: sudo $0 stop <instance_name>"
                exit 1
            fi
            stop_instance "$2"
            ;;
        restart)
            if [ -z "${2:-}" ]; then
                log_error "Instance name required."
                echo "Usage: sudo $0 restart <instance_name>"
                exit 1
            fi
            restart_instance "$2"
            ;;
        backup)
            if [ -z "${2:-}" ]; then
                log_error "Instance name required."
                echo "Usage: $0 backup <instance_name>"
                exit 1
            fi
            backup_instance "$2"
            ;;
        start-all)
            start_all
            ;;
        stop-all)
            stop_all
            ;;
        restart-all)
            restart_all
            ;;
        logs)
            if [ -z "${2:-}" ]; then
                log_error "Instance name required."
                echo "Usage: $0 logs <instance_name>"
                exit 1
            fi
            show_logs "$2"
            ;;
        restore)
            restore_instance "${2:-}"
            ;;
        remove)
            if [ -z "${2:-}" ]; then
                log_error "Instance name required."
                echo "Usage: sudo $0 remove <instance_name>"
                exit 1
            fi
            remove_instance "$2"
            ;;
        patch)
            shift
            cmd_patch "$@"
            ;;
        recorder)
            shift
            cmd_recorder "$@"
            ;;
        update)
            cmd_update
            ;;
        menu)
            interactive_menu
            ;;
        "")
            if [ -t 0 ] && [ -t 1 ]; then
                interactive_menu
            else
                show_usage
            fi
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            log_error "Unknown command: $command"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
