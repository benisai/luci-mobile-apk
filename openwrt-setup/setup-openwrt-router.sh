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
FILES_DIR="$SCRIPT_DIR/files"
INSTALL_PROFILE=""
INSTALL_ADBLOCK=0
INSTALL_PBR=0
INSTALL_NETIFY=0
INSTALL_ADBLOCK_OVERRIDE=""
INSTALL_PBR_OVERRIDE=""
INSTALL_NETIFY_OVERRIDE=""

usage() {
	cat <<'EOF'
Usage: sh openwrt-setup/setup-openwrt-router.sh [--profile=1|2|3] [--with-netify] [--without-netify] [--with-adblock] [--without-adblock] [--with-pbr] [--without-pbr] [--help]

Profiles:
  1  Install Openwalla Stack (Ping, Speedtest, Flows, nlbw, vnstat)
  2  Install Openwalla Stack + Adblock + PBR
  3  Install Openwalla Stack + Adblock + PBR + Netify

Options:
  --profile=N         Choose profile 1, 2, or 3 (non-interactive)
  --with-netify      Install and enable netifyd + netify-collector
  --without-netify   Skip netifyd + netify-collector install (default)
  --with-adblock     Install adblock package(s)
  --without-adblock  Skip adblock package(s)
  --with-pbr         Install pbr package(s)
  --without-pbr      Skip pbr package(s)
  --help             Show this help
EOF
}

prompt_install_profile() {
	while true; do
		cat <<'EOF'

Select installation profile:
  1) Install Openwalla Stack (Ping, Speedtest, Flows, nlbw, vnstat)
  2) Install Openwalla Stack + Adblock + PBR
  3) Install Openwalla Stack + Adblock + PBR + Netify
EOF
		printf "Enter option [1-3] (default: 1): "
		read -r choice
		choice="${choice:-1}"
		case "$choice" in
		1|2|3)
			INSTALL_PROFILE="$choice"
			return 0
			;;
		*)
			echo "Invalid selection: $choice"
			;;
		esac
	done
}

apply_install_profile() {
	case "$INSTALL_PROFILE" in
	1)
		INSTALL_ADBLOCK=0
		INSTALL_PBR=0
		INSTALL_NETIFY=0
		;;
	2)
		INSTALL_ADBLOCK=1
		INSTALL_PBR=1
		INSTALL_NETIFY=0
		;;
	3)
		INSTALL_ADBLOCK=1
		INSTALL_PBR=1
		INSTALL_NETIFY=1
		;;
	*)
		echo "Invalid profile: $INSTALL_PROFILE"
		exit 1
		;;
	esac
}

for arg in "$@"; do
	case "$arg" in
	--profile=*)
		INSTALL_PROFILE="${arg#*=}"
		;;
	--with-netify)
		INSTALL_NETIFY_OVERRIDE=1
		;;
	--without-netify)
		INSTALL_NETIFY_OVERRIDE=0
		;;
	--with-adblock)
		INSTALL_ADBLOCK_OVERRIDE=1
		;;
	--without-adblock)
		INSTALL_ADBLOCK_OVERRIDE=0
		;;
	--with-pbr)
		INSTALL_PBR_OVERRIDE=1
		;;
	--without-pbr)
		INSTALL_PBR_OVERRIDE=0
		;;
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

if [ -z "$INSTALL_PROFILE" ]; then
	if [ "$#" -eq 0 ] && [ -t 0 ]; then
		prompt_install_profile
	else
		INSTALL_PROFILE=1
	fi
fi

apply_install_profile

[ -n "$INSTALL_ADBLOCK_OVERRIDE" ] && INSTALL_ADBLOCK="$INSTALL_ADBLOCK_OVERRIDE"
[ -n "$INSTALL_PBR_OVERRIDE" ] && INSTALL_PBR="$INSTALL_PBR_OVERRIDE"
[ -n "$INSTALL_NETIFY_OVERRIDE" ] && INSTALL_NETIFY="$INSTALL_NETIFY_OVERRIDE"

log "Selected profile=$INSTALL_PROFILE (adblock=$INSTALL_ADBLOCK pbr=$INSTALL_PBR netify=$INSTALL_NETIFY)"

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

require_file "$FILES_DIR/openwalla-connection-flow-collector.sh"
require_file "$FILES_DIR/openwalla-ping-monitor.sh"
require_file "$FILES_DIR/openwalla-dns-monitor.sh"
require_file "$FILES_DIR/openwalla-speedtest-monitor.sh"
require_file "$FILES_DIR/openwalla-notifications-db.sh"
require_file "$FILES_DIR/openwalla-state-sync.sh"
require_file "$FILES_DIR/openwalla-device-quarantine.sh"
require_file "$FILES_DIR/openwalla-device-bandwidth-collector.sh"
require_file "$FILES_DIR/openwalla-device-traffic-summary.sh"
require_file "$FILES_DIR/openwalla-paternal-pause.sh"
require_file "$FILES_DIR/openwalla-connection-flows-collector.init"
require_file "$FILES_DIR/openwalla-device-bandwidth-collector.init"
require_file "$FILES_DIR/openwalla-ping-monitor.init"
require_file "$FILES_DIR/openwalla-dns-monitor.init"
require_file "$FILES_DIR/openwalla-state-sync.init"
require_file "$FILES_DIR/openwalla-device-quarantine.init"
require_file "$FILES_DIR/openwalla.config"
require_file "$SCRIPT_DIR/rpcd-acl.json"
if [ "$INSTALL_NETIFY" = "1" ]; then
	require_file "$FILES_DIR/openwalla-netify-collector.sh"
	require_file "$FILES_DIR/openwalla-netify-collector.init"
fi

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
	nano \
	htop \
	gawk \
	grep \
	sed \
	coreutils-sort \
	uhttpd-mod-ubus \
	vnstat2 \
	vnstati2 \
	luci-app-vnstat2 \
	nlbwmon \
	luci-app-nlbwmon \
	banip \
	luci-app-banip \
	qos-scripts \
	luci-app-qos \
	sqm-scripts \
	luci-app-sqm \
	wireguard-tools \
	kmod-wireguard \
	luci-proto-wireguard \
	tcpdump-mini \
	qrencode \
	sqlite3-cli
do
	install_pkg_if_available "$pkg"
done

if [ "$INSTALL_ADBLOCK" = "1" ]; then
	install_pkg_if_available "adblock"
	install_pkg_if_available "luci-app-adblock"
fi

if [ "$INSTALL_PBR" = "1" ]; then
	install_pkg_if_available "pbr"
	install_pkg_if_available "luci-app-pbr"
fi

if [ "$INSTALL_NETIFY" = "1" ]; then
	install_pkg_if_available "netifyd"
fi

# Dependency package names can vary between opkg and apk feeds.
if [ "$INSTALL_NETIFY" = "1" ]; then
	install_first_available_pkg "netcat" netcat netcat-openbsd
fi
install_first_available_pkg "sqlite-cli" sqlite3-cli sqlite3
install_first_available_pkg "speedtest" speedtestcpp python3-speedtest-cli

log "Installing backend workers and init scripts"
install_file "$FILES_DIR/openwalla-connection-flow-collector.sh" /usr/bin/openwalla-connection-flow-collector 0755
install_file "$FILES_DIR/openwalla-ping-monitor.sh" /usr/bin/openwalla-ping-monitor 0755
install_file "$FILES_DIR/openwalla-dns-monitor.sh" /usr/bin/openwalla-dns-monitor 0755
install_file "$FILES_DIR/openwalla-speedtest-monitor.sh" /usr/bin/openwalla-speedtest-monitor 0755
install_file "$FILES_DIR/openwalla-notifications-db.sh" /usr/bin/openwalla-notifications-db 0755
install_file "$FILES_DIR/openwalla-state-sync.sh" /usr/bin/openwalla-state-sync 0755
install_file "$FILES_DIR/openwalla-device-quarantine.sh" /usr/bin/openwalla-device-quarantine 0755
install_file "$FILES_DIR/openwalla-device-bandwidth-collector.sh" /usr/bin/openwalla-device-bandwidth-collector 0755
install_file "$FILES_DIR/openwalla-device-traffic-summary.sh" /usr/bin/openwalla-device-traffic-summary 0755
install_file "$FILES_DIR/openwalla-paternal-pause.sh" /usr/bin/openwalla-paternal-pause 0755
install_file "$FILES_DIR/openwalla-connection-flows-collector.init" /etc/init.d/openwalla-connection-flows-collector 0755
install_file "$FILES_DIR/openwalla-device-bandwidth-collector.init" /etc/init.d/openwalla-device-bandwidth-collector 0755
install_file "$FILES_DIR/openwalla-ping-monitor.init" /etc/init.d/openwalla-ping-monitor 0755
install_file "$FILES_DIR/openwalla-dns-monitor.init" /etc/init.d/openwalla-dns-monitor 0755
install_file "$FILES_DIR/openwalla-state-sync.init" /etc/init.d/openwalla-state-sync 0755
install_file "$FILES_DIR/openwalla-device-quarantine.init" /etc/init.d/openwalla-device-quarantine 0755
install_file "$SCRIPT_DIR/rpcd-acl.json" /usr/share/rpcd/acl.d/openwalla.json 0644
if [ "$INSTALL_NETIFY" = "1" ]; then
	install_file "$FILES_DIR/openwalla-netify-collector.sh" /usr/bin/openwalla-netify-collector 0755
	install_file "$FILES_DIR/openwalla-netify-collector.init" /etc/init.d/openwalla-netify-collector 0755
fi

if [ -f /etc/config/openwalla ]; then
	cp /etc/config/openwalla "/etc/config/openwalla.bak.$(date +%Y%m%d%H%M%S)"
	log "Backed up existing /etc/config/openwalla"
fi
install_file "$FILES_DIR/openwalla.config" /etc/config/openwalla 0644

log "Setting uhttpd home to /www"
set_uci uhttpd.main.home "/www"
uci commit uhttpd

log "Applying Openwalla runtime defaults"
set_uci openwalla.features.qosify "1"
set_uci openwalla.features.sqm "1"
set_uci openwalla.features.banip "1"
set_uci openwalla.features.adblock "$INSTALL_ADBLOCK"
set_uci openwalla.features.pbr "$INSTALL_PBR"
set_uci openwalla.features.netify "$INSTALL_NETIFY"
set_uci openwalla.collector.enabled "$INSTALL_NETIFY"
set_uci openwalla.collector.host "127.0.0.1"
set_uci openwalla.collector.port "7150"
set_uci openwalla.collector.db_path "/tmp/openwalla-netify.sqlite"
set_uci openwalla.collector.retention_rows "500000"
set_uci openwalla.collector.stream_timeout "45"
set_uci openwalla.collector.exclude_protocols "MDNS,DNS,QUIC,DHCPv6,ICMP"
set_uci openwalla.collector.ignore_wan_source "1"
set_uci openwalla.connection_flows.enabled "1"
set_uci openwalla.connection_flows.db_path "/tmp/openwalla-connection-flows.sqlite"
set_uci openwalla.connection_flows.poll_seconds "5"
set_uci openwalla.connection_flows.retention_rows "50000"
set_uci openwalla.connection_flows.exclude_endpoints "127.0.0.1"
set_uci openwalla.connection_flows.ignore_ipv6 "1"
set_uci openwalla.connection_flows.lan_to_wan_only "0"
set_uci openwalla.device_bandwidth.enabled "1"
set_uci openwalla.device_bandwidth.db_path "/tmp/openwalla-device-bandwidth.sqlite"
set_uci openwalla.device_bandwidth.poll_seconds "60"
set_uci openwalla.device_bandwidth.bucket_seconds "900"
set_uci openwalla.device_bandwidth.retention_seconds "86400"
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
set_uci openwalla.speedtest_monitor.run_hour "3"
set_uci openwalla.speedtest_monitor.run_minute "15"
set_uci openwalla.speedtest_monitor.bin "/usr/bin/speedtest"
set_uci openwalla.speedtest_monitor.output_file "/tmp/openwalla-speedtest-monitor.txt"
set_uci openwalla.speedtest_monitor.max_lines "365"
set_uci openwalla.dashboard.provider "auto"
set_uci openwalla.dashboard.window_seconds "900"
set_uci openwalla.dashboard.vnstat_interface "br-lan"
set_uci openwalla.quarantine.enabled "0"
set_uci openwalla.quarantine.interval "15"
set_uci openwalla.quarantine.leases_file "/tmp/dhcp.leases"
set_uci openwalla.quarantine.state_file "/tmp/openwalla-quarantine-known.txt"
set_uci openwalla.quarantine.rule_prefix "openwalla_quarantine_"
set_uci openwalla.state_backup.backup_time "720"
set_uci openwalla.state_backup.state_dir "/overlay/openwalla-state"
set_uci openwalla.notifications.db_path "/tmp/openwalla-notifications.sqlite"
uci commit openwalla

if [ "$INSTALL_NETIFY" = "1" ]; then
	NETIFYD_CONF="/etc/netifyd.conf"
	if [ -f "$NETIFYD_CONF" ]; then
		if grep -q "^listen_address\[0\]" "$NETIFYD_CONF"; then
			sed -i "s|^listen_address\[0\].*|listen_address[0] = 127.0.0.1|" "$NETIFYD_CONF"
		else
			grep -q "^\[socket\]" "$NETIFYD_CONF" || echo "[socket]" >>"$NETIFYD_CONF"
			sed -i "/^\[socket\]/a listen_address[0] = 127.0.0.1" "$NETIFYD_CONF"
		fi
		log "Updated netifyd listen_address[0] to 127.0.0.1"
	fi
elif [ -x /etc/init.d/openwalla-netify-collector ]; then
	/etc/init.d/openwalla-netify-collector stop || true
	/etc/init.d/openwalla-netify-collector disable || true
fi

NLBW_CONF="/etc/config/nlbwmon"
if [ -f "$NLBW_CONF" ]; then
	sed -i "s/option refresh_interval '30s'/option refresh_interval '10s'/" "$NLBW_CONF"
	sed -i "s/option refresh_interval 30s/option refresh_interval 10s/" "$NLBW_CONF"
	log "Set nlbwmon refresh_interval to 10s"
fi

log "Initializing data files"
if [ "$INSTALL_NETIFY" = "1" ] && [ -x /usr/bin/openwalla-netify-collector ]; then
	/usr/bin/openwalla-netify-collector --init-db || true
fi
/usr/bin/openwalla-connection-flow-collector --init-db || true
/usr/bin/openwalla-device-bandwidth-collector --init-db || true
/usr/bin/openwalla-device-bandwidth-collector --once || true
/usr/bin/openwalla-ping-monitor --once || true
/usr/bin/openwalla-dns-monitor --once || true
/usr/bin/openwalla-speedtest-monitor --init-file || true
/usr/bin/openwalla-notifications-db --init-db || true
/usr/bin/openwalla-state-sync restore || true
/usr/bin/openwalla-state-sync sync-cron || true

if [ "$INSTALL_NETIFY" = "1" ] && ! have_cmd nc; then
	log "WARNING: nc command not found; netify collector will not ingest flows."
fi
if [ "$INSTALL_NETIFY" = "1" ] && ! have_cmd sqlite3 && ! have_cmd sqlite3-cli; then
	log "WARNING: sqlite3/sqlite3-cli not found; netify collector and UI sqlite queries will fail."
fi

log "Enabling and restarting services"
/etc/init.d/rpcd restart || true
/etc/init.d/uhttpd restart || true

for legacy_svc in connection-flows-collector ping-monitor dns-monitor netify-collector; do
	if [ -x "/etc/init.d/$legacy_svc" ]; then
		/etc/init.d/"$legacy_svc" stop || true
		/etc/init.d/"$legacy_svc" disable || true
		log "Legacy service disabled: $legacy_svc"
	fi
done

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

log "Applying paternal pause cron schedule"
PATERNAL_PAUSE_MARKER="# OPENWALLA_PATERNAL_PAUSE"
TMP_CRON="/tmp/.openwalla_paternal_pause_cron.$$"
if [ -f "$CRON_PATH" ]; then
	grep -v "$PATERNAL_PAUSE_MARKER" "$CRON_PATH" >"$TMP_CRON" 2>/dev/null || : >"$TMP_CRON"
else
	: >"$TMP_CRON"
fi
echo "* * * * * /usr/bin/openwalla-paternal-pause apply >/tmp/openwalla-paternal-pause.last.log 2>&1 $PATERNAL_PAUSE_MARKER" >>"$TMP_CRON"
cp "$TMP_CRON" "$CRON_PATH"
rm -f "$TMP_CRON"

log "Removing legacy paternal time-of-use cron schedule"
PATERNAL_MARKER="# OPENWALLA_PATERNAL_TIME"
TMP_CRON="/tmp/.openwalla_paternal_cron.$$"
if [ -f "$CRON_PATH" ]; then
	grep -v "$PATERNAL_MARKER" "$CRON_PATH" >"$TMP_CRON" 2>/dev/null || : >"$TMP_CRON"
	cp "$TMP_CRON" "$CRON_PATH"
	rm -f "$TMP_CRON"
fi
rm -f /usr/bin/openwalla-paternal-time 2>/dev/null || true

while :; do
	LEGACY_SECTION="$(uci show firewall 2>/dev/null | awk -F'[.=]' '$1 == "firewall" && $3 == "name" && $0 ~ /openwalla_paternal_time_/ { print $2; exit }')"
	[ -n "$LEGACY_SECTION" ] || break
	uci -q delete "firewall.$LEGACY_SECTION" 2>/dev/null || true
done
while :; do
	LEGACY_SECTION="$(uci show openwalla 2>/dev/null | sed -n 's/^openwalla\.\([^.=]*\)=paternal_rule$/\1/p' | head -n 1)"
	[ -n "$LEGACY_SECTION" ] || break
	uci -q delete "openwalla.$LEGACY_SECTION" 2>/dev/null || true
done
uci commit firewall 2>/dev/null || true
uci commit openwalla 2>/dev/null || true
/bin/sh -c '/etc/init.d/cron reload 2>/dev/null || /etc/init.d/cron restart 2>/dev/null || /etc/init.d/crond reload 2>/dev/null || /etc/init.d/crond restart 2>/dev/null || killall -HUP crond 2>/dev/null || true'

SERVICES="vnstat nlbwmon openwalla-connection-flows-collector openwalla-device-bandwidth-collector openwalla-ping-monitor openwalla-dns-monitor openwalla-state-sync openwalla-device-quarantine"
if [ "$INSTALL_NETIFY" = "1" ]; then
	SERVICES="vnstat nlbwmon netifyd openwalla-netify-collector openwalla-connection-flows-collector openwalla-device-bandwidth-collector openwalla-ping-monitor openwalla-dns-monitor openwalla-state-sync openwalla-device-quarantine"
fi
if [ "$INSTALL_ADBLOCK" = "1" ]; then
	SERVICES="$SERVICES adblock"
fi
if [ "$INSTALL_PBR" = "1" ]; then
	SERVICES="$SERVICES pbr"
fi
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
