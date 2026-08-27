#!/bin/sh

# Openwalla internet blocking helper for OpenWrt.
# Creates, updates, lists, and removes firewall rules used for device-level
# internet pause/block actions from the mobile app.

PREFIX="openwalla_time_"

now() {
	date +%s
}

is_number() {
	case "$1" in
	''|*[!0-9]*) return 1 ;;
	*) return 0 ;;
	esac
}

is_paternal_firewall_section() {
	section="$1"
	name="$(uci -q get "firewall.$section.name" 2>/dev/null || true)"
	[ -n "$name" ] || return 1
	case "$name" in
	"$PREFIX"*) return 0 ;;
	*) return 1 ;;
	esac
}

delete_pause_for_section() {
	target="$1"
	while :; do
		pause_section="$(uci show openwalla 2>/dev/null | awk -F'[.=]' -v target="$target" '
			$1 == "openwalla" && $3 == "target_section" {
				value = $0
				sub(/^[^=]*=/, "", value)
				gsub(/^'\''|'\''$/, "", value)
				if (value == target) {
					print $2
					exit
				}
			}
		')"
		[ -n "$pause_section" ] || break
		uci -q delete "openwalla.$pause_section" 2>/dev/null || true
	done
}

reload_firewall() {
	/etc/init.d/firewall reload >/dev/null 2>&1 || /etc/init.d/firewall restart >/dev/null 2>&1 || true
}

pause_rules() {
	minutes="$1"
	shift
	if ! is_number "$minutes" || [ "$minutes" -lt 1 ]; then
		echo "invalid pause minutes" >&2
		return 1
	fi
	if [ "$#" -lt 1 ]; then
		echo "no firewall sections supplied" >&2
		return 1
	fi

	resume_at=$(( $(now) + (minutes * 60) ))
	changed=0
	for section in "$@"; do
		is_paternal_firewall_section "$section" || continue
		delete_pause_for_section "$section"
		uci set "firewall.$section.enabled=0"
		pause_section="$(uci add openwalla paternal_pause)"
		uci set "openwalla.$pause_section.target_section=$section"
		uci set "openwalla.$pause_section.rule_name=$(uci -q get "firewall.$section.name" 2>/dev/null || echo "$section")"
		uci set "openwalla.$pause_section.resume_at=$resume_at"
		changed=1
	done

	if [ "$changed" = "1" ]; then
		uci commit firewall
		uci commit openwalla
		reload_firewall
	else
		echo "no valid paternal firewall sections supplied" >&2
		return 1
	fi
}

clear_pauses() {
	changed=0
	for section in "$@"; do
		delete_pause_for_section "$section"
		changed=1
	done
	if [ "$changed" = "1" ]; then
		uci commit openwalla
	fi
}

apply_pauses() {
	current="$(now)"
	firewall_changed=0
	openwalla_changed=0
	for pause_section in $(uci show openwalla 2>/dev/null | sed -n 's/^openwalla\.\([^.=]*\)=paternal_pause$/\1/p'); do
		target="$(uci -q get "openwalla.$pause_section.target_section" 2>/dev/null || true)"
		resume_at="$(uci -q get "openwalla.$pause_section.resume_at" 2>/dev/null || echo 0)"
		is_number "$resume_at" || resume_at=0
		[ "$resume_at" -le "$current" ] || continue

		if [ -n "$target" ] && is_paternal_firewall_section "$target"; then
			uci set "firewall.$target.enabled=1"
			firewall_changed=1
		fi
		uci -q delete "openwalla.$pause_section" 2>/dev/null || true
		openwalla_changed=1
	done

	if [ "$firewall_changed" = "1" ]; then
		uci commit firewall
		reload_firewall
	fi
	if [ "$openwalla_changed" = "1" ]; then
		uci commit openwalla
	fi
}

case "$1" in
pause)
	shift
	pause_rules "$@"
	;;
clear)
	shift
	clear_pauses "$@"
	;;
apply|--apply)
	apply_pauses
	;;
*)
	echo "usage: $0 {pause MINUTES SECTION...|clear SECTION...|apply}" >&2
	exit 1
	;;
esac
