#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  BF1942 Multi-Instance Manager
#
#  Purpose:
#    Manage multiple BF1942 server instances on a single machine
#
#  Usage: ./bf1942_manager.sh [command] [instance_name]
#
# ---------------------------------------------------------------------------

set -euo pipefail

BF_USER="bf1942_user"
BF_BASE="/home/${BF_USER}/instances"
BF_STANDALONE="/home/${BF_USER}/bf1942"

# Colors
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\e[34m'
CYAN='\e[36m'
BOLD='\e[1m'
NC='\e[0m'

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

# Get instance hash/ID from name
get_instance_id() {
    local name="$1"
    local hash=$(echo -n "$name" | cksum | cut -d' ' -f1)
    echo $((hash % 100))
}

# Calculate ports from instance name
get_ports() {
    local name="$1"
    local id=$(get_instance_id "$name")
    local game_port=$((14567 + id))
    local query_port=$((23000 + id))
    local mgmt_port=$((14667 + id))
    echo "${game_port} ${query_port} ${mgmt_port}"
}

# Check if service file exists
service_exists() {
    local service="$1"
    [ -f "/etc/systemd/system/${service}" ]
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
    if [ -d "$BF_BASE" ]; then
        for instance_dir in "$BF_BASE"/*; do
            if [ -d "$instance_dir" ]; then
                local name=$(basename "$instance_dir")
                local service="bfsmd-${name}.service"
                
                if service_exists "$service"; then
                    local status=$(systemctl is-active "$service" 2>/dev/null || echo "inactive")
                    local enabled=$(systemctl is-enabled "$service" 2>/dev/null || echo "disabled")
                    
                    local status_color="${RED}"
                    [ "$status" == "active" ] && status_color="${GREEN}"
                    
                    read game_port query_port mgmt_port <<< $(get_ports "$name")
                    
                    printf "  ${CYAN}%-20s${NC} ${status_color}%-10s${NC} (${enabled}) [Game:%-5s Query:%-5s Mgmt:%-5s]\n" \
                        "$name" "$status" "$game_port" "$query_port" "$mgmt_port"
                    found=1
                else
                    printf "  ${CYAN}%-20s${NC} ${RED}%-10s${NC} (no service)\n" "$name" "ERROR"
                    found=1
                fi
            fi
        done
    fi
    
    if [ $found -eq 0 ]; then
        log_warn "No instances found."
        echo ""
        echo "To create an instance, run:"
        echo "  sudo ./bf1942_unified_setup.sh [instance_name]"
    fi
    
    echo ""
}

# Show port assignments
show_ports() {
    echo -e "${BOLD}Port Assignments${NC}"
    echo ""
    printf "%-20s %-15s %-15s %-15s\n" "Instance" "Game Port" "Query Port" "Mgmt Port"
    printf "%-20s %-15s %-15s %-15s\n" "--------" "---------" "----------" "---------"
    
    # Standalone
    if [ -d "$BF_STANDALONE" ] && service_exists "bf1942.service"; then
        printf "%-20s %-15s %-15s %-15s\n" "default" "14567 (UDP)" "23000 (UDP)" "N/A"
    fi
    
    # BFSMD instances
    if [ -d "$BF_BASE" ]; then
        for instance_dir in "$BF_BASE"/*; do
            if [ -d "$instance_dir" ]; then
                local name=$(basename "$instance_dir")
                read game_port query_port mgmt_port <<< $(get_ports "$name")
                printf "%-20s %-15s %-15s %-15s\n" \
                    "$name" "$game_port (UDP)" "$query_port (UDP)" "$mgmt_port (TCP)"
            fi
        done
    fi
    
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
    
    read game_port query_port mgmt_port <<< $(get_ports "$name")
    log_info "Port Configuration:"
    echo "  Game Port      : $game_port (UDP)"
    echo "  Query Port     : $query_port (UDP)"
    echo "  Management Port: $mgmt_port (TCP)"
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
        echo "  - ServerSettings.con (game settings)"
        echo "  - MapList.con (map rotation)"
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
    
    read game_port query_port mgmt_port <<< $(get_ports "$name")
    echo "Ports:"
    echo "  Game:       $game_port (UDP)"
    echo "  Query:      $query_port (UDP)"
    echo "  Management: $mgmt_port (TCP)"
    echo ""
    echo "Key Files:"
    echo "  - servermanager.con (BFSMD settings)"
    echo "  - useraccess.con (admin accounts)"
    echo "  - ServerSettings.con (game settings)"
    echo "  - MapList.con (map rotation)"
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
            active=$((active + 1))
            echo -e "  ${GREEN}✓${NC} default (standalone) - Running"
        else
            issues=$((issues + 1))
            echo -e "  ${RED}✗${NC} default (standalone) - Not running"
        fi
    fi
    
    # Check BFSMD instances
    if [ -d "$BF_BASE" ]; then
        for instance_dir in "$BF_BASE"/*; do
            if [ -d "$instance_dir" ]; then
                local name=$(basename "$instance_dir")
                local service="bfsmd-${name}.service"
                
                if service_exists "$service"; then
                    total=$((total + 1))
                    if systemctl is-active --quiet "$service"; then
                        active=$((active + 1))
                        echo -e "  ${GREEN}✓${NC} $name - Running"
                    else
                        issues=$((issues + 1))
                        echo -e "  ${RED}✗${NC} $name - Not running"
                    fi
                fi
            fi
        done
    fi
    
    echo ""
    echo "Summary: $active/$total instances running"
    
    if [ $issues -gt 0 ]; then
        log_warn "$issues instance(s) have issues"
    else
        log_success "All instances healthy"
    fi
    echo ""
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
                    if grep -q "battlefield" "$access_file" 2>/dev/null; then
                        echo -e "  ${RED}✗${NC} $name - Default password 'battlefield' still in use!"
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
            
            # Check if ports are properly restricted
            local mgmt_ports_open=$(ufw status | grep -c "14[67][0-9][0-9].*ALLOW.*Anywhere" || echo "0")
            if [ "$mgmt_ports_open" -gt 0 ]; then
                echo -e "  ${YELLOW}⚠${NC} Management ports may be open to the world"
                echo "    Consider restricting to trusted IPs only"
                warnings=$((warnings + 1))
            fi
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
    
    log_info "Stopping service..."
    systemctl stop "$service" 2>/dev/null || true
    
    log_info "Disabling service..."
    systemctl disable "$service" 2>/dev/null || true
    
    log_info "Removing service file..."
    rm -f "/etc/systemd/system/$service"
    
    log_info "Removing sudoers file..."
    rm -f "/etc/sudoers.d/bf1942_${name}"
    
    log_info "Removing instance files..."
    rm -rf "$instance_path"
    
    log_info "Reloading systemd..."
    systemctl daemon-reload
    
    log_success "Instance '$name' has been removed."
}

# Backup instance
backup_instance() {
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
    
    log_info "Creating backup of instance '$name'..."
    log_info "This may take a minute..."
    
    if tar -czf "${backup_dir}/${backup_file}" -C "${BF_BASE}" "${name}" 2>/dev/null; then
        local size=$(du -h "${backup_dir}/${backup_file}" | cut -f1)
        log_success "Backup created: ${backup_dir}/${backup_file} (${size})"
        echo ""
        echo "To restore this backup:"
        echo "  sudo tar -xzf ${backup_dir}/${backup_file} -C ${BF_BASE}"
        echo "  sudo systemctl restart bfsmd-${name}.service"
    else
        log_error "Backup failed!"
        exit 1
    fi
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
    if [ -d "$BF_BASE" ]; then
        for dir in "$BF_BASE"/*; do
            if [ -d "$dir" ]; then
                local name=$(basename "$dir")
                local service="bfsmd-${name}.service"
                
                if [ -f "/etc/systemd/system/${service}" ]; then
                    systemctl start "${service}"
                    ((count++)) || true
                    echo "  Started: $name"
                fi
            fi
        done
    fi
    
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
    if [ -d "$BF_BASE" ]; then
        for dir in "$BF_BASE"/*; do
            if [ -d "$dir" ]; then
                local name=$(basename "$dir")
                local service="bfsmd-${name}.service"
                
                if [ -f "/etc/systemd/system/${service}" ]; then
                    systemctl stop "${service}"
                    ((count++)) || true
                    echo "  Stopped: $name"
                fi
            fi
        done
    fi
    
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
    if [ -d "$BF_BASE" ]; then
        for dir in "$BF_BASE"/*; do
            if [ -d "$dir" ]; then
                local name=$(basename "$dir")
                local service="bfsmd-${name}.service"
                
                if [ -f "/etc/systemd/system/${service}" ]; then
                    systemctl restart "${service}"
                    ((count++)) || true
                    echo "  Restarted: $name"
                fi
            fi
        done
    fi
    
    echo ""
    log_success "Restarted $count instance(s)"
}

# Show usage
show_usage() {
    cat << EOF
${BOLD}BF1942 Multi-Instance Manager v${VERSION}${NC}

${BOLD}Usage:${NC} $0 [command] [instance_name]

${BOLD}Commands:${NC}
  ${CYAN}list${NC}              - List all instances and their status
  ${CYAN}ports${NC}             - Show port assignments for all instances
  ${CYAN}status${NC} [name]     - Show detailed status of instance(s)
  ${CYAN}config${NC} <n>        - Show configuration paths for instance
  ${CYAN}health${NC}            - Check health of all instances
  ${CYAN}security${NC}          - Run security audit on all instances
  ${CYAN}backup${NC} <n>        - Create backup of instance configuration
  ${CYAN}start${NC} <n>         - Start an instance
  ${CYAN}stop${NC} <n>          - Stop an instance
  ${CYAN}restart${NC} <n>       - Restart an instance
  ${CYAN}start-all${NC}         - Start all instances
  ${CYAN}stop-all${NC}          - Stop all instances
  ${CYAN}restart-all${NC}       - Restart all instances
  ${CYAN}logs${NC} <n>          - View logs for an instance (tail -f)
  ${CYAN}remove${NC} <n>        - Remove an instance (requires confirmation)

${BOLD}Examples:${NC}
  $0 list
  $0 status server1
  $0 config server1
  $0 health
  $0 security
  $0 backup server1
  sudo $0 restart server1
  sudo $0 start-all
  sudo $0 remove server2

${BOLD}Notes:${NC}
  - Commands that modify services require sudo
  - Use 'default' for standalone server instance
  - Instance names are case-sensitive
  - Run 'security' regularly to check for issues
EOF
}

# Main command handler
main() {
    local command="${1:-}"
    
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
        remove)
            if [ -z "${2:-}" ]; then
                log_error "Instance name required."
                echo "Usage: sudo $0 remove <instance_name>"
                exit 1
            fi
            remove_instance "$2"
            ;;
        help|--help|-h|"")
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
