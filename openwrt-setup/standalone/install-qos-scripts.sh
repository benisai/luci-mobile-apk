#!/bin/sh

# Standalone installer for Openwalla Smart Queue support.
# Installs OpenWrt SQM packages and enables the app feature/config entries.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
. "$SCRIPT_DIR/lib/openwalla-standalone-common.sh"

log "Installing Openwrt SQM packages"

require_file "$FILES_DIR/openwalla.config"
require_file "$RPCD_ACL"

update_package_feeds
install_pkg_if_available "sqm-scripts"
install_pkg_if_available "luci-app-sqm"

ensure_openwalla_config
ensure_uci_section features ui
install_rpcd_acl

set_uci openwalla.features.qosify "1"
set_uci openwalla.features.sqm "1"
uci commit openwalla

log "SQM packages installed."
