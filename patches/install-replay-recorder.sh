#!/usr/bin/env bash
# ------------------------------------------------------------
# install-replay-recorder.sh
#
# Interactive installer for the bfstats.io server replay recorder.
# Finds the BF1942 installs on this box, lets you pick one, shows its
# current state, and walks through install / update / disable / remove.
#
# Follows the upstream guide:
#   https://github.com/sila-skandia/bfstats/blob/main/features/server-replay-recorder/INSTALL.md
#   - recorder.so + recorder.con in the server root
#   - LD_PRELOAD set via a systemd drop-in on the instance's unit
#   - server must run the stock bf1942_lnxded.static build
#
# Usage: sudo bash install-replay-recorder.sh
# ------------------------------------------------------------
set -euo pipefail

URL="https://github.com/sila-skandia/bfstats/releases/download/recorder-v0.3.0/recorder.so"
VERSION="v0.3.0"
STATIC_SHA256="18237721d2bd92f7bd01902d127cfcb8771b62eea1813ae67de638462e55b2e6"
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
        [ -f "$d/bf1942_lnxded.static" ] || [ -f "$d/bf1942_lnxded.dynamic" ] || continue
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

dropin_for() { echo "/etc/systemd/system/$1.service.d/recorder.conf"; }

server_pid() {    # running bf1942 server process for this install
    local p
    for p in $(pgrep -f bf1942_lnxded 2>/dev/null); do
        [ "$(readlink -f "/proc/$p/cwd" 2>/dev/null)" = "$1" ] && { echo "$p"; return; }
    done
}

running_binary() { readlink -f "/proc/$1/exe" 2>/dev/null; }

has_dropin() { local s; s="$(service_for "$1")"; [ -n "$s" ] && [ -f "$(dropin_for "$s")" ]; }
installed()  { [ -f "$1/recorder.so" ] && has_dropin "$1"; }
enabled()    { grep -qs "^recordReplays[[:space:]]*1" "$1/recorder.con"; }
sample_hz()  { awk '/^replaySampleHz/{print $2}' "$1/recorder.con" 2>/dev/null; }
legacy_wrapper() { grep -qs "replay-recorder wrapper" "$1/bf1942_lnxded"; }

static_ok() {
    [ -f "$1/bf1942_lnxded.static" ] &&
        [ "$(sha256sum "$1/bf1942_lnxded.static" | cut -d' ' -f1)" = "$STATIC_SHA256" ]
}

status_line() {   # one-line summary for the menu
    local d="$1" s pid
    if installed "$d"; then
        enabled "$d" && s="${G}recording${N}" || s="${Y}installed, disabled${N}"
    else
        s="not installed"
    fi
    legacy_wrapper "$d" && s="$s, ${R}old wrapper - reinstall${N}"
    pid="$(server_pid "$d")"
    [ -n "$pid" ] && s="$s, server ${G}running${N}" || s="$s, server ${R}stopped${N}"
    echo "$s"
}

show_status() {
    local d="$1" svc pid bin
    svc="$(service_for "$d")"
    pid="$(server_pid "$d")"
    step "Status: $(basename "$d")"
    echo "  Path:      $d"
    echo "  Service:   ${svc:-${Y}none found${N}}"
    if [ -n "$svc" ]; then
        has_dropin "$d" && echo "  Preload:   ${G}$(dropin_for "$svc")${N}" || echo "  Preload:   ${Y}no drop-in${N}"
    fi
    if legacy_wrapper "$d"; then
        echo "  Binary:    ${R}bf1942_lnxded = old recorder wrapper (forces .dynamic - broken)${N}"
    elif [ -L "$d/bf1942_lnxded" ]; then
        echo "  Binary:    bf1942_lnxded -> $(readlink "$d/bf1942_lnxded")"
    fi
    if [ -f "$d/bf1942_lnxded.static" ]; then
        static_ok "$d" && echo "  Static:    ${G}matches recorder build${N}" \
                       || echo "  Static:    ${R}sha256 mismatch - recorder hooks will be skipped${N}"
    else
        echo "  Static:    ${R}bf1942_lnxded.static missing${N}"
    fi
    [ -f "$d/recorder.so" ] && echo "  recorder:  $d/recorder.so" || echo "  recorder:  not installed"
    if [ -f "$d/recorder.con" ]; then
        enabled "$d" && echo "  Recording: ${G}on${N} @ $(sample_hz "$d") Hz" || echo "  Recording: ${Y}off${N}"
    fi
    for extra in "$d"/mods/*/settings/recorder.con; do
        [ -f "$extra" ] && warn "Override found: $extra (takes precedence over the root recorder.con)"
    done
    if [ -n "$pid" ]; then
        bin="$(running_binary "$pid")"
        echo "  Server:    ${G}running${N} (PID $pid, $(basename "${bin:-?}"))"
        if grep -q recorder.so "/proc/$pid/maps" 2>/dev/null; then
            echo "  Recorder:  ${G}loaded in process${N}"
        else
            echo "  Recorder:  ${R}not loaded in process${N}"
        fi
        [[ "$bin" == *dynamic ]] && warn "Server is running the DYNAMIC binary; the recorder needs .static."
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

show_log() {
    local d="$1" svc; svc="$(service_for "$d")"
    [ -n "$svc" ] || { warn "No service found."; return; }
    step "Recorder log lines ($svc, last 2h)"
    local out
    out="$(journalctl -u "$svc" --since "2 hours ago" --no-pager 2>/dev/null | grep "recorder:" | tail -n 25 || true)"
    if [ -n "$out" ]; then
        echo "$out" | sed 's/^/  /'
        echo "$out" | grep -q "detour skipped\|not hooked" && \
            err "Build mismatch: the server binary isn't the build the recorder expects."
        echo "$out" | grep -q "no recorder.con" && \
            err "recorder.con not found where the server looks for it."
    else
        warn "No 'recorder:' lines - LD_PRELOAD isn't reaching the server."
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
    local i pid=""
    for i in $(seq 1 15); do
        sleep 2
        pid="$(server_pid "$d")"
        [ -n "$pid" ] && break
    done
    if [ -z "$pid" ]; then
        warn "Server process not seen yet (BFSMD may not have launched it). Check status later."
    elif grep -q recorder.so "/proc/$pid/maps" 2>/dev/null; then
        ok "recorder.so is loaded in server PID $pid ($(basename "$(running_binary "$pid")"))"
        echo "  Recording begins when a round starts; check 'View recorder log' after that."
    else
        err "Server is running (PID $pid) but recorder.so is NOT loaded."
    fi
}

# Undo the old wrapper from earlier versions of this script
remove_legacy_wrapper() {
    local d="$1" orig
    legacy_wrapper "$d" || return 0
    rm -f "$d/bf1942_lnxded"
    orig="$(cat "$d/bf1942_lnxded.orig-link" 2>/dev/null || true)"
    if [ "$orig" = "bf1942_lnxded.orig-bin" ]; then
        mv "$d/bf1942_lnxded.orig-bin" "$d/bf1942_lnxded"
    else
        ln -s bf1942_lnxded.static "$d/bf1942_lnxded"
    fi
    rm -f "$d/bf1942_lnxded.orig-link"
    chown -h "$USR:$USR" "$d/bf1942_lnxded"
    ok "Removed old wrapper; bf1942_lnxded -> $(readlink "$d/bf1942_lnxded" 2>/dev/null || echo file)"
}

# ------------------------------------------------------------
# Actions
# ------------------------------------------------------------
do_install() {
    local d="$1" hz tmp svc a SWITCH_STATIC=0
    svc="$(service_for "$d")"
    step "Install / update recorder $VERSION on $(basename "$d")"

    [ -n "$svc" ] || { err "No systemd service found for $d - can't set LD_PRELOAD."; return; }
    if [ ! -f "$d/bf1942_lnxded.static" ]; then
        err "bf1942_lnxded.static not found. The recorder only supports the stock static build."
        return
    fi
    if ! static_ok "$d"; then
        err "bf1942_lnxded.static sha256 doesn't match the build the recorder supports."
        echo "     Expected $STATIC_SHA256"
        echo "     Got      $(sha256sum "$d/bf1942_lnxded.static" | cut -d' ' -f1)"
        echo "     (Binary patches like the CTF fixes change the hash.)"
        confirm "Install anyway? Recordings will likely be partial or empty." n || return
    fi
    if [ -L "$d/bf1942_lnxded" ] && [ "$(readlink "$d/bf1942_lnxded")" != "bf1942_lnxded.static" ]; then
        warn "bf1942_lnxded points to $(readlink "$d/bf1942_lnxded"); the recorder needs .static."
        confirm "Point it at bf1942_lnxded.static?" y || return
        SWITCH_STATIC=1
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
    echo "    4. Add $(dropin_for "$svc") setting LD_PRELOAD"
    echo "    5. Restart $svc"
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
    remove_legacy_wrapper "$d"
    if [ "${SWITCH_STATIC:-0}" = 1 ]; then
        ln -sfn bf1942_lnxded.static "$d/bf1942_lnxded"
        chown -h "$USR:$USR" "$d/bf1942_lnxded"
        ok "bf1942_lnxded -> bf1942_lnxded.static"
    fi

    # Temp name + mv so a running server never sees a half-written .so
    install -m 755 -o "$USR" -g "$USR" "$tmp" "$d/recorder.so.new"; rm -f "$tmp"
    mv -f "$d/recorder.so.new" "$d/recorder.so"
    ok "recorder.so"

    printf 'recordReplays 1\nreplaySampleHz %s\n' "$hz" > "$d/recorder.con"
    chown "$USR:$USR" "$d/recorder.con"
    ok "recorder.con"

    mkdir -p "$d/replays"; chown "$USR:$USR" "$d/replays"
    ok "replays/"

    mkdir -p "/etc/systemd/system/$svc.service.d"
    printf '[Service]\nEnvironment=LD_PRELOAD=%s/recorder.so\n' "$d" > "$(dropin_for "$svc")"
    systemctl daemon-reload
    ok "$(dropin_for "$svc")"

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
    local d="$1" svc; svc="$(service_for "$d")"
    step "Remove recorder from $(basename "$d")"
    [ -f "$d/recorder.so" ] || has_dropin "$d" || legacy_wrapper "$d" || { warn "Nothing to remove."; return; }
    echo "  This removes the LD_PRELOAD drop-in, recorder.so and recorder.con."
    confirm "Continue?" n || return
    stop_server "$d" || return

    remove_legacy_wrapper "$d"
    if [ -n "$svc" ] && [ -f "$(dropin_for "$svc")" ]; then
        rm -f "$(dropin_for "$svc")"
        rmdir "/etc/systemd/system/$svc.service.d" 2>/dev/null || true
        systemctl daemon-reload
        ok "Removed drop-in"
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
        echo "  ${B}3)${N} View recorder log"
        echo "  ${B}4)${N} Restart server"
        echo "  ${B}5)${N} Remove recorder"
        echo "  ${B}b)${N} Back"
        read -r -p "  Choose: " c
        case "$c" in
            1) do_install "$d"; pause ;;
            2) do_toggle "$d"; pause ;;
            3) show_log "$d"; pause ;;
            4) stop_server "$d" && start_server "$d"; pause ;;
            5) do_remove "$d"; pause ;;
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
