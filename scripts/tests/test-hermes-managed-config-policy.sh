#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
role_root="${repo_root}/ansible/roles/hermes_agent"
configure_path="${role_root}/tasks/configure.yml"
validate_path="${role_root}/tasks/validate-install.yml"
dashboard_template="${role_root}/templates/hermes-agent-dashboard.service.j2"
backup_template="${role_root}/templates/hermes-agent-backup.service.j2"
apple_harness="${repo_root}/scripts/verify-hermes-home-apple-home.py"
restore_harness="${repo_root}/scripts/verify-hermes-home-assistant-backup-restore.sh"
managed_bind_literal="BindReadOnlyPaths=\${managed_config}:\${hermes_home}/config.yaml"

managed_task="$({
  sed -n \
    '/^- name: Install root-controlled authoritative Hermes configuration$/,/^- name: Install Hermes runtime configuration mount point$/p' \
    "${configure_path}"
} | sed '$d')"

grep --fixed-strings --quiet \
  'dest: "{{ hermes_agent_managed_config_path }}"' <<<"${managed_task}"
grep --fixed-strings --quiet '    owner: root' <<<"${managed_task}"
grep --fixed-strings --quiet '    group: root' <<<"${managed_task}"
grep --fixed-strings --quiet '    mode: "0644"' <<<"${managed_task}"

for consumer in \
  "${dashboard_template}" \
  "${backup_template}"; do
  grep --fixed-strings --quiet \
    'BindReadOnlyPaths={{ hermes_agent_managed_config_path }}:{{ hermes_agent_home }}/config.yaml' \
    "${consumer}"
done
grep --fixed-strings --quiet -- \
  '--property=BindReadOnlyPaths={{ hermes_agent_managed_config_path' \
  "${validate_path}"
grep --fixed-strings --quiet \
  '}}:{{ hermes_agent_home }}/config.yaml' \
  "${validate_path}"

grep --fixed-strings --quiet \
  'MANAGED_CONFIG_PATH = "/usr/local/lib/hermes-agent/.hermes-config.yaml"' \
  "${apple_harness}"
grep --fixed-strings --quiet \
  'managed_config=/usr/local/lib/hermes-agent/.hermes-config.yaml' \
  "${restore_harness}"
grep --fixed-strings --quiet \
  "${managed_bind_literal}" \
  "${restore_harness}"
