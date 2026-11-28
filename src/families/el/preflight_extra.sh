
# Enterprise Linux 10 (RHEL, Rocky, Alma, CentOS Stream 10) dropped all
# 32-bit (i686) packages, so the 32-bit server can't get its libraries.
EL_MAJOR=""
if [ -f /etc/os-release ]; then
    EL_MAJOR=$(. /etc/os-release; echo "${VERSION_ID%%.*}")
fi
if [[ "$EL_MAJOR" =~ ^[0-9]+$ ]] && [ "$EL_MAJOR" -ge 10 ]; then
    log_error "Enterprise Linux ${EL_MAJOR} has no 32-bit (i686) packages - Battlefield 1942 can't run on it."
    echo "  Use an EL 9 release (RHEL / Rocky / Alma / CentOS Stream 9), Debian, Ubuntu,"
    echo "  Fedora or openSUSE instead."
    exit 1
fi
#@include i386_check
