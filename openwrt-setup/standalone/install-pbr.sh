#!/bin/sh

# Standalone installer for Openwalla PBR support.
# Installs OpenWrt policy-based routing packages and enables the feature flag.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
. "$SCRIPT_DIR/lib/openwalla-standalone-common.sh"

log "Installing Openwrt PBR support"

require_file "$FILES_DIR/openwalla.config"
require_file "$RPCD_ACL"

update_package_feeds
install_pkg_if_available "pbr"
install_pkg_if_available "luci-app-pbr"

ensure_openwalla_config
ensure_uci_section features ui
install_rpcd_acl

set_uci openwalla.features.pbr "1"
uci commit openwalla

enable_restart_service pbr

log "PBR support installed."
