#!/bin/sh

# Openwalla OpenWrt bootstrap script.
# Downloads and runs feature-focused installers from this repo.

set -u

log() {
	echo "[openwalla-setup] $*"
}

have_cmd() {
	command -v "$1" >/dev/null 2>&1
}

OPENWALLA_GITHUB_REPO="${OPENWALLA_GITHUB_REPO:-benisai/luci-mobile-apk}"
OPENWALLA_GITHUB_REF="${OPENWALLA_GITHUB_REF:-main}"
OPENWALLA_RAW_BASE="${OPENWALLA_RAW_BASE:-https://raw.githubusercontent.com/$OPENWALLA_GITHUB_REPO/$OPENWALLA_GITHUB_REF/openwrt-setup}"
OPENWALLA_ROOT="${OPENWALLA_ROOT:-/root/openwalla}"
STANDALONE_DIR="$OPENWALLA_ROOT/standalone"
STANDALONE_LIB_DIR="$STANDALONE_DIR/lib"

FEATURES=""
INSTALLERS=""
INSTALL_PROFILE=""
DRY_RUN=0
USED_FEATURE_ARGS=0
WITH_ADBLOCK=""
WITH_PBR=""
WITH_NETIFY=""

usage() {
	cat <<'EOF'
Usage:
  sh setup-openwrt-router.sh [feature ...] [options]

Examples:
  sh setup-openwrt-router.sh netify
  sh setup-openwrt-router.sh conntrack
  sh setup-openwrt-router.sh ping dns speedtest
  sh setup-openwrt-router.sh monitoring
  sh setup-openwrt-router.sh stack --with-netify
  sh setup-openwrt-router.sh --profile=3

Feature groups:
  stack        Standard Openwrt apps plus Openwalla monitoring, usage,
               notifications, devices, blocking, state sync, quarantine,
               and simple Conntrack flows.
  monitoring   Standard apps plus usage, ping, DNS, speedtest, notifications,
               devices, device bandwidth, blocking, and state sync.
  flows        Simple Conntrack flows plus detailed Netify flows.
  all          Everything in stack plus AdBlock, PBR, Netify, banIP, and QoS/SQM.

Individual features:
  standard          uhttpd-mod-ubus, nlbwmon, vnstat2, sqlite, conntrack, qrencode
  usage            vnstat/nlbwmon usage support
  ping             ping monitor script and init service
  dns              DNS monitor script and init service
  speedtest        speedtest monitor script and cron
  notifications    notifications sqlite helper
  devices          devices sqlite collector
  bandwidth        per-device bandwidth collector
  blocking         internet/parental blocking helper
  conntrack        simple flow collector
  netify           detailed Netify flow collector
  quarantine       device quarantine helper service
  state-sync       Openwalla state backup/sync helper
  adblock          OpenWrt adblock packages and config
  banip            OpenWrt banIP packages and config
  pbr              OpenWrt PBR packages and config
  qos              QoS/SQM packages

Compatibility options:
  --profile=1         Same as stack
  --profile=2         Stack + AdBlock + PBR
  --profile=3         Stack + AdBlock + PBR + Netify
  --with-netify       Add Netify to the selected profile/group
  --without-netify    Remove Netify from the selected profile/group
  --with-adblock      Add AdBlock to the selected profile/group
  --without-adblock   Remove AdBlock from the selected profile/group
  --with-pbr          Add PBR to the selected profile/group
  --without-pbr       Remove PBR from the selected profile/group
  --dry-run           Show what would run without installing
  --help              Show this help

Environment:
  OPENWALLA_RAW_BASE   Override raw GitHub setup URL
  OPENWALLA_ROOT       Override install download dir (default: /root/openwalla)
EOF
}

append_feature() {
	feature="$1"
	case " $FEATURES " in
	*" $feature "*) ;;
	*) FEATURES="$FEATURES $feature" ;;
	esac
}

remove_feature() {
	target="$1"
	next_features=""
	for feature in $FEATURES; do
		if [ "$feature" != "$target" ]; then
			next_features="$next_features $feature"
		fi
	done
	FEATURES="$next_features"
}

append_installer() {
	installer="$1"
	case " $INSTALLERS " in
	*" $installer "*) ;;
	*) INSTALLERS="$INSTALLERS $installer" ;;
	esac
}

feature_to_installer() {
	case "$1" in
	standard) echo "install-standard-apps.sh" ;;
	usage) echo "install-usage-monitoring.sh" ;;
	ping) echo "install-ping-monitor.sh" ;;
	dns) echo "install-dns-monitor.sh" ;;
	speedtest) echo "install-speedtest-monitor.sh" ;;
	notifications) echo "install-notifications-db.sh" ;;
	devices) echo "install-devices-collector.sh" ;;
	bandwidth) echo "install-device-bandwidth.sh" ;;
	blocking) echo "install-internet-blocking.sh" ;;
	conntrack) echo "install-conntrack.sh" ;;
	netify) echo "install-netify.sh" ;;
	quarantine) echo "install-quarantine.sh" ;;
	state-sync) echo "install-state-sync.sh" ;;
	adblock) echo "install-adblock.sh" ;;
	banip) echo "install-banip.sh" ;;
	pbr) echo "install-pbr.sh" ;;
	qos) echo "install-qos-scripts.sh" ;;
	*) return 1 ;;
	esac
}

canonical_feature() {
	case "$1" in
	apps|packages|standard-apps) echo "standard" ;;
	usage|statistics|stats|vnstat|nlbwmon) echo "usage" ;;
	ping|ping-test|ping-monitor) echo "ping" ;;
	dns|dns-test|dns-monitor) echo "dns" ;;
	speedtest|speed-test|speedtest-monitor) echo "speedtest" ;;
	notifications|notification|notifications-db) echo "notifications" ;;
	devices|device-db|devices-collector) echo "devices" ;;
	bandwidth|device-bandwidth|device-bandwidth-collector) echo "bandwidth" ;;
	blocking|internet-blocking|parental-blocking|paternal-pause) echo "blocking" ;;
	conntrack|simple-flow|simple-flows|connection-flows) echo "conntrack" ;;
	netify|detailed-flow|detailed-flows) echo "netify" ;;
	quarantine|device-quarantine) echo "quarantine" ;;
	state-sync|state|backup|sync) echo "state-sync" ;;
	adblock|ad-block) echo "adblock" ;;
	banip|ban-ip) echo "banip" ;;
	pbr) echo "pbr" ;;
	qos|sqm|smart-queue|smartqueue) echo "qos" ;;
	*) return 1 ;;
	esac
}

append_monitoring_features() {
	append_feature standard
	append_feature usage
	append_feature ping
	append_feature dns
	append_feature speedtest
	append_feature notifications
	append_feature devices
	append_feature bandwidth
	append_feature blocking
	append_feature state-sync
}

append_stack_features() {
	append_monitoring_features
	append_feature conntrack
	append_feature quarantine
}

append_all_features() {
	append_stack_features
	append_feature adblock
	append_feature pbr
	append_feature netify
	append_feature banip
	append_feature qos
}

append_feature_arg() {
	arg="$1"
	case "$arg" in
	stack|profile1|default)
		append_stack_features
		;;
	monitoring|monitors)
		append_monitoring_features
		;;
	flows)
		append_feature conntrack
		append_feature netify
		;;
	all|everything|profile3)
		append_all_features
		;;
	profile2)
		append_stack_features
		append_feature adblock
		append_feature pbr
		;;
	*)
		if canonical="$(canonical_feature "$arg")"; then
			append_feature "$canonical"
		else
			echo "Unknown feature: $arg"
			usage
			exit 1
		fi
		;;
	esac
}

prompt_install_profile() {
	while true; do
		cat <<'EOF'

Select installation profile:
  1) Install Openwalla Stack
  2) Install Openwalla Stack + AdBlock + PBR
  3) Install Openwalla Stack + AdBlock + PBR + Netify
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

append_profile_features() {
	case "$1" in
	1)
		append_stack_features
		;;
	2)
		append_stack_features
		append_feature adblock
		append_feature pbr
		;;
	3)
		append_stack_features
		append_feature adblock
		append_feature pbr
		append_feature netify
		;;
	*)
		echo "Invalid profile: $1"
		exit 1
		;;
	esac
}

download_file() {
	url="$1"
	dst="$2"
	mkdir -p "$(dirname "$dst")"
	if have_cmd wget; then
		wget -qO "$dst" "$url" && return 0
	fi
	if have_cmd curl; then
		curl -fsSL "$url" -o "$dst" && return 0
	fi
	echo "Neither wget nor curl is available; cannot download $url"
	return 1
}

download_standalone_runtime() {
	log "Preparing installer runtime in $OPENWALLA_ROOT"
	mkdir -p "$STANDALONE_LIB_DIR"

	download_file "$OPENWALLA_RAW_BASE/standalone/lib/openwalla-standalone-common.sh" \
		"$STANDALONE_LIB_DIR/openwalla-standalone-common.sh" || exit 1
	chmod 0755 "$STANDALONE_LIB_DIR/openwalla-standalone-common.sh"

	for installer in $INSTALLERS; do
		download_file "$OPENWALLA_RAW_BASE/standalone/$installer" "$STANDALONE_DIR/$installer" || exit 1
		chmod 0755 "$STANDALONE_DIR/$installer"
	done
}

resolve_installers() {
	INSTALLERS=""
	for feature in $FEATURES; do
		if installer="$(feature_to_installer "$feature")"; then
			append_installer "$installer"
		else
			echo "No installer mapped for feature: $feature"
			exit 1
		fi
	done
}

run_installers() {
	for installer in $INSTALLERS; do
		log "Running $installer"
		sh "$STANDALONE_DIR/$installer"
	done
}

while [ "$#" -gt 0 ]; do
	case "$1" in
	--profile=*)
		INSTALL_PROFILE="${1#*=}"
		;;
	--with-netify)
		WITH_NETIFY=1
		;;
	--without-netify)
		WITH_NETIFY=0
		;;
	--with-adblock)
		WITH_ADBLOCK=1
		;;
	--without-adblock)
		WITH_ADBLOCK=0
		;;
	--with-pbr)
		WITH_PBR=1
		;;
	--without-pbr)
		WITH_PBR=0
		;;
	--dry-run)
		DRY_RUN=1
		;;
	--help|-h)
		usage
		exit 0
		;;
	--*)
		echo "Unknown option: $1"
		usage
		exit 1
		;;
	*)
		USED_FEATURE_ARGS=1
		append_feature_arg "$1"
		;;
	esac
	shift
done

if [ -n "$INSTALL_PROFILE" ]; then
	append_profile_features "$INSTALL_PROFILE"
elif [ "$USED_FEATURE_ARGS" = "0" ]; then
	if [ -t 0 ]; then
		prompt_install_profile
		append_profile_features "$INSTALL_PROFILE"
	else
		append_stack_features
	fi
fi

[ "$WITH_NETIFY" = "1" ] && append_feature netify
[ "$WITH_NETIFY" = "0" ] && remove_feature netify
[ "$WITH_ADBLOCK" = "1" ] && append_feature adblock
[ "$WITH_ADBLOCK" = "0" ] && remove_feature adblock
[ "$WITH_PBR" = "1" ] && append_feature pbr
[ "$WITH_PBR" = "0" ] && remove_feature pbr

if [ -z "$FEATURES" ]; then
	echo "No features selected."
	usage
	exit 1
fi

resolve_installers

log "Selected features:$FEATURES"
log "Installer order:$INSTALLERS"

if [ "$DRY_RUN" = "1" ]; then
	exit 0
fi

if [ "$(id -u)" != "0" ]; then
	echo "Run as root."
	exit 1
fi

download_standalone_runtime
run_installers

log "Setup complete."
log "Installed feature bundles:$FEATURES"
