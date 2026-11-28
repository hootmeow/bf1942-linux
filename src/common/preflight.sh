if ! command -v @@PKG_TOOL@@ &> /dev/null; then
    log_error "This script requires @@PKG_TOOL@@ (@@OS_NAME@@)."
    exit 1
fi
#@include? preflight_extra

# Warn (but allow continuing) when run on another distro or release.
# OS_TARGET_IDS may list several IDs (e.g. a distro and its rebuilds).
OS_TARGET_IDS=" @@OS_ID@@ "
OS_TARGET_VERSION="@@OS_VERSION@@"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$OS_TARGET_IDS" != *" ${ID:-unknown} "* ]]; then
        log_warn "This script is intended for @@OS_NAME@@. Detected: ${PRETTY_NAME:-unknown}"
        if ! confirm_continue; then exit 1; fi
    elif [ -n "$OS_TARGET_VERSION" ] && [[ "${VERSION_ID:-}" != "$OS_TARGET_VERSION"* ]]; then
        log_warn "This script targets @@OS_NAME@@ ${OS_TARGET_VERSION}. Detected: ${PRETTY_NAME:-unknown}"
        if ! confirm_continue; then exit 1; fi
    else
        log_info "Detected: ${PRETTY_NAME:-$ID}"
    fi
fi
