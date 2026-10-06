#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo 'init-firewall: must run as root.' >&2
  exit 1
fi

strict_dns="${STRICT_DNS:-0}"
if [[ "$strict_dns" != 0 && "$strict_dns" != 1 ]]; then
  echo 'init-firewall: STRICT_DNS must be 0 or 1.' >&2
  exit 1
fi

allowed_set=agentbox-allowed
allowlist=/etc/agent-box/allowed-domains.txt

valid_ipv4() {
  local address="$1" octet
  local -a octets
  [[ "$address" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
  IFS=. read -r -a octets <<< "$address"
  for octet in "${octets[@]}"; do
    (( 10#$octet <= 255 )) || return 1
  done
}

# Install the deny policy before flushing so refreshes never open outbound traffic.
iptables -w -P OUTPUT DROP
iptables -w -F OUTPUT
if command -v ip6tables >/dev/null 2>&1; then
  # A present but failing IPv6 firewall is an error, not a reason to allow IPv6.
  ip6tables -w -P OUTPUT DROP
  ip6tables -w -F OUTPUT
else
  echo 'init-firewall: ip6tables unavailable; IPv6 OUTPUT policy could not be set.' >&2
fi

ipset create "$allowed_set" hash:net -exist
ipset flush "$allowed_set"

# Strict DNS must precede loopback and established rules, including on refresh.
for protocol in udp tcp; do
  if [[ "$strict_dns" == 1 ]]; then
    iptables -w -A OUTPUT -p "$protocol" -d 127.0.0.11 --dport 53 -j ACCEPT
    iptables -w -A OUTPUT -p "$protocol" --dport 53 -j DROP
  else
    iptables -w -A OUTPUT -p "$protocol" --dport 53 -j ACCEPT
  fi
done
iptables -w -A OUTPUT -o lo -j ACCEPT
iptables -w -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

while IFS= read -r line || [[ -n "$line" ]]; do
  # Accept whitespace, CRLF files and inline comments without passing them to dig.
  domain="${line%%#*}"
  domain="${domain//[[:space:]]/}"
  [[ -n "$domain" ]] || continue
  if [[ ! "$domain" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?\.?$ ]]; then
    echo "init-firewall: invalid domain: $domain" >&2
    exit 1
  fi

  addresses="$(dig +short +time=2 +tries=1 "$domain" A)" || addresses=''
  resolved=0
  while IFS= read -r address; do
    # dig may also return CNAMEs; only resolved IPv4 addresses belong in the set.
    if valid_ipv4 "$address"; then
      ipset add "$allowed_set" "$address" -exist
      resolved=1
    fi
  done <<< "$addresses"
  if [[ "$resolved" == 0 ]]; then
    echo "init-firewall: warning: no IPv4 addresses for $domain" >&2
  fi
done < "$allowlist"

iptables -w -A OUTPUT -m set --match-set "$allowed_set" dst -j ACCEPT

if [[ -n "${EXTRA_ALLOWED_CIDRS:-}" ]]; then
  # Validate before handing values to iptables; malformed service subnets fail closed.
  IFS=, read -r -a extra_cidrs <<< "$EXTRA_ALLOWED_CIDRS"
  for cidr in "${extra_cidrs[@]}"; do
    cidr="${cidr//[[:space:]]/}"
    address="${cidr%/*}"
    prefix="${cidr##*/}"
    if [[ "$cidr" != */* ]] || ! valid_ipv4 "$address" ||
       [[ ! "$prefix" =~ ^[0-9]{1,2}$ ]] || (( 10#$prefix > 32 )); then
      echo "init-firewall: invalid IPv4 CIDR: $cidr" >&2
      exit 1
    fi
    iptables -w -A OUTPUT -d "$cidr" -j ACCEPT
  done
fi

# Ignore proxy environment variables so this probes the blocked destination itself.
# HTTP error responses still prove connectivity, so deliberately do not use --fail.
if curl --noproxy '*' --silent --output /dev/null --connect-timeout 5 --max-time 5 https://example.com; then
  echo 'FIREWALL FAIL: https://example.com is reachable.' >&2
  exit 1
fi

echo 'Firewall OK'
