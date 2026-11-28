
# Fail before any questions if this release has no 32-bit packages at all
# (Enterprise Linux 10 and Amazon Linux 2023 don't; Fedora has discussed
# dropping them). The metadata dnf downloads here is reused by the install.
if run_quiet --soft "Checking for 32-bit (i686) packages" dnf -q list glibc.i686; then
    :
elif dnf -q -C list glibc.x86_64 >/dev/null 2>&1; then
    # Repository metadata is there, so glibc.i686 really doesn't exist.
    log_error "This release has no 32-bit (i686) packages - Battlefield 1942 can't run on it."
    echo "  The server is a 32-bit program. Use Debian, Ubuntu, Fedora 43-45, an EL 9 release"
    echo "  (RHEL / Rocky / Alma / CentOS Stream 9) or openSUSE instead."
    exit 1
else
    log_warn "Couldn't reach the package repositories to check for 32-bit support - continuing."
fi
