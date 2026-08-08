#!/usr/bin/env bash

# Returns the SSH target, preferring the operator-supplied DHCP lease when mDNS
# is unavailable.
piserv_ssh_target() {
  local piserv_host=${PISERV_IP:-PiServ.local}
  local piserv_user=${PISERV_USER:-admin}

  printf '%s@%s\n' "${piserv_user}" "${piserv_host}"
}
