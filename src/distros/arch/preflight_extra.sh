
if ! grep -q "^\s*\[multilib\]" /etc/pacman.conf; then
    log_error "[multilib] repository is not enabled in /etc/pacman.conf."
    echo "  Battlefield 1942 is a 32-bit application and requires [multilib]."
    echo "  Please enable it by uncommenting [multilib] and Include in /etc/pacman.conf:"
    echo ""
    echo "    [multilib]"
    echo "    Include = /etc/pacman.d/mirrorlist"
    echo ""
    echo "  Then run: sudo pacman -Sy"
    exit 1
fi
