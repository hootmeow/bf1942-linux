#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  Assemble the per-distro installers from src/.
#
#  Every installer is generated from src/installer.sh.in. Lines of the form
#      #@include name     (required)
#      #@include? name    (optional hook - nothing is inserted if absent)
#  are replaced by name.sh, searched in the FRAGMENTS directories listed in
#  src/distros/<distro>/distro.conf (first match wins). @@KEY@@ placeholders
#  are then filled from the same distro.conf.
#
#  Usage:
#    ./src/build.sh          regenerate installers/
#    ./src/build.sh --check  exit 1 if installers/ is out of date with src/
#
#  Users still download a single self-contained script for their distro;
#  edit src/ and rebuild instead of editing installers/ directly.
# ---------------------------------------------------------------------------

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SRC")"
CHECK=0

case "${1:-}" in
    "") ;;
    --check) CHECK=1 ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1 (use --check or --help)" >&2; exit 1 ;;
esac

find_fragment() {
    local name="$1" dir
    for dir in $FRAGMENTS; do
        if [ -f "${SRC}/${dir}/${name}.sh" ]; then
            echo "${SRC}/${dir}/${name}.sh"
            return 0
        fi
    done
    return 1
}

expand() {
    local file="$1" depth="$2" line name optional frag
    if [ "$depth" -gt 5 ]; then
        echo "${DISTRO}: includes nested too deeply in ${file}" >&2
        exit 1
    fi
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        if [[ "$line" =~ ^#@include(\?)?\ ([a-z_]+)$ ]]; then
            optional="${BASH_REMATCH[1]}"
            name="${BASH_REMATCH[2]}"
            if frag=$(find_fragment "$name"); then
                expand "$frag" $((depth + 1))
            elif [ -z "$optional" ]; then
                echo "${DISTRO}: required fragment '${name}' not found in: ${FRAGMENTS}" >&2
                exit 1
            fi
        else
            printf '%s\n' "$line"
        fi
    done < "$file"
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

stale=0
for conf in "${SRC}"/distros/*/distro.conf; do
    DISTRO=$(basename "$(dirname "$conf")")
    OUTPUT="" LABEL="" PKG_TOOL="" OS_ID="" OS_NAME="" OS_VERSION="" FRAGMENTS=""
    # shellcheck source=/dev/null
    . "$conf"
    for key in OUTPUT LABEL PKG_TOOL OS_ID OS_NAME FRAGMENTS; do
        if [ -z "${!key}" ]; then
            echo "${DISTRO}: ${key} is not set in ${conf}" >&2
            exit 1
        fi
    done

    out="${TMP}/${DISTRO}.sh"
    expand "${SRC}/installer.sh.in" 0 > "$out"

    text=$(<"$out")
    text="${text//@@LABEL@@/"$LABEL"}"
    text="${text//@@PKG_TOOL@@/"$PKG_TOOL"}"
    text="${text//@@OS_ID@@/"$OS_ID"}"
    text="${text//@@OS_NAME@@/"$OS_NAME"}"
    text="${text//@@OS_VERSION@@/"$OS_VERSION"}"
    if [[ "$text" =~ @@[A-Z_]+@@ ]]; then
        echo "${DISTRO}: unknown placeholder ${BASH_REMATCH[0]}" >&2
        exit 1
    fi
    printf '%s\n' "$text" > "$out"

    if ! bash -n "$out"; then
        echo "${DISTRO}: generated script has a syntax error" >&2
        exit 1
    fi

    target="${ROOT}/${OUTPUT}"
    if [ "$CHECK" -eq 1 ]; then
        # Compare ignoring CR so a Windows checkout does not report drift.
        if ! [ -f "$target" ] || ! cmp -s "$out" <(tr -d '\r' < "$target"); then
            echo "out of date: ${OUTPUT}"
            stale=1
        fi
    else
        mkdir -p "$(dirname "$target")"
        cp "$out" "$target"
        chmod 755 "$target"
        echo "built: ${OUTPUT}"
    fi
done

if [ "$CHECK" -eq 1 ]; then
    if [ "$stale" -eq 1 ]; then
        echo "Run ./src/build.sh and commit the result." >&2
        exit 1
    fi
    echo "installers/ is up to date."
fi
