#!/bin/sh
# Container entrypoint for xara.
#   (no args / options)      -> xara --config /config/xara.conf --state-dir /state [--registered] "$@"
#   xara-monitor | any exe   -> exec that command instead
# Command-line options override values from the config file.
set -eu

CONFIG=${XARA_CONFIG:-/config/xara.conf}
STATE=${XARA_STATE_DIR:-/state}

# First argument is a command (not an option): run it directly.
if [ $# -gt 0 ]; then
    case "$1" in
        -*) ;;
        *) exec "$@" ;;
    esac
fi

# Informational invocations need no config.
for a in "$@"; do
    case "$a" in
        --help|-h|--version|-V|--list-devices) exec xara "$@" ;;
    esac
done

if [ ! -r "$CONFIG" ]; then
    echo "xara: config file $CONFIG not found or unreadable." >&2
    echo "xara: mount one, e.g. -v ./xara.conf:/config/xara.conf:ro (see docker/xara.conf.example)." >&2
    exit 1
fi

case "${XARA_REGISTERED:-0}" in
    1|true|TRUE|yes) set -- --registered "$@" ;;
esac

exec xara --config "$CONFIG" --state-dir "$STATE" "$@"
