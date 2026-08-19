#!/bin/sh

# Openwalla OpenWrt bootstrap script
# Intended for fresh/new routers and safe to rerun.

set -u

if [ "$(id -u)" != "0" ]; then
	echo "Run as root."
	exit 1
fi

log() {
	echo "[openwalla-setup] $*"
}

have_cmd() {
	command -v "$1" >/dev/null 2>&1
}

SCRIPT_PATH="$0"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" 2>/dev/null && pwd)"

# Direct-download source. Override either variable when testing a branch/fork:
#   OPENWALLA_GITHUB_REF=my-branch sh ./setup-openwrt-router.sh
#   OPENWALLA_RAW_BASE=https://example.com/path sh ./setup-openwrt-router.sh
OPENWALLA_GITHUB_REPO="${OPENWALLA_GITHUB_REPO:-benisai/luci-mobile-apk}"
OPENWALLA_GITHUB_REF="${OPENWALLA_GITHUB_REF:-main}"
OPENWALLA_RAW_BASE="${OPENWALLA_RAW_BASE:-https://raw.githubusercontent.com/$OPENWALLA_GITHUB_REPO/$OPENWALLA_GITHUB_REF/openwrt-setup}"

LOCAL_FILES_DIR="$SCRIPT_DIR/files"
LOCAL_RPCD_ACL="$SCRIPT_DIR/rpcd-acl.json"
DOWNLOAD_ROOT="/tmp/openwalla-setup.$$"
DOWNLOAD_FILES_DIR="$DOWNLOAD_ROOT/files"

# These are selected later. If a complete local checkout is present, it is
# still used; otherwise the files are downloaded directly from GitHub.
FILES_DIR="$LOCAL_FILES_DIR"
RPCD_ACL_FILE="$LOCAL_RPCD_ACL"

usage() {
	cat <<'EOF'
Usage: sh setup-openwrt-router.sh [--help]

Installs the recommended Openwalla core packages and supporting router scripts.
Required assets are downloaded directly from the luci-mobile-apk GitHub repo
when a local openwrt-setup/files directory is not present.
EOF
}

for arg in "$@"; do
	case "$arg" in
	--help|-h)
		usage
		exit 0
		;;
	*)
		echo "Unknown option: $arg"
		usage
		exit 1
		;;
	esac
done

log "Installing Openwalla core stack"

require_file() {
	if [ ! -f "$1" ]; then
		echo "Missing required file: $1"
		exit 1
	fi
}

install_file() {
	src="$1"
	dst="$2"
	mode="$3"
	mkdir -p "$(dirname "$dst")"
	cp "$src" "$dst"
	chmod "$mode" "$dst"
	log "Installed $dst"
}

download_url() {
	url="$1"
	dst="$2"

	mkdir -p "$(dirname "$dst")"

	if have_cmd uclient-fetch; then
		uclient-fetch -q -O "$dst" "$url" && return 0
	elif have_cmd wget; then
		wget -q -O "$dst" "$url" && return 0
	elif have_cmd curl; then
		curl -fsSL "$url" -o "$dst" && return 0
	else
		echo "No downloader found. Need uclient-fetch, wget, or curl."
		return 1
	fi

	rm -f "$dst"
	return 1
}

download_required_asset() {
	relative_path="$1"
	dst="$2"
	url="$OPENWALLA_RAW_BASE/$relative_path"

	log "Downloading $relative_path"
	if ! download_url "$url" "$dst"; then
		echo "Failed to download: $url"
		exit 1
	fi
}

prepare_source_files() {
	if [ -f "$LOCAL_FILES_DIR/openwalla-ping-monitor.sh" ] && \
	   [ -f "$LOCAL_FILES_DIR/openwalla-dns-monitor.sh" ] && \
	   [ -f "$LOCAL_FILES_DIR/openwalla-speedtest-monitor.sh" ] && \
	   [ -f "$LOCAL_FILES_DIR/openwalla-notifications-db.sh" ] && \
	   [ -f "$LOCAL_FILES_DIR/openwalla-state-sync.sh" ] && \
	   [ -f "$LOCAL_FILES_DIR/openwalla-devices-collector.sh" ] && \
	   [ -f "$LOCAL_FILES_DIR/openwalla-device-bandwidth-collector.sh" ] && \
	   [ -f "$LOCAL_FILES_DIR/openwalla-device-traffic-summary.sh" ] && \
	   [ -f "$LOCAL_FILES_DIR/openwalla-devices-collector.init" ] && \
	   [ -f "$LOCAL_FILES_DIR/openwalla-device-bandwidth-collector.init" ] && \
	   [ -f "$LOCAL_FILES_DIR/openwalla-ping-monitor.init" ] && \
	   [ -f "$LOCAL_FILES_DIR/openwalla-dns-monitor.init" ] && \
	   [ -f "$LOCAL_FILES_DIR/openwalla-state-sync.init" ] && \
	   [ -f "$LOCAL_FILES_DIR/openwalla.config" ] && \
	   [ -f "$LOCAL_RPCD_ACL" ]; then
		FILES_DIR="$LOCAL_FILES_DIR"
		RPCD_ACL_FILE="$LOCAL_RPCD_ACL"
		log "Using local setup files from $SCRIPT_DIR"
		return 0
	fi

	log "Downloading required Openwalla core router files"
	log "Source: $OPENWALLA_RAW_BASE"
	mkdir -p "$DOWNLOAD_FILES_DIR"

	for name in \
		openwalla-ping-monitor.sh \
		openwalla-dns-monitor.sh \
		openwalla-speedtest-monitor.sh \
		openwalla-notifications-db.sh \
		openwalla-state-sync.sh \
		openwalla-devices-collector.sh \
		openwalla-device-bandwidth-collector.sh \
		openwalla-device-traffic-summary.sh \
		openwalla-devices-collector.init \
		openwalla-device-bandwidth-collector.init \
		openwalla-ping-monitor.init \
		openwalla-dns-monitor.init \
		openwalla-state-sync.init \
		openwalla.config
	do
		download_required_asset "files/$name" "$DOWNLOAD_FILES_DIR/$name"
	done

	download_required_asset "rpcd-acl.json" "$DOWNLOAD_ROOT/rpcd-acl.json"

	FILES_DIR="$DOWNLOAD_FILES_DIR"
	RPCD_ACL_FILE="$DOWNLOAD_ROOT/rpcd-acl.json"
}
cleanup_downloads() {
	[ -d "$DOWNLOAD_ROOT" ] && rm -rf "$DOWNLOAD_ROOT"
}

trap cleanup_downloads EXIT INT TERM

install_pkg_if_available() {
	pkg="$1"
	case "$PKG_MGR" in
	opkg)
		if opkg list-installed | grep -q "^$pkg -"; then
			log "Package already installed: $pkg"
			return 0
		fi
		if ! opkg list | grep -q "^$pkg -"; then
			log "Package unavailable in current feed, skipping: $pkg"
			return 1
		fi
		opkg install "$pkg" && log "Installed package: $pkg" && return 0
		log "Failed to install package: $pkg"
		return 1
		;;
	apk)
		if apk info -e "$pkg" >/dev/null 2>&1; then
			log "Package already installed: $pkg"
			return 0
		fi
		if ! apk search -x "$pkg" >/dev/null 2>&1; then
			log "Package unavailable in current feed, skipping: $pkg"
			return 1
		fi
		apk add "$pkg" && log "Installed package: $pkg" && return 0
		log "Failed to install package: $pkg"
		return 1
		;;
	*)
		log "No supported package manager available; skipping package: $pkg"
		return 1
		;;
	esac
}

install_first_available_pkg() {
	label="$1"
	shift
	for candidate in "$@"; do
		[ -n "$candidate" ] || continue
		if install_pkg_if_available "$candidate"; then
			log "Using package for $label: $candidate"
			return 0
		fi
	done
	log "No installable package found for $label"
	return 1
}

set_uci() {
	key="$1"
	value="$2"
	value="${value#\'}"
	value="${value%\'}"
	value="${value#\"}"
	value="${value%\"}"
	uci set "$key=$value"
}

prepare_source_files

require_file "$FILES_DIR/openwalla-ping-monitor.sh"
require_file "$FILES_DIR/openwalla-dns-monitor.sh"
require_file "$FILES_DIR/openwalla-speedtest-monitor.sh"
require_file "$FILES_DIR/openwalla-notifications-db.sh"
require_file "$FILES_DIR/openwalla-state-sync.sh"
require_file "$FILES_DIR/openwalla-devices-collector.sh"
require_file "$FILES_DIR/openwalla-device-bandwidth-collector.sh"
require_file "$FILES_DIR/openwalla-device-traffic-summary.sh"
require_file "$FILES_DIR/openwalla-devices-collector.init"
require_file "$FILES_DIR/openwalla-device-bandwidth-collector.init"
require_file "$FILES_DIR/openwalla-ping-monitor.init"
require_file "$FILES_DIR/openwalla-dns-monitor.init"
require_file "$FILES_DIR/openwalla-state-sync.init"
require_file "$FILES_DIR/openwalla.config"
require_file "$RPCD_ACL_FILE"

log "Updating package feeds"
PKG_MGR=""
if have_cmd opkg; then
	PKG_MGR="opkg"
	opkg update
elif have_cmd apk; then
	PKG_MGR="apk"
	apk update
else
	log "No supported package manager found (opkg/apk). Package install steps will be skipped."
fi

for pkg in \
	uhttpd-mod-ubus \
	vnstat2 \
	vnstati2 \
	luci-app-vnstat2 \
	nlbwmon \
	luci-app-nlbwmon \
	qrencode \
	sqlite3-cli \
	conntrack
do
	install_pkg_if_available "$pkg"
done

# Required by the requested openwalla-speedtest-monitor worker.
install_first_available_pkg "speedtest" speedtestcpp speedtest python3-speedtest-cli || \
	log "WARNING: no speedtest package found; speedtest monitor will log 'binary not found'."

log "Installing backend workers and init scripts"
install_file "$FILES_DIR/openwalla-ping-monitor.sh" /usr/bin/openwalla-ping-monitor 0755
install_file "$FILES_DIR/openwalla-dns-monitor.sh" /usr/bin/openwalla-dns-monitor 0755
install_file "$FILES_DIR/openwalla-speedtest-monitor.sh" /usr/bin/openwalla-speedtest-monitor 0755
install_file "$FILES_DIR/openwalla-notifications-db.sh" /usr/bin/openwalla-notifications-db 0755
install_file "$FILES_DIR/openwalla-state-sync.sh" /usr/bin/openwalla-state-sync 0755
install_file "$FILES_DIR/openwalla-devices-collector.sh" /usr/bin/openwalla-devices-collector 0755
install_file "$FILES_DIR/openwalla-device-bandwidth-collector.sh" /usr/bin/openwalla-device-bandwidth-collector 0755
install_file "$FILES_DIR/openwalla-device-traffic-summary.sh" /usr/bin/openwalla-device-traffic-summary 0755

install_file "$FILES_DIR/openwalla-devices-collector.init" /etc/init.d/openwalla-devices-collector 0755
install_file "$FILES_DIR/openwalla-device-bandwidth-collector.init" /etc/init.d/openwalla-device-bandwidth-collector 0755
install_file "$FILES_DIR/openwalla-ping-monitor.init" /etc/init.d/openwalla-ping-monitor 0755
install_file "$FILES_DIR/openwalla-dns-monitor.init" /etc/init.d/openwalla-dns-monitor 0755
install_file "$FILES_DIR/openwalla-state-sync.init" /etc/init.d/openwalla-state-sync 0755

install_file "$RPCD_ACL_FILE" /usr/share/rpcd/acl.d/openwalla.json 0644

if [ -f /etc/config/openwalla ]; then
	cp /etc/config/openwalla "/etc/config/openwalla.bak.$(date +%Y%m%d%H%M%S)"
	log "Backed up existing /etc/config/openwalla"
fi
install_file "$FILES_DIR/openwalla.config" /etc/config/openwalla 0644

log "Setting uhttpd home to /www"
set_uci uhttpd.main.home "/www"
uci commit uhttpd

log "Applying Openwalla runtime defaults"
set_uci openwalla.device_bandwidth.enabled "1"
set_uci openwalla.device_bandwidth.db_path "/tmp/openwalla-device-bandwidth.sqlite"
set_uci openwalla.device_bandwidth.poll_seconds "60"
set_uci openwalla.device_bandwidth.bucket_seconds "900"
set_uci openwalla.device_bandwidth.retention_seconds "86400"
set_uci openwalla.devices.enabled "1"
set_uci openwalla.devices.db_path "/tmp/openwalla-devices.sqlite"
set_uci openwalla.devices.poll_seconds "60"
set_uci openwalla.devices.offline_after_seconds "300"
set_uci openwalla.ping_monitor.enabled "1"
set_uci openwalla.ping_monitor.target "1.1.1.1"
set_uci openwalla.ping_monitor.interval "60"
set_uci openwalla.ping_monitor.threshold "100"
set_uci openwalla.ping_monitor.warning_percent "95"
set_uci openwalla.ping_monitor.timeout "2"
set_uci openwalla.ping_monitor.output_file "/tmp/openwalla-ping-monitor.txt"
set_uci openwalla.ping_monitor.max_lines "2000"
set_uci openwalla.dns_monitor.enabled "1"
set_uci openwalla.dns_monitor.target "openwrt.org"
set_uci openwalla.dns_monitor.interval "60"
set_uci openwalla.dns_monitor.threshold "1000"
set_uci openwalla.dns_monitor.timeout "3"
set_uci openwalla.dns_monitor.output_file "/tmp/openwalla-dns-monitor.txt"
set_uci openwalla.dns_monitor.max_lines "2000"
set_uci openwalla.speedtest_monitor.enabled "1"
set_uci openwalla.speedtest_monitor.run_date "$(date +%Y-%m-%d)"
set_uci openwalla.speedtest_monitor.run_hour "3"
set_uci openwalla.speedtest_monitor.run_minute "15"
set_uci openwalla.speedtest_monitor.bin "/usr/bin/speedtest"
set_uci openwalla.speedtest_monitor.output_file "/tmp/openwalla-speedtest-monitor.txt"
set_uci openwalla.speedtest_monitor.max_lines "365"
set_uci openwalla.dashboard.provider "auto"
set_uci openwalla.dashboard.window_seconds "900"
set_uci openwalla.dashboard.vnstat_interface "br-lan"
set_uci openwalla.state_backup.backup_time "720"
set_uci openwalla.state_backup.state_dir "/overlay/openwalla-state"
set_uci openwalla.notifications.db_path "/tmp/openwalla-notifications.sqlite"
uci commit openwalla

NLBW_CONF="/etc/config/nlbwmon"
if [ -f "$NLBW_CONF" ]; then
	sed -i "s/option refresh_interval '30s'/option refresh_interval '10s'/" "$NLBW_CONF"
	sed -i "s/option refresh_interval 30s/option refresh_interval 10s/" "$NLBW_CONF"
	log "Set nlbwmon refresh_interval to 10s"
fi

log "Initializing data files"
/usr/bin/openwalla-devices-collector --init-db || true
/usr/bin/openwalla-devices-collector --once || true
/usr/bin/openwalla-device-bandwidth-collector --init-db || true
/usr/bin/openwalla-device-bandwidth-collector --once || true
/usr/bin/openwalla-ping-monitor --once || true
/usr/bin/openwalla-dns-monitor --once || true
/usr/bin/openwalla-speedtest-monitor --init-file || true
/usr/bin/openwalla-notifications-db --init-db || true
/usr/bin/openwalla-state-sync restore || true
/usr/bin/openwalla-state-sync sync-cron || true

log "Enabling and restarting services"
/etc/init.d/rpcd restart || true
/etc/init.d/uhttpd restart || true

log "Applying daily speedtest cron schedule"
SPEEDTEST_MARKER="# OPENWALLA_SPEEDTEST_MONITOR"
CRON_PATH="/etc/crontabs/root"
TMP_CRON="/tmp/.openwalla_cron.$$"
HOUR="$(uci -q get openwalla.speedtest_monitor.run_hour 2>/dev/null || echo 3)"
MINUTE="$(uci -q get openwalla.speedtest_monitor.run_minute 2>/dev/null || echo 15)"
ENABLED="$(uci -q get openwalla.speedtest_monitor.enabled 2>/dev/null || echo 1)"
case "$HOUR" in ''|*[!0-9]*) HOUR=3 ;; esac
case "$MINUTE" in ''|*[!0-9]*) MINUTE=15 ;; esac
if [ "$HOUR" -gt 23 ]; then HOUR=3; fi
if [ "$MINUTE" -gt 59 ]; then MINUTE=15; fi
if [ -f "$CRON_PATH" ]; then
	grep -v "$SPEEDTEST_MARKER" "$CRON_PATH" >"$TMP_CRON" 2>/dev/null || : >"$TMP_CRON"
else
	: >"$TMP_CRON"
fi
if [ "$ENABLED" = "1" ]; then
	echo "$MINUTE $HOUR * * * /usr/bin/openwalla-speedtest-monitor --once >/tmp/openwalla-speedtest-monitor.last.log 2>&1 $SPEEDTEST_MARKER" >>"$TMP_CRON"
fi
cp "$TMP_CRON" "$CRON_PATH"
rm -f "$TMP_CRON"

SERVICES="vnstat nlbwmon openwalla-devices-collector openwalla-device-bandwidth-collector openwalla-ping-monitor openwalla-dns-monitor openwalla-state-sync"
for svc in $SERVICES; do
	if [ -x "/etc/init.d/$svc" ]; then
		/etc/init.d/"$svc" enable || true
		/etc/init.d/"$svc" restart || true
		log "Service restarted: $svc"
	fi
done

log "Finalizing web server settings"
/etc/init.d/uhttpd restart || true
uci set uhttpd.main.home='/www'
uci commit uhttpd
/etc/init.d/uhttpd restart || true

log "Ensuring openwalla-state-sync restore runs from rc.local"
if [ -f /etc/rc.local ]; then
	if ! grep -q '/usr/bin/openwalla-state-sync restore' /etc/rc.local 2>/dev/null; then
		RC_TMP="/tmp/.openwalla_rc_local.$$"
		awk '
			BEGIN { added=0 }
			/^exit 0$/ && !added { print "/usr/bin/openwalla-state-sync restore"; added=1 }
			{ print }
			END {
				if (!added) {
					print "/usr/bin/openwalla-state-sync restore"
					print "exit 0"
				}
			}
		' /etc/rc.local >"$RC_TMP"
		cp "$RC_TMP" /etc/rc.local
		rm -f "$RC_TMP"
	fi
else
	cat <<'EOF' >/etc/rc.local
/usr/bin/openwalla-state-sync restore
exit 0
EOF
fi
chmod +x /etc/rc.local

log "Setup complete."
log "Openwalla router helper services are installed."

exit 0
