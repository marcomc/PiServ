#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
playbook_path="${repo_root}/ansible/playbooks/hermes-agent.yml"
handler_path="${repo_root}/ansible/roles/hermes_agent/handlers/main.yml"

policy_task="$({
  sed -n \
    '/^-\{0,1\} *- name: Install root-controlled PiServ smart-home policy source$/,/^  roles:$/p' \
    "${playbook_path}"
} || true)"
dashboard_handler="$({
  sed -n \
    '/^- name: Restart Hermes Agent dashboard$/,/^- name: Reload systemd daemon$/p' \
    "${handler_path}"
} || true)"

grep --fixed-strings --quiet \
  'notify: Restart Hermes Agent dashboard' <<<"${policy_task}"
grep --fixed-strings --quiet \
  '    - hermes_agent_manage_dashboard' <<<"${dashboard_handler}"
grep --fixed-strings --quiet \
  '    - not ansible_check_mode' <<<"${dashboard_handler}"
