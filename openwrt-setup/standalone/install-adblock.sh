#!/bin/sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
. "$SCRIPT_DIR/lib/openwalla-standalone-common.sh"

log "Installing Openwrt AdBlock support"

require_file "$FILES_DIR/openwalla.config"
require_file "$RPCD_ACL"

update_package_feeds
install_pkg_if_available "adblock"
install_pkg_if_available "luci-app-adblock"

ensure_openwalla_config
ensure_uci_section features ui
install_rpcd_acl

uci -q get adblock.global >/dev/null 2>&1 || uci set adblock.global="adblock"
set_uci openwalla.features.adblock "1"
set_uci adblock.global.adb_enabled "1"
set_uci adblock.global.adb_trigger "wan"
uci commit openwalla
uci commit adblock

enable_restart_service adblock

log "AdBlock support installed."
