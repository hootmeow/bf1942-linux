# Set up isolated local library directory
mkdir -p "${BF_ROOT}/lib"
if [ -f "/usr/lib32/libncursesw.so.6" ]; then
    ln -sf /usr/lib32/libncursesw.so.6 "${BF_ROOT}/lib/libncurses.so.5"
    log_success "Created isolated ncurses compatibility link in ${BF_ROOT}/lib"
elif [ -f "/usr/lib32/libncurses.so.6" ]; then
    ln -sf /usr/lib32/libncurses.so.6 "${BF_ROOT}/lib/libncurses.so.5"
    log_success "Created isolated ncurses compatibility link in ${BF_ROOT}/lib"
fi

# Link the static BF1942 binary (eliminates legacy libstdc++5 dependency)
if [ -f "bf1942_lnxded.static" ]; then
    ln -sf bf1942_lnxded.static bf1942_lnxded
    log_success "Configured static binary (bf1942_lnxded -> bf1942_lnxded.static)"
elif [ -f "bf1942_lnxded.dynamic" ]; then
    ln -sf bf1942_lnxded.dynamic bf1942_lnxded
    log_warn "Static binary not found, using dynamic binary"
else
    log_error "Server binary not found"
    exit 1
fi
