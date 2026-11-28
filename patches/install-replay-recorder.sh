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
# Always installs the newest recorder-v* release (checked against the
# release's recorder.so.sha256), so upstream updates need no change here.
#
# Usage:
#   sudo bash install-replay-recorder.sh                  interactive menu
#   sudo bash install-replay-recorder.sh --update         update every installed recorder, no prompts
#   sudo bash install-replay-recorder.sh --prune-replays 30   delete replays older than 30 days
#   sudo RECORDER_TAG=recorder-v0.3.0 bash install-replay-recorder.sh   pin a version
#
# --update and --prune-replays can be combined, e.g. nightly from cron:
#   /etc/cron.d/bf1942-recorder:
#   30 5 * * * root /path/to/install-replay-recorder.sh --update --prune-replays 30 >> /var/log/bf1942-recorder.log 2>&1
# ------------------------------------------------------------
set -euo pipefail

REPO="sila-skandia/bfstats"
# Used only when the GitHub API can't be reached (offline, rate limit).
FALLBACK_TAG="recorder-v0.3.1"
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

usage() { sed -n '/^# Usage:/,/^# ----/p' "$0" | sed '$d; s/^# \{0,1\}//'; }

# ------------------------------------------------------------
# Arguments
# ------------------------------------------------------------
ASSUME_YES=0      # non-interactive: every prompt takes its default
DO_UPDATE=0
PRUNE_DAYS=""
while [ $# -gt 0 ]; do
    case "$1" in
        --update) DO_UPDATE=1; ASSUME_YES=1 ;;
        --prune-replays)
            [ $# -ge 2 ] || { err "--prune-replays needs a number of days"; exit 1; }
            PRUNE_DAYS="$2"; ASSUME_YES=1; shift ;;
        --prune-replays=*) PRUNE_DAYS="${1#*=}"; ASSUME_YES=1 ;;
        -h|--help) usage; exit 0 ;;
        *) err "Unknown option: $1"; usage; exit 1 ;;
    esac
    shift
done
if [ -n "$PRUNE_DAYS" ] && { [[ ! "$PRUNE_DAYS" =~ ^[0-9]+$ ]] || [ "$PRUNE_DAYS" -lt 1 ]; }; then
    err "--prune-replays takes a whole number of days (1 or more)"; exit 1
fi

confirm() {   # confirm "question" [default y|n]
    local d="${2:-y}" a
    if [ "$ASSUME_YES" = 1 ]; then
        [ "$d" = y ]; return
    fi
    local p="[Y/n]"; [ "$d" = n ] && p="[y/N]"
    read -r -p "  $1 $p " a
    a="${a:-$d}"
    [[ "$a" =~ ^[Yy] ]]
}
pause() { echo; read -r -p "  Press Enter to continue..." _; }

[ "$(id -u)" -eq 0 ] || { err "Run with sudo."; exit 1; }
command -v curl >/dev/null || { err "curl is required."; exit 1; }

# One copy at a time (a cron --update must not race an interactive session).
if command -v flock >/dev/null; then
    exec 9>/run/bf1942-replay-recorder.lock
    flock -n 9 || { err "Another copy of this script is already running."; exit 1; }
fi

# Downloaded recorder.so, removed on exit (including Ctrl-C).
DL=""
cleanup() { [ -n "$DL" ] && rm -f "$DL"; return 0; }
trap cleanup EXIT
trap 'echo; exit 130' INT TERM

# ------------------------------------------------------------
# Release lookup
# ------------------------------------------------------------
# Newest published (not draft / pre-release) recorder-v* tag. The repo has
# other releases too, so /releases/latest isn't necessarily the recorder.
latest_recorder_tag() {
    curl -fsS --max-time 10 -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/${REPO}/releases?per_page=30" 2>/dev/null |
        awk -F'"' '
            /"tag_name":/   { tag = $4 }
            /"draft":/      { draft = ($0 ~ /true/) }
            /"prerelease":/ { if (!found && tag ~ /^recorder-v/ && !draft && $0 !~ /true/) { print tag; found = 1 } }
        '
    # (awk reads to the end: exiting early would SIGPIPE curl and fail the pipe)
}

TAG_SOURCE=latest
if [ -n "${RECORDER_TAG:-}" ]; then
    TAG="$RECORDER_TAG"
    TAG_SOURCE=pinned
    TAG_NOTE="pinned via RECORDER_TAG"
elif TAG="$(latest_recorder_tag)" && [ -n "$TAG" ]; then
    TAG_NOTE="latest release"
else
    TAG="$FALLBACK_TAG"
    TAG_SOURCE=fallback
    TAG_NOTE="GitHub API unreachable - using built-in ${FALLBACK_TAG}"
fi
[[ "$TAG" =~ ^recorder-v[0-9A-Za-z._-]+$ ]] || { err "Unexpected release tag: $TAG"; exit 1; }
VERSION="${TAG#recorder-}"
URL="https://github.com/${REPO}/releases/download/${TAG}/recorder.so"
SHA_URL="${URL}.sha256"

installed_version() { cat "$1/recorder.version" 2>/dev/null || true; }

# version_gt A B: A is a newer version than B
version_gt() {
    [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n 1)" = "$1" ]
}

# Does this install need the release we resolved? Unknown version = yes
# (installed before versions were tracked). Never offers a downgrade.
update_available() {
    local iv; iv="$(installed_version "$1")"
    [ -z "$iv" ] || version_gt "$VERSION" "$iv"
}

# 32-bit ELF shared object? Reads the header directly - 'file' isn't
# installed on many minimal server images.
is_elf32_so() {
    local h
    h="$(od -An -tx1 -N18 "$1" 2>/dev/null | tr -d ' \n')"
    # magic 7f 'E' 'L' 'F', EI_CLASS 01 = 32-bit, e_type (bytes 16-17) 03 00 = ET_DYN
    [ "${h:0:10}" = "7f454c4601" ] && [ "${h:32:4}" = "0300" ]
}

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
        local iv; iv="$(installed_version "$d")"
        [ -n "$iv" ] && version_gt "$VERSION" "$iv" && s="$s, ${Y}$iv -> $VERSION available${N}"
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
    if [ -f "$d/recorder.so" ]; then
        local iv; iv="$(installed_version "$d")"
        if [ -z "$iv" ]; then
            echo "  recorder:  $d/recorder.so (version unknown - reinstall to track it)"
        elif [ "$iv" = "$VERSION" ]; then
            echo "  recorder:  $d/recorder.so ${G}$iv (up to date)${N}"
        elif version_gt "$VERSION" "$iv"; then
            echo "  recorder:  $d/recorder.so ${Y}$iv - $VERSION available, use Install / update${N}"
        else
            echo "  recorder:  $d/recorder.so $iv (newer than $VERSION, $TAG_NOTE)"
        fi
    else
        echo "  recorder:  not installed"
    fi
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
        n="$(find "$d/replays" -maxdepth 1 -name '*.ndjson*' | wc -l)"
        sz="$(du -sh "$d/replays" 2>/dev/null | cut -f1)"
        echo "  Replays:   $n file(s), $sz in $d/replays"
        if [ "$n" -gt 0 ]; then
            echo "  Latest:"
            ls -1t "$d/replays"/*.ndjson* 2>/dev/null | head -n 3 | sed 's/^/             /'
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
# Download (once per run, shared by every install that needs it)
# ------------------------------------------------------------
fetch_recorder() {
    [ -n "$DL" ] && [ -s "$DL" ] && return 0
    step "Downloading recorder.so $VERSION"
    DL="$(mktemp)"
    local prog="--progress-bar"; [ -t 1 ] || prog="-sS"
    if ! curl -fL --retry 3 "$prog" -o "$DL" "$URL"; then
        err "Download failed: $URL"; rm -f "$DL"; DL=""; return 1
    fi
    local want got
    want="$(curl -fsSL --retry 3 "$SHA_URL" 2>/dev/null | awk '{print $1; exit}' || true)"
    got="$(sha256sum "$DL" | cut -d' ' -f1)"
    if [[ ! "$want" =~ ^[0-9a-f]{64}$ ]]; then
        warn "No recorder.so.sha256 published for $TAG - can't verify the download."
        confirm "Install it unverified?" n || { rm -f "$DL"; DL=""; return 1; }
    elif [ "$want" != "$got" ]; then
        err "Checksum mismatch for recorder.so $VERSION"
        echo "     Expected $want"
        echo "     Got      $got"
        rm -f "$DL"; DL=""; return 1
    else
        ok "Checksum verified"
    fi
    if ! is_elf32_so "$DL"; then
        err "Downloaded file isn't a 32-bit Linux shared object."; rm -f "$DL"; DL=""; return 1
    fi
    ok "Downloaded ($(du -h "$DL" | cut -f1))"
}

place_recorder_so() {   # copy the verified download into the install
    local d="$1"
    # Temp name + mv so a running server never sees a half-written .so
    if ! { install -m 755 -o "$USR" -g "$USR" "$DL" "$d/recorder.so.new" &&
           mv -f "$d/recorder.so.new" "$d/recorder.so"; }; then
        rm -f "$d/recorder.so.new"
        err "Couldn't write $d/recorder.so"; return 1
    fi
    echo "$VERSION" > "$d/recorder.version"
    chown "$USR:$USR" "$d/recorder.version"
    ok "recorder.so $VERSION"
}

# ------------------------------------------------------------
# Actions
# ------------------------------------------------------------
do_install() {
    local d="$1" hz svc a SWITCH_STATIC=0
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
    local iv; iv="$(installed_version "$d")"
    if [ -n "$iv" ] && version_gt "$iv" "$VERSION"; then
        warn "Installed $iv is newer than $VERSION ($TAG_NOTE)."
        confirm "Downgrade to $VERSION?" n || return
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

    fetch_recorder || return

    step "Stopping server"
    stop_server "$d" || return

    step "Installing files"
    remove_legacy_wrapper "$d"
    if [ "${SWITCH_STATIC:-0}" = 1 ]; then
        ln -sfn bf1942_lnxded.static "$d/bf1942_lnxded"
        chown -h "$USR:$USR" "$d/bf1942_lnxded"
        ok "bf1942_lnxded -> bf1942_lnxded.static"
    fi

    place_recorder_so "$d" || return

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

# Update recorder.so on every install that already has the recorder.
# Keeps each recorder.con (on/off, sample rate) and only restarts servers
# that were running. Returns 1 if any install failed.
update_all() {
    local d svc iv was_active failed=0 n=0 todo=()
    local installs; mapfile -t installs < <(find_installs)
    step "Update recorder to $VERSION ($TAG_NOTE)"
    if [ "$ASSUME_YES" = 1 ] && [ "$TAG_SOURCE" = fallback ]; then
        err "Can't reach the GitHub API to find the latest release - nothing updated."
        return 1
    fi
    for d in "${installs[@]}"; do
        installed "$d" || continue
        n=$((n + 1))
        iv="$(installed_version "$d")"
        if update_available "$d"; then
            todo+=("$d")
            echo "  $(basename "$d"): ${iv:-unknown version} -> $VERSION"
        else
            ok "$(basename "$d"): $iv, up to date"
        fi
    done
    if [ "$n" -eq 0 ]; then warn "No installs have the recorder."; return 0; fi
    if [ "${#todo[@]}" -eq 0 ]; then ok "Everything is up to date."; return 0; fi
    confirm "Update ${#todo[@]} install(s)? Running servers restart (players disconnect)." y || return 0

    fetch_recorder || return 1
    for d in "${todo[@]}"; do
        step "$(basename "$d")"
        svc="$(service_for "$d")"
        static_ok "$d" || warn "bf1942_lnxded.static isn't the supported build - recordings may stay partial."
        was_active=0
        systemctl is-active --quiet "$svc" && was_active=1
        if [ "$was_active" = 1 ]; then
            systemctl stop "$svc" && ok "Stopped $svc" || { err "Couldn't stop $svc"; failed=1; continue; }
        fi
        remove_legacy_wrapper "$d"
        place_recorder_so "$d" || failed=1
        if [ "$was_active" = 1 ]; then
            if systemctl start "$svc"; then ok "Started $svc"; else err "Couldn't start $svc"; failed=1; fi
        else
            ok "$svc was stopped - left stopped"
        fi
    done
    return "$failed"
}

# Delete replay files older than N days in one install. Prints what it did.
prune_install() {   # prune_install dir days
    local d="$1" days="$2" n sz
    [ -d "$d/replays" ] || return 0
    n="$(find "$d/replays" -maxdepth 1 -type f -name '*.ndjson*' -mtime +"$days" | wc -l)"
    if [ "$n" -eq 0 ]; then
        ok "$(basename "$d"): no replays older than $days days"
        return 0
    fi
    sz="$(find "$d/replays" -maxdepth 1 -type f -name '*.ndjson*' -mtime +"$days" -printf '%s\n' |
          awk '{s += $1} END {printf "%.1f MB", s / 1048576}')"
    if [ "$ASSUME_YES" != 1 ]; then
        confirm "Delete $n replay(s) older than $days days ($sz) from $(basename "$d")?" n || return 0
    fi
    find "$d/replays" -maxdepth 1 -type f -name '*.ndjson*' -mtime +"$days" -delete
    ok "$(basename "$d"): deleted $n replay(s), freed $sz"
}

do_prune() {
    local d="$1" days a
    [ -d "$d/replays" ] || { warn "No replays folder."; return; }
    step "Clean up old replays: $(basename "$d") ($(du -sh "$d/replays" 2>/dev/null | cut -f1) in use)"
    read -r -p "  Delete replays older than how many days? [30]: " a
    days="${a:-30}"
    [[ "$days" =~ ^[0-9]+$ ]] && [ "$days" -ge 1 ] || { err "Enter a whole number of days (1 or more)."; return; }
    prune_install "$d" "$days"
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
    rm -f "$d/recorder.so" "$d/recorder.con" "$d/recorder.version"
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
        echo "  ${B}5)${N} Clean up old replays"
        echo "  ${B}6)${N} Remove recorder"
        echo "  ${B}b)${N} Back"
        read -r -p "  Choose: " c
        case "$c" in
            1) do_install "$d"; pause ;;
            2) do_toggle "$d"; pause ;;
            3) show_log "$d"; pause ;;
            4) stop_server "$d" && start_server "$d"; pause ;;
            5) do_prune "$d"; pause ;;
            6) do_remove "$d"; pause ;;
            b|B) return ;;
        esac
    done
}

main_menu() {
    local installs c i outdated
    while true; do
        mapfile -t installs < <(find_installs)
        clear 2>/dev/null || true
        echo "${B}BF1942 Replay Recorder $VERSION${N}  (bfstats.io, $TAG_NOTE)"
        echo
        if [ "${#installs[@]}" -eq 0 ]; then
            err "No BF1942 installs found under $BF_HOME"
            exit 1
        fi
        outdated=0
        echo "  Installs found:"
        for i in "${!installs[@]}"; do
            printf "  ${B}%d)${N} %-24s %s\n" "$((i+1))" "$(basename "${installs[$i]}")" "$(status_line "${installs[$i]}")"
            installed "${installs[$i]}" && update_available "${installs[$i]}" && outdated=$((outdated + 1))
        done
        if [ "$outdated" -gt 0 ]; then
            echo "  ${B}u)${N} Update all ($outdated install(s) not on $VERSION)"
        fi
        echo "  ${B}q)${N} Quit"
        echo
        read -r -p "  Select an install: " c
        [[ "$c" =~ ^[Qq]$ ]] && exit 0
        if [[ "$c" =~ ^[Uu]$ ]]; then
            update_all || true; pause
        elif [[ "$c" =~ ^[0-9]+$ ]] && [ "$c" -ge 1 ] && [ "$c" -le "${#installs[@]}" ]; then
            install_menu "${installs[$((c-1))]}"
        fi
    done
}

# ------------------------------------------------------------
# Entry point
# ------------------------------------------------------------
if [ "$DO_UPDATE" = 1 ] || [ -n "$PRUNE_DAYS" ]; then
    echo "$(date '+%F %T') replay recorder $VERSION ($TAG_NOTE)"
    rc=0
    if [ "$DO_UPDATE" = 1 ]; then
        update_all || rc=1
    fi
    if [ -n "$PRUNE_DAYS" ]; then
        step "Delete replays older than $PRUNE_DAYS days"
        mapfile -t all_installs < <(find_installs)
        for d in "${all_installs[@]}"; do
            prune_install "$d" "$PRUNE_DAYS" || rc=1
        done
    fi
    exit "$rc"
fi

main_menu
