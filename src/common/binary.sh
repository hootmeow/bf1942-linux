if [ -f "bf1942_lnxded.dynamic" ]; then
    ln -sf bf1942_lnxded.dynamic bf1942_lnxded
    log_success "Symlink created"
else
    log_error "Server binary not found"
    exit 1
fi
