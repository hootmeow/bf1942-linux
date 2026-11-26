# Restore SELinux file contexts so systemd can execute binaries in /home
if command -v restorecon >/dev/null 2>&1; then
    log_info "Restoring SELinux file contexts..."
    restorecon -Rv "${BF_HOME}" 2>/dev/null || true
fi

