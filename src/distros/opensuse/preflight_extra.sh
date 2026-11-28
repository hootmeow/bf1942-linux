
# Fail before any questions if the repositories have no 32-bit packages.
# ZYPP_LOCK_TIMEOUT: wait for PackageKit / another zypper instead of failing.
if run_quiet --soft "Checking for 32-bit packages" \
        env ZYPP_LOCK_TIMEOUT=180 zypper --non-interactive --gpg-auto-import-keys search --match-exact glibc-32bit; then
    :
elif env ZYPP_LOCK_TIMEOUT=180 zypper --non-interactive search --match-exact glibc >/dev/null 2>&1; then
    log_error "This release has no 32-bit packages (glibc-32bit) - Battlefield 1942 can't run on it."
    echo "  The server is a 32-bit program. Use openSUSE Leap 16 / Tumbleweed, Debian, Ubuntu or Fedora."
    exit 1
else
    log_warn "Couldn't reach the package repositories to check for 32-bit support - continuing."
fi
