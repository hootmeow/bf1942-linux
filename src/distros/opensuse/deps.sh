if [ ! -f "/etc/bf1942_deps_installed" ]; then
    log_info "First-time setup: Installing 32-bit libraries..."

    ZYPPER=(zypper --non-interactive --gpg-auto-import-keys)
    run_quiet "Refreshing repositories" "${ZYPPER[@]}" refresh

    # openSUSE ships 32-bit libraries as <name>-32bit (installed to /usr/lib),
    # including the legacy libncurses.so.5 - no Debian package needed for it.
    SUSE_PKGS=(glibc-32bit libstdc++6-32bit libgcc_s1-32bit libz1-32bit
               libncurses5-32bit libncurses6-32bit libX11-6-32bit libXext6-32bit
               wget tar curl iproute2 binutils firewalld)
    # Not needed by the server itself; Leap 16 doesn't ship it.
    if "${ZYPPER[@]}" search --match-exact libcurl4-32bit >/dev/null 2>&1; then
        SUSE_PKGS+=(libcurl4-32bit)
    fi

    run_quiet "Installing 32-bit libraries" \
        "${ZYPPER[@]}" install --no-recommends "${SUSE_PKGS[@]}"

    log_info "Installing legacy libstdc++5 (GCC 3.3 compatibility)..."

    pushd "$TEMP_DIR" > /dev/null

    fetch_legacy_deb "pool/main/g/gcc-3.3/libstdc++5_3.3.6-34_i386.deb" "$LIBSTDC5_SHA"

    ar x libstdc++5_3.3.6-34_i386.deb
    if [ -f data.tar.xz ]; then
        tar xJf data.tar.xz
    elif [ -f data.tar.gz ]; then
        tar xzf data.tar.gz
    fi
    find . -name "libstdc++.so.5*" -not -type d -exec cp -a {} /usr/lib/ \;

    popd > /dev/null

    ldconfig

    # Verify the legacy libraries actually landed before recording success -
    # otherwise a broken install would be skipped forever on re-runs.
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
