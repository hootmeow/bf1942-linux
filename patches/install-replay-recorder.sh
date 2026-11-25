#!/usr/bin/env bash
# ------------------------------------------------------------
# install-replay-recorder.sh
#
# Interactive installer for the bfstats.io server replay recorder.
# Finds the BF1942 installs on this box, lets you pick one, shows its
# current state, and walks through install / update / disable / remove.
#
# Usage: sudo bash install-replay-recorder.sh
# ------------------------------------------------------------
set -euo pipefail

URL="https://github.com/sila-skandia/bfstats/releases/download/recorder-v0.3.0/recorder.so"
VERSION="v0.3.0"
BF_HOME="/home/bf1942_user"
USR="bf1942_user"

if [ -t 1 ]; then
    B=$'\e[1m'; G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; C=$'\e[36m'; N=$'\e[0m'
else
    B=""; G=""; Y=""; R=""; C=""; N=""
fi
ok()   { echo "  ${G}✔${N} $*"; }
warn() { echo "  ${Y}!${N} $*"; }
err()  { echo "  ${R}✘${N} $*"; }
step() { echo; echo "${B}${C}==> $*${N}"; }

confirm() {   # confirm "question" [default y|n]
    local d="${2:-y}" a
    local p="[Y/n]"; [ "$d" = n ] && p="[y/N]"
    read -r -p "  $1 $p " a
    a="${a:-$d}"
    [[ "$a" =~ ^[Yy] ]]
}
pause() { echo; read -r -p "  Press Enter to continue..." _; }

[ "$(id -u)" -eq 0 ] || { err "Run with sudo."; exit 1; }
command -v curl >/dev/null || { err "curl is required."; exit 1; }

# ------------------------------------------------------------
# Discovery
# ------------------------------------------------------------
find_installs() {
    local d
    for d in "$BF_HOME"/bf1942*/ "$BF_HOME"/instances/*/; do
        d="${d%/}"
        [ -f "$d/bf1942_lnxded.dynamic" ] || [ -f "$d/bf1942_lnxded.static" ] || continue
        echo "$d"
    done
}

service_for() {   # systemd unit whose WorkingDirectory is this install
    local f
    for f in /etc/systemd/system/*.service; do
        [ -f "$f" ] || continue
        if grep -qE "^WorkingDirectory=$1/?\$" "$f"; then
            basename "$f" .service
            return
        fi
    done
}

server_pid() {    # running bf1942 server process for this install
    local p
    for p in $(pgrep -f bf1942_lnxded 2>/dev/null); do
        [ "$(readlink -f "/proc/$p/cwd" 2>/dev/null)" = "$1" ] && { echo "$p"; return; }
    done
}

wrapped()  { grep -qs "replay-recorder wrapper" "$1/bf1942_lnxded"; }
enabled()  { grep -qs "^recordReplays[[:space:]]*1" "$1/recorder.con"; }
sample_hz() { awk '/^replaySampleHz/{print $2}' "$1/recorder.con" 2>/dev/null; }

status_line() {   # one-line summary for the menu
    local d="$1" s=""
    if [ -f "$d/recorder.so" ] && wrapped "$d"; then
        enabled "$d" && s="${G}recording${N}" || s="${Y}installed, disabled${N}"
    else
        s="not installed"
    fi
    local pid; pid="$(server_pid "$d")"
    [ -n "$pid" ] && s="$s, server ${G}running${N}" || s="$s, server ${R}stopped${N}"
    echo "$s"
}

show_status() {
    local d="$1" svc pid
    svc="$(service_for "$d")"
    pid="$(server_pid "$d")"
    step "Status: $(basename "$d")"
    echo "  Path:      $d"
    echo "  Service:   ${svc:-${Y}none found${N}}"
    if [ -L "$d/bf1942_lnxded" ]; then
        echo "  Binary:    bf1942_lnxded -> $(readlink "$d/bf1942_lnxded")"
    elif wrapped "$d"; then
        echo "  Binary:    bf1942_lnxded = recorder wrapper -> bf1942_lnxded.dynamic"
    else
        echo "  Binary:    bf1942_lnxded (regular file)"
    fi
    [ -f "$d/recorder.so" ] && echo "  recorder:  $d/recorder.so" || echo "  recorder:  not installed"
    if [ -f "$d/recorder.con" ]; then
        enabled "$d" && echo "  Recording: ${G}on${N} @ $(sample_hz "$d") Hz" || echo "  Recording: ${Y}off${N}"
    fi
    if [ -n "$pid" ]; then
        if grep -q recorder.so "/proc/$pid/maps" 2>/dev/null; then
            echo "  Server:    ${G}running${N} (PID $pid), recorder ${G}loaded${N}"
        else
            echo "  Server:    ${G}running${N} (PID $pid), recorder ${Y}not loaded${N}"
        fi
    else
        echo "  Server:    ${R}not running${N}"
    fi
    if [ -d "$d/replays" ]; then
        local n sz
        n="$(find "$d/replays" -maxdepth 1 -name '*.ndjson' | wc -l)"
        sz="$(du -sh "$d/replays" 2>/dev/null | cut -f1)"
        echo "  Replays:   $n file(s), $sz in $d/replays"
        if [ "$n" -gt 0 ]; then
            echo "  Latest:"
            ls -1t "$d/replays"/*.ndjson 2>/dev/null | head -n 3 | sed 's/^/             /'
        fi
    fi
}

# ------------------------------------------------------------
# Service control
# ------------------------------------------------------------
stop_server() {
    local d="$1" svc; svc="$(service_for "$d")"
    if [ -n "$svc" ]; then
        if systemctl is-active --quiet "$svc"; then
            confirm "Stop $svc now? (players will be disconnected)" y || { warn "Aborted."; return 1; }
            systemctl stop "$svc" && ok "Stopped $svc"
        fi
    elif [ -n "$(server_pid "$d")" ]; then
        warn "Server is running but no systemd service was found. Stop it manually, then continue."
        confirm "Is it stopped?" n || return 1
    fi
}

start_server() {
    local d="$1" svc; svc="$(service_for "$d")"
    if [ -z "$svc" ]; then
        warn "No systemd service found - start the server however you normally do."
        return
    fi
    confirm "Start $svc now?" y || return 0
    systemctl start "$svc" && ok "Started $svc"
    echo "  Waiting for the server to come up..."
    local i pid
    for i in $(seq 1 15); do
        sleep 2
        pid="$(server_pid "$d")"
        [ -n "$pid" ] && break
    done
    if [ -z "$pid" ]; then
        warn "Server process not seen yet (BFSMD may not have launched it). Check status later."
    elif grep -q recorder.so "/proc/$pid/maps" 2>/dev/null; then
        ok "recorder.so is loaded in server PID $pid"
    else
        err "Server is running (PID $pid) but recorder.so is NOT loaded."
        echo "     Whatever launches it is probably calling bf1942_lnxded.static/.dynamic"
        echo "     directly instead of bf1942_lnxded. Point it at bf1942_lnxded."
    fi
}

# ------------------------------------------------------------
# Actions
# ------------------------------------------------------------
do_install() {
    local d="$1" hz tmp
    step "Install / update recorder $VERSION on $(basename "$d")"

    if [ ! -f "$d/bf1942_lnxded.dynamic" ]; then
        err "bf1942_lnxded.dynamic not found. The recorder needs the dynamic binary (LD_PRELOAD can't hook the static one)."
        return
    fi
    if [ -L "$d/bf1942_lnxded" ] && [ "$(readlink "$d/bf1942_lnxded")" = "bf1942_lnxded.static" ]; then
        warn "This install currently runs the STATIC binary. The recorder will switch it to the dynamic one."
        confirm "Continue?" y || return
    fi

    hz="$(sample_hz "$d")"; hz="${hz:-30}"
    read -r -p "  Sample rate in Hz [$hz]: " a
    hz="${a:-$hz}"
    [[ "$hz" =~ ^[0-9]+$ ]] || { err "Not a number."; return; }

    echo
    echo "  This will:"
    echo "    1. Download recorder.so $VERSION to $d/recorder.so"
    echo "    2. Write $d/recorder.con (recordReplays 1, replaySampleHz $hz)"
    echo "    3. Create $d/replays/"
    echo "    4. Replace the bf1942_lnxded symlink with a wrapper that preloads the recorder"
    echo "    5. Restart the server"
    confirm "Go ahead?" y || return

    step "Downloading recorder.so"
    tmp="$(mktemp)"
    if ! curl -fL --retry 3 --progress-bar -o "$tmp" "$URL"; then
        err "Download failed."; rm -f "$tmp"; return
    fi
    if ! file -b "$tmp" | grep -q 'ELF 32-bit.*shared object'; then
        err "Downloaded file isn't a 32-bit .so: $(file -b "$tmp")"; rm -f "$tmp"; return
    fi
    ok "Downloaded ($(du -h "$tmp" | cut -f1))"

    step "Stopping server"
    stop_server "$d" || { rm -f "$tmp"; return; }

    step "Installing files"
    install -m 755 -o "$USR" -g "$USR" "$tmp" "$d/recorder.so"; rm -f "$tmp"
    ok "recorder.so"

    printf 'recordReplays 1\nreplaySampleHz %s\n' "$hz" > "$d/recorder.con"
    chown "$USR:$USR" "$d/recorder.con"
    ok "recorder.con"

    mkdir -p "$d/replays"; chown "$USR:$USR" "$d/replays"
    ok "replays/"

    if ! wrapped "$d"; then
        if [ -L "$d/bf1942_lnxded" ]; then
            readlink "$d/bf1942_lnxded" > "$d/bf1942_lnxded.orig-link"
        elif [ -f "$d/bf1942_lnxded" ]; then
            mv "$d/bf1942_lnxded" "$d/bf1942_lnxded.orig-bin"
            echo bf1942_lnxded.orig-bin > "$d/bf1942_lnxded.orig-link"
        fi
        rm -f "$d/bf1942_lnxded"
    fi
    cat > "$d/bf1942_lnxded" <<EOF
#!/bin/bash
# replay-recorder wrapper (install-replay-recorder.sh)
cd "$d"
export LD_PRELOAD="$d/recorder.so"
exec ./bf1942_lnxded.dynamic "\$@"
EOF
    chmod 755 "$d/bf1942_lnxded"
    chown "$USR:$USR" "$d/bf1942_lnxded" "$d/bf1942_lnxded.orig-link" 2>/dev/null || true
    ok "bf1942_lnxded wrapper"

    step "Starting server"
    start_server "$d"
    show_status "$d"
}

do_toggle() {
    local d="$1"
    [ -f "$d/recorder.con" ] || { err "Recorder isn't installed here."; return; }
    if enabled "$d"; then
        confirm "Recording is ON. Turn it off?" y || return
        sed -i 's/^recordReplays.*/recordReplays 0/' "$d/recorder.con"
        ok "Recording disabled"
    else
        confirm "Recording is OFF. Turn it on?" y || return
        sed -i 's/^recordReplays.*/recordReplays 1/' "$d/recorder.con"
        ok "Recording enabled"
    fi
    warn "Takes effect after a restart."
    if confirm "Restart the server now?" n; then
        stop_server "$d" && start_server "$d"
    fi
}

do_remove() {
    local d="$1"
    step "Remove recorder from $(basename "$d")"
    wrapped "$d" || [ -f "$d/recorder.so" ] || { warn "Nothing to remove."; return; }
    echo "  This restores the original bf1942_lnxded and deletes recorder.so and recorder.con."
    confirm "Continue?" n || return
    stop_server "$d" || return

    if wrapped "$d"; then
        rm -f "$d/bf1942_lnxded"
        local orig; orig="$(cat "$d/bf1942_lnxded.orig-link" 2>/dev/null || echo bf1942_lnxded.dynamic)"
        if [ "$orig" = "bf1942_lnxded.orig-bin" ]; then
            mv "$d/bf1942_lnxded.orig-bin" "$d/bf1942_lnxded"
        else
            ln -s "$orig" "$d/bf1942_lnxded"
        fi
        rm -f "$d/bf1942_lnxded.orig-link"
        chown -h "$USR:$USR" "$d/bf1942_lnxded"
        ok "Restored bf1942_lnxded"
    fi
    rm -f "$d/recorder.so" "$d/recorder.con"
    ok "Removed recorder.so and recorder.con"

    if [ -d "$d/replays" ] && [ -n "$(ls -A "$d/replays")" ]; then
        if confirm "Delete recorded replays in $d/replays too?" n; then
            rm -rf "$d/replays"; ok "Replays deleted"
        else
            ok "Replays kept"
        fi
    fi
    start_server "$d"
}

# ------------------------------------------------------------
# Menus
# ------------------------------------------------------------
install_menu() {
    local d="$1" c
    while true; do
        show_status "$d"
        echo
        echo "  ${B}1)${N} Install / update recorder"
        echo "  ${B}2)${N} Turn recording on/off"
        echo "  ${B}3)${N} Restart server"
        echo "  ${B}4)${N} Remove recorder"
        echo "  ${B}b)${N} Back"
        read -r -p "  Choose: " c
        case "$c" in
            1) do_install "$d"; pause ;;
            2) do_toggle "$d"; pause ;;
            3) stop_server "$d" && start_server "$d"; pause ;;
            4) do_remove "$d"; pause ;;
            b|B) return ;;
        esac
    done
}

main_menu() {
    local installs c i
    while true; do
        mapfile -t installs < <(find_installs)
        clear 2>/dev/null || true
        echo "${B}BF1942 Replay Recorder $VERSION${N}  (bfstats.io)"
        echo
        if [ "${#installs[@]}" -eq 0 ]; then
            err "No BF1942 installs found under $BF_HOME"
            exit 1
        fi
        echo "  Installs found:"
        for i in "${!installs[@]}"; do
            printf "  ${B}%d)${N} %-24s %s\n" "$((i+1))" "$(basename "${installs[$i]}")" "$(status_line "${installs[$i]}")"
        done
        echo "  ${B}q)${N} Quit"
        echo
        read -r -p "  Select an install: " c
        [[ "$c" =~ ^[Qq]$ ]] && exit 0
        if [[ "$c" =~ ^[0-9]+$ ]] && [ "$c" -ge 1 ] && [ "$c" -le "${#installs[@]}" ]; then
            install_menu "${installs[$((c-1))]}"
        fi
    done
}

main_menu
