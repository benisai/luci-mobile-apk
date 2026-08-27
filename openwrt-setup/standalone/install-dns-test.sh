#!/bin/sh

# Compatibility wrapper for DNS test installs.
# Delegates to install-dns-monitor.sh so old setup names keep working.

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
exec "$SCRIPT_DIR/install-dns-monitor.sh" "$@"
