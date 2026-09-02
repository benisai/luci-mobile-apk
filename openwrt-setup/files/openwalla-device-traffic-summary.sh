#!/bin/sh

# Openwalla live device traffic summary for OpenWrt.
#
# This helper is intentionally one-shot: it reads conntrack byte counters and
# emits cumulative per-device upload/download totals as JSON. The app polls this
# script and calculates live speed from byte deltas, keeping router load low.
#
# Core approach adapted from luci-app-trafficctl's Apache-2.0 licensed
# conntrack counter method:
# https://github.com/YusDyr/luci-app-trafficctl

PATH="/usr/sbin:/usr/bin:/sbin:/bin"
export PATH

conntrack_source() {
	if [ -r /proc/net/nf_conntrack ]; then
		cat /proc/net/nf_conntrack
		return 0
	fi
	if [ -r /proc/net/ip_conntrack ]; then
		cat /proc/net/ip_conntrack
		return 0
	fi
	if command -v conntrack >/dev/null 2>&1; then
		conntrack -L 2>/dev/null
		return 0
	fi
	return 1
}

default_wan_dev() {
	ip -4 route show default 2>/dev/null | awk '
	{
		for (i = 1; i <= NF; i++) {
			if ($i == "dev" && (i + 1) <= NF) {
				print $(i + 1)
				exit
			}
		}
	}'
}

configured_wan_devs() {
	configured="$(
		{
			uci -q get network.wan.device 2>/dev/null
			uci -q get network.wan.ifname 2>/dev/null
		} | tr ' ' '\n' | awk 'NF && !seen[$1]++'
	)"
	if [ -n "$configured" ]; then
		printf "%s\n" "$configured"
		return 0
	fi
	{
		default_wan_dev
	} | tr ' ' '\n' | awk 'NF && !seen[$1]++'
}

local_ipv4_addresses() {
	ip -4 addr show 2>/dev/null | awk '/inet /{split($2,a,"/"); print a[1]}'
}

monitored_subnets() {
	wan_devs="$(configured_wan_devs | tr '\n' ' ')"
	ip -4 route show scope link 2>/dev/null | awk -v wan="$wan_devs" '
	function is_private_net(net) {
		return (net ~ /^10\./ || net ~ /^192\.168\./ || net ~ /^172\.(1[6-9]|2[0-9]|3[0-1])\./)
	}
	function is_wan(dev, parts, n, i) {
		n = split(wan, parts, " ")
		for (i = 1; i <= n; i++)
			if (parts[i] != "" && parts[i] == dev) return 1
		return 0
	}
	{
		net = $1
		dev = ""
		for (i = 1; i <= NF; i++) {
			if ($i == "dev" && (i + 1) <= NF) {
				dev = $(i + 1)
				break
			}
		}
		if (dev == "" || is_wan(dev)) next
		if (net !~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\/[0-9]+$/) next
		if (!is_private_net(net)) next
		if (!seen[net]++) print net
	}'
}

subnet_spec="$(monitored_subnets | awk -F'[./]' '
function pow2(n, r) {
	r = 1
	while (n-- > 0) r *= 2
	return r
}
NF == 5 {
	prefix = $5 + 0
	if (prefix < 0 || prefix > 32) next
	ip = ($1 * 16777216) + ($2 * 65536) + ($3 * 256) + $4
	block = pow2(32 - prefix)
	base = ip - (ip % block)
	printf "%s%s:%s", (NR > 1 ? " " : ""), base, block
}')"

local_ips="$(local_ipv4_addresses | tr '\n' ' ')"

[ -z "$subnet_spec" ] && { echo '[]'; exit 0; }

conntrack_source | awk -v spec="$subnet_spec" -v localips="$local_ips" '
function ip2int(ip, a) {
	split(ip, a, ".")
	return a[1] * 16777216 + a[2] * 65536 + a[3] * 256 + a[4]
}

function is_ipv4(ip) {
	return ip ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/
}

function subnet_idx(ip, si, k) {
	if (!is_ipv4(ip)) return 0
	si = ip2int(ip)
	for (k = 1; k <= subnet_count; k++) {
		if (si - (si % block[k]) == base[k]) return k
	}
	return 0
}

function add_flow(ip, upload_bytes, download_bytes) {
	if (ip == "" || ip in local) return
	seen[ip] = 1
	tx[ip] += upload_bytes + 0
	rx[ip] += download_bytes + 0
}

BEGIN {
	subnet_count = split(spec, parts, " ")
	for (k = 1; k <= subnet_count; k++) {
		split(parts[k], kv, ":")
		base[k] = kv[1] + 0
		block[k] = kv[2] + 0
	}
	local_count = split(localips, lp, " ")
	for (k = 1; k <= local_count; k++) {
		if (lp[k] != "") local[lp[k]] = 1
	}
}

{
	delete src
	delete dst
	delete bytes
	src_count = 0
	dst_count = 0
	byte_count = 0

	for (i = 1; i <= NF; i++) {
		if (index($i, "src=") == 1) {
			src_count++
			src[src_count] = substr($i, 5)
		} else if (index($i, "dst=") == 1) {
			dst_count++
			dst[dst_count] = substr($i, 5)
		} else if (index($i, "bytes=") == 1) {
			byte_count++
			bytes[byte_count] = substr($i, 7) + 0
		}
	}

	client = ""
	if (src_count >= 1 && subnet_idx(src[1]) > 0) {
		client = src[1]
	} else if (src_count >= 2 && dst_count >= 2 && subnet_idx(dst[2]) > 0) {
		client = dst[2]
	} else if (src_count >= 1 && dst_count >= 2 && src[1] != dst[2] && is_ipv4(src[1]) && !(src[1] in local)) {
		client = src[1]
	}

	if (client == "" || client in local) next

	upload = (byte_count >= 1 ? bytes[1] : 0)
	download = 0
	if (src_count >= 2 && dst_count >= 2 && byte_count >= 2 && dst[2] == client) {
		download = bytes[2]
	}

	add_flow(client, upload, download)
}

END {
	for (ip in seen) {
		printf "%s\t%.0f\t%.0f\n", ip, rx[ip] + 0, tx[ip] + 0
	}
}
' | awk '
BEGIN {
	while ((getline line < "/tmp/dhcp.leases") > 0) {
		n = split(line, f, /[ \t]+/)
		if (n >= 4 && f[2] ~ /^([0-9a-fA-F][0-9a-fA-F]:){5}[0-9a-fA-F][0-9a-fA-F]$/)
			mac[tolower(f[3])] = tolower(f[2])
	}

	while ((getline line < "/proc/net/arp") > 0) {
		if (line ~ /^IP/) continue
		n = split(line, f, /[ \t]+/)
		if (n >= 4 && f[4] ~ /^([0-9a-fA-F][0-9a-fA-F]:){5}[0-9a-fA-F][0-9a-fA-F]$/)
			mac[tolower(f[1])] = tolower(f[4])
	}

	cmd = "ip neigh 2>/dev/null"
	while ((cmd | getline line) > 0) {
		n = split(line, f, /[ \t]+/)
		ip = f[1]
		for (i = 2; i <= n; i++) {
			if (f[i] == "lladdr" && (i + 1) <= n && f[i + 1] ~ /^([0-9a-fA-F][0-9a-fA-F]:){5}[0-9a-fA-F][0-9a-fA-F]$/)
				mac[tolower(ip)] = tolower(f[i + 1])
		}
	}
	close(cmd)

	printf "["
	first = 1
}

{
	ip = $1
	rx = $2 + 0
	tx = $3 + 0
	m = mac[tolower(ip)]
	if (!first) printf ","
	first = 0
	printf "{\"ip\":\"%s\",\"mac\":\"%s\",\"rx_bytes\":%.0f,\"tx_bytes\":%.0f}", ip, m, rx, tx
}

END {
	printf "]\n"
}
'
