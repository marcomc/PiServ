#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
role_root="${repo_root}/ansible/roles/hermes_agent"
defaults_path="${role_root}/defaults/main.yml"
configure_path="${role_root}/tasks/configure.yml"
validate_path="${role_root}/tasks/validate-target.yml"

grep --fixed-strings --quiet \
  '/root/hermes-agent-dashboard-auth.yaml' "${defaults_path}"
grep --fixed-strings --quiet \
  '{{ hermes_agent_home }}/dashboard-basic-auth.yaml' "${defaults_path}"
grep --fixed-strings --quiet \
  "hermes_agent_dashboard_basic_auth_state.stat.pw_name == 'root'" \
  "${configure_path}"
grep --fixed-strings --quiet \
  "hermes_agent_dashboard_basic_auth_state.stat.gr_name == 'root'" \
  "${configure_path}"
grep --fixed-strings --quiet \
  'HERMES_EXISTING_DASHBOARD_PASSWORD:' "${configure_path}"
grep --fixed-strings --quiet \
  'hermes_agent_dashboard_existing_bootstrap_password.content' "${configure_path}"
grep --fixed-strings --quiet \
  'password = os.environ.get("HERMES_EXISTING_DASHBOARD_PASSWORD")' \
  "${configure_path}"
grep --fixed-strings --quiet \
  '"secret": secrets.token_urlsafe(32)' "${configure_path}"
grep --fixed-strings --quiet \
  'Remove obsolete runtime-owned Hermes dashboard authentication state' \
  "${configure_path}"
grep --fixed-strings --quiet \
  'not hermes_agent_dashboard_basic_auth_state_file.startswith(' "${validate_path}"

state_task="$({
  sed -n \
    '/^- name: Commit private Hermes dashboard authentication state$/,/^- name: Read private Hermes dashboard authentication state$/p' \
    "${configure_path}"
} | sed '$d')"
grep --fixed-strings --quiet '    owner: root' <<<"${state_task}"
grep --fixed-strings --quiet '    group: root' <<<"${state_task}"
grep --fixed-strings --quiet '    mode: "0600"' <<<"${state_task}"
