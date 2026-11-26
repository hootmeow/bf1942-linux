elif command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    log_info "Configuring UFW firewall..."
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
    ufw reload
    FW_APPLIED="ufw"
    log_success "UFW firewall updated."
elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state 2>/dev/null | grep -q running; then
    log_info "Configuring firewalld..."
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
    log_success "firewalld updated."
else
    log_info "No active UFW or firewalld detected; skipping firewall rules."
fi
