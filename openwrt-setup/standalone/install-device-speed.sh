#!/bin/sh

# Standalone installer for Openwalla live per-device speed support.
# Installs only conntrack plus the one-shot device traffic summary helper.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
. "$SCRIPT_DIR/lib/openwalla-standalone-common.sh"

log "Installing Openwalla live device speed helper"

require_file "$FILES_DIR/openwalla-device-traffic-summary.sh"
require_file "$RPCD_ACL"

update_package_feeds
install_pkg_if_available "conntrack"

install_file "$FILES_DIR/openwalla-device-traffic-summary.sh" /usr/bin/openwalla-device-traffic-summary 0755
install_rpcd_acl

log "Live device speed helper installed."
log "Test with: /usr/bin/openwalla-device-traffic-summary"
