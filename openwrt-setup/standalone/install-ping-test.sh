#!/bin/sh

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
exec "$SCRIPT_DIR/install-ping-monitor.sh" "$@"
