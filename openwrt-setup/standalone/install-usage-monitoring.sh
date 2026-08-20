#!/bin/sh

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
. "$SCRIPT_DIR/lib/openwalla-standalone-common.sh"

log "Installing Openwalla usage monitoring support"

require_file "$FILES_DIR/openwalla.config"
require_file "$RPCD_ACL"

update_package_feeds
install_pkg_if_available "vnstat2"
install_pkg_if_available "vnstati2"
install_pkg_if_available "luci-app-vnstat2"
install_pkg_if_available "nlbwmon"
install_pkg_if_available "luci-app-nlbwmon"

ensure_openwalla_config
ensure_uci_section dashboard dashboard
install_rpcd_acl

set_uci openwalla.dashboard.provider "auto"
set_uci openwalla.dashboard.window_seconds "900"
set_uci openwalla.dashboard.vnstat_interface "br-lan"
uci commit openwalla

NLBW_CONF="/etc/config/nlbwmon"
if [ -f "$NLBW_CONF" ]; then
	sed -i "s/option refresh_interval '30s'/option refresh_interval '10s'/" "$NLBW_CONF"
	sed -i "s/option refresh_interval 30s/option refresh_interval 10s/" "$NLBW_CONF"
	log "Set nlbwmon refresh_interval to 10s"
fi

enable_restart_service vnstat
enable_restart_service nlbwmon

log "Usage monitoring support installed."
