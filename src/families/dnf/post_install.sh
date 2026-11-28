# Restore SELinux file contexts so systemd can execute binaries in /home
if command -v restorecon >/dev/null 2>&1; then
    log_info "Restoring SELinux file contexts..."
    restorecon -Rv "${BF_HOME}" 2>/dev/null || true
fi

# With SELinux enforcing, systemd may not run programs labelled as home
# directory files (user_home_t): the service fails with status=203/EXEC.
# Label the server folder bin_t, so the service runs as an ordinary
# unconfined system service. A semanage rule survives relabels/restorecon;
# chcon is the fallback when the SELinux tools can't be installed.
if command -v selinuxenabled >/dev/null 2>&1 && selinuxenabled; then
    if ! command -v semanage >/dev/null 2>&1; then
        if command -v dnf >/dev/null 2>&1; then
            run_quiet --soft "Installing SELinux tools (semanage)" \
                dnf install -y policycoreutils-python-utils || true
        elif command -v zypper >/dev/null 2>&1; then
            run_quiet --soft "Installing SELinux tools (semanage)" \
                env ZYPP_LOCK_TIMEOUT=180 zypper --non-interactive install policycoreutils-python-utils || true
        fi
    fi
    SELINUX_SPEC="${BF_ROOT}(/.*)?"
    if command -v semanage >/dev/null 2>&1 &&
        { semanage fcontext -a -t bin_t "$SELINUX_SPEC" 2>/dev/null ||
          semanage fcontext -m -t bin_t "$SELINUX_SPEC" 2>/dev/null; }; then
        restorecon -R "$BF_ROOT" 2>/dev/null || true
        log_success "SELinux: ${BF_ROOT} labelled bin_t (persistent rule)"
    elif chcon -R -t bin_t "$BF_ROOT" 2>/dev/null; then
        log_warn "SELinux: labelled ${BF_ROOT} with chcon (a full relabel would undo it - install policycoreutils-python-utils and re-run with --repair)"
    else
        log_warn "SELinux: couldn't label ${BF_ROOT}. If the service fails with 203/EXEC: sudo chcon -R -t bin_t ${BF_ROOT}"
    fi
fi
