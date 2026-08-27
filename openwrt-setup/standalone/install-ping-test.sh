#!/bin/sh

# Compatibility wrapper for ping test installs.
# Delegates to install-ping-monitor.sh so old setup names keep working.

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
exec "$SCRIPT_DIR/install-ping-monitor.sh" "$@"
