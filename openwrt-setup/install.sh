#!/bin/sh

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
exec sh "$SCRIPT_DIR/setup-openwrt-router.sh" "$@"
