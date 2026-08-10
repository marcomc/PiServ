#!/usr/bin/env bash

# Returns the SSH target, preferring the operator-supplied DHCP lease when mDNS
# is unavailable.
piserv_ssh_target() {
  local piserv_host=${PISERV_IP-PiServ.local}
  local piserv_user=${PISERV_USER:-admin}
  local formatted_host

  if [[ -n "${PISERV_IP+x}" ]]; then
    if ! formatted_host="$(python3 - "${piserv_host}" <<'PYTHON'
import ipaddress
import sys

value = sys.argv[1]
try:
    address = ipaddress.ip_address(value)
except ValueError:
    print("PISERV_IP must be an IPv4 or IPv6 literal", file=sys.stderr)
    raise SystemExit(64)

print(f"[{value}]" if address.version == 6 else value)
PYTHON
    )"; then
      return 64
    fi
  else
    formatted_host=${piserv_host}
  fi

  printf '%s@%s\n' "${piserv_user}" "${formatted_host}"
}
