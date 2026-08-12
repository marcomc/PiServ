#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
role_root="${repo_root}/ansible/roles/hermes_agent"
render_path="${role_root}/tasks/dashboard-auth-render.yml"
validate_path="${role_root}/tasks/validate-install.yml"
catalog_validate_path="${role_root}/tasks/validate-tool-catalog.yml"
dashboard_template="${role_root}/templates/hermes-agent-dashboard.service.j2"
backup_template="${role_root}/templates/hermes-agent-backup.service.j2"
apple_harness="${repo_root}/scripts/verify-hermes-home-apple-home.py"
restore_harness="${repo_root}/scripts/verify-hermes-home-assistant-backup-restore.sh"
managed_bind_literal="BindReadOnlyPaths=\${config_artifact}:\${hermes_home}/config.yaml"

managed_task="$({
  sed -n \
    '/^- name: Install root-controlled authoritative Hermes configuration$/,/^- name: Install Hermes runtime configuration mount point$/p' \
    "${render_path}"
} | sed '$d')"

grep --fixed-strings --quiet \
  'dest: "{{ hermes_agent_managed_config_path }}"' <<<"${managed_task}"
grep --fixed-strings --quiet '    owner: root' <<<"${managed_task}"
grep --fixed-strings --quiet '    group: "{{ hermes_agent_group }}"' <<<"${managed_task}"
grep --fixed-strings --quiet '    mode: "0640"' <<<"${managed_task}"
grep --fixed-strings --quiet '  no_log: true' <<<"${managed_task}"

runtime_task="$({
  sed -n \
    '/^- name: Install Hermes runtime configuration mount point$/,/^- name: Inspect Hermes environment file$/p' \
    "${render_path}"
} | sed '$d')"
grep --fixed-strings --quiet '    mode: "0600"' <<<"${runtime_task}"
grep --fixed-strings --quiet '  no_log: true' <<<"${runtime_task}"

for assertion in \
  'hermes_agent_managed_config_state.stat.isreg' \
  'not hermes_agent_managed_config_state.stat.islnk' \
  "hermes_agent_managed_config_state.stat.pw_name == 'root'" \
  'hermes_agent_managed_config_state.stat.gr_name == hermes_agent_group' \
  "hermes_agent_managed_config_state.stat.mode == '0640'"; do
  grep --fixed-strings --quiet "${assertion}" "${validate_path}"
done

for consumer in \
  "${dashboard_template}" \
  "${backup_template}"; do
  grep --fixed-strings --quiet 'User={{ hermes_agent_user }}' "${consumer}"
  grep --fixed-strings --quiet 'Group={{ hermes_agent_group }}' "${consumer}"
  grep --fixed-strings --quiet \
    'BindReadOnlyPaths={{ hermes_agent_managed_config_path }}:{{ hermes_agent_home }}/config.yaml' \
    "${consumer}"
done
grep --fixed-strings --quiet '"--uid={{ hermes_agent_user }}"' "${catalog_validate_path}"
grep --fixed-strings --quiet '"--gid={{ hermes_agent_group }}"' "${catalog_validate_path}"
grep --fixed-strings --quiet -- \
  '--property=BindReadOnlyPaths={{ hermes_agent_managed_config_path' \
  "${catalog_validate_path}"
grep --fixed-strings --quiet \
  '}}:{{ hermes_agent_home }}/config.yaml' \
  "${catalog_validate_path}"

grep --fixed-strings --quiet \
  'MANAGED_CONFIG_PATH = "/usr/local/lib/hermes-agent/.hermes-config.yaml"' \
  "${apple_harness}"
grep --fixed-strings --quiet \
  'managed_config=/usr/local/lib/hermes-agent/.hermes-config.yaml' \
  "${restore_harness}"
grep --fixed-strings --quiet \
  "${managed_bind_literal}" \
  "${restore_harness}"
