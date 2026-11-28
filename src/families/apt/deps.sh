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

