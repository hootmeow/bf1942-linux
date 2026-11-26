ARCH_PKGS=()
for pkg in lib32-glibc lib32-gcc-libs lib32-ncurses wget curl tar; do
    if ! pacman -Q "$pkg" >/dev/null 2>&1; then
        ARCH_PKGS+=("$pkg")
    fi
done

if [ ${#ARCH_PKGS[@]} -gt 0 ]; then
    log_info "Installing missing dependencies: ${ARCH_PKGS[*]}..."
    pacman -S --needed --noconfirm "${ARCH_PKGS[@]}"
else
    log_success "All required multilib packages are already installed."
fi

touch /etc/bf1942_deps_installed 2>/dev/null || true

