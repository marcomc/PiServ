#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
playbook_path="${repo_root}/ansible/playbooks/hermes-agent.yml"
handler_path="${repo_root}/ansible/roles/hermes_agent/handlers/main.yml"
parent_chain_test_path="${repo_root}/ansible/tests/test-hermes-policy-parent-chain.yml"

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
  'not ansible_check_mode or' <<<"${policy_task}"
grep --fixed-strings --quiet \
  'piserv_hermes_policy_directory_postcreate.stat.exists' <<<"${policy_task}"
grep --fixed-strings --quiet \
  '    - hermes_agent_manage_dashboard' <<<"${dashboard_handler}"
grep --fixed-strings --quiet \
  '    - not ansible_check_mode' <<<"${dashboard_handler}"

catalog_line="$(grep -n 'import_tasks: validate-tool-catalog.yml' "${repo_root}/ansible/roles/hermes_agent/tasks/configure.yml" | cut -d: -f1)"
startup_line="$(grep -n 'state: started' "${repo_root}/ansible/roles/hermes_agent/tasks/configure.yml" | head -1 | cut -d: -f1)"
test "${catalog_line}" -lt "${startup_line}"
if grep --fixed-strings --quiet \
  'Read enabled Hermes CLI toolsets' \
  "${repo_root}/ansible/roles/hermes_agent/tasks/validate-install.yml"; then
  exit 1
fi

ansible-playbook \
  --inventory localhost, \
  --connection local \
  "${parent_chain_test_path}"
