#!/bin/sh

# Standalone installer for Openwalla WireGuard support.
# Installs WireGuard tools, kernel/protocol support, and LuCI helpers when available.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
. "$SCRIPT_DIR/lib/openwalla-standalone-common.sh"

log "Installing Openwrt WireGuard support"

require_file "$FILES_DIR/openwalla.config"
require_file "$RPCD_ACL"

update_package_feeds
install_pkg_if_available "wireguard-tools"
install_pkg_if_available "kmod-wireguard"
install_pkg_if_available "luci-proto-wireguard"
install_pkg_if_available "luci-app-wireguard"

ensure_openwalla_config
ensure_uci_section features ui
install_rpcd_acl

set_uci openwalla.features.wireguard "1"
uci commit openwalla

log "WireGuard support installed."
