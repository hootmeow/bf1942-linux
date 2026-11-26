elif ! command -v firewall-cmd >/dev/null 2>&1; then
    log_warn "firewalld not found - skipping firewall configuration"
else
    if ! systemctl is-active --quiet firewalld; then
        log_info "Starting firewalld..."
        systemctl enable --now firewalld
    fi
    if [ -z "$FW_ACTIVE" ]; then
        allow_existing_server_ports firewalld
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

        choose_mgmt_access

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
    FW_APPLIED="firewalld"
    log_success "Firewall configured"
fi
