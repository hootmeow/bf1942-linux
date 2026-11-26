    # Enable EPEL and CRB (CodeReady Linux Builder) for compat packages
    dnf install -y dnf-plugins-core
    dnf install -y epel-release || \
        dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm || true
    dnf config-manager --enable crb 2>/dev/null || \
        dnf config-manager --enable codeready-builder-for-rhel-9-$(arch)-rpms 2>/dev/null || \
        log_warn "Could not enable CRB - some packages may be unavailable"

