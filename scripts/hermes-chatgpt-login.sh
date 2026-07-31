#!/usr/bin/env bash

set -euo pipefail

piserv_host=${PISERV_HOST:-PiServ.local}
piserv_user=${PISERV_USER:-admin}
target="${piserv_user}@${piserv_host}"

codex_env='env CODEX_HOME=/var/lib/hermes-agent/codex'
hermes_env='env HERMES_HOME=/var/lib/hermes-agent CODEX_HOME=/var/lib/hermes-agent/codex'

if ssh -o BatchMode=yes "${target}" \
  "sudo -u hermes-agent -H ${codex_env} codex login status" >/dev/null 2>&1; then
  printf 'Codex CLI is already authenticated.\n'
else
  ssh -t "${target}" \
    "sudo -u hermes-agent -H ${codex_env} codex login --device-auth"
fi

hermes_status=$(
  ssh -o BatchMode=yes "${target}" \
    "sudo -u hermes-agent -H ${hermes_env} hermes auth status openai-codex"
)

if [[ ${hermes_status} == *"logged out"* ]]; then
  printf 'Importing the Codex CLI session into Hermes...\n'
  printf 'y\n' | ssh -o BatchMode=yes "${target}" \
    "sudo -u hermes-agent -H ${hermes_env} hermes auth add openai-codex --no-browser"
else
  printf 'Hermes is already authenticated.\n'
fi

ssh -o BatchMode=yes "${target}" \
  "sudo systemctl restart hermes-agent-dashboard.service"

ssh -o BatchMode=yes "${target}" \
  "sudo -u hermes-agent -H ${codex_env} codex login status"
ssh -o BatchMode=yes "${target}" \
  "sudo -u hermes-agent -H ${hermes_env} hermes auth status openai-codex"
ssh -o BatchMode=yes "${target}" \
  "sudo -u hermes-agent -H ${hermes_env} hermes tools list --platform cli"

printf '\nDashboard tunnel:\n'
printf '  ssh -N -L 9119:127.0.0.1:9119 %s\n' "${target}"
