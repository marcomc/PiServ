#!/usr/bin/env bash

# Validates and returns the operator-supplied DHCP lease as an IP literal.
piserv_ip_literal() {
  if [[ -z "${PISERV_IP+x}" ]]; then
    printf 'PISERV_IP must be set to an IPv4 or IPv6 literal\n' >&2
    return 64
  fi

  python3 - "${PISERV_IP}" <<'PYTHON'
import ipaddress
import sys

value = sys.argv[1]
try:
    address = ipaddress.ip_address(value)
except ValueError:
    print("PISERV_IP must be an IPv4 or IPv6 literal", file=sys.stderr)
    raise SystemExit(64)

print(value)
PYTHON
}

# Formats an already validated IP literal as an SSH target.
piserv_ssh_target_from_ip() {
  local piserv_host=$1
  local piserv_user=${PISERV_USER:-admin}

  if [[ "${piserv_host}" == *:* ]]; then
    piserv_host="[${piserv_host}]"
  fi
  printf '%s@%s\n' "${piserv_user}" "${piserv_host}"
}

# Returns the SSH target, preferring the operator-supplied DHCP lease when mDNS
# is unavailable.
piserv_ssh_target() {
  local piserv_host=PiServ.local
  local piserv_user=${PISERV_USER:-admin}

  if [[ -n "${PISERV_IP+x}" ]]; then
    if ! piserv_host="$(piserv_ip_literal)"; then
      return 64
    fi
    piserv_ssh_target_from_ip "${piserv_host}"
    return
  else
    piserv_host=PiServ.local
  fi

  printf '%s@%s\n' "${piserv_user}" "${piserv_host}"
}
