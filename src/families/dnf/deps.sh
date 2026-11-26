if [ ! -f "/etc/bf1942_deps_installed" ]; then
    log_info "First-time setup: Installing 32-bit libraries..."

#@include? dnf_repos
    # Detect zlib package name - Fedora 36+ ships zlib-ng; EL9 keeps zlib
    if dnf info zlib.i686 &>/dev/null; then
        ZLIB_PKG="zlib.i686"
    else
        ZLIB_PKG="zlib-ng-compat.i686"
    fi
    log_info "Using zlib package: ${ZLIB_PKG}"

    run_quiet "Installing 32-bit libraries" dnf install -y \
        glibc.i686 libstdc++.i686 libgcc.i686 \
        "${ZLIB_PKG}" libcurl.i686 libX11.i686 \
        libXext.i686 ncurses-libs.i686 \
        ncurses-compat-libs.i686 \
        wget tar curl net-tools binutils

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

    # Restore SELinux file contexts
    if command -v restorecon >/dev/null 2>&1; then
        restorecon -Rv "${BF_HOME}" 2>/dev/null || true
    fi

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

