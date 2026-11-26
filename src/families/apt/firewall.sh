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
    log_success "Firewall configured"
fi
