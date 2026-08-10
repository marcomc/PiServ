#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
role_root="${repo_root}/ansible/roles/hermes_agent"
defaults_path="${role_root}/defaults/main.yml"
configure_path="${role_root}/tasks/configure.yml"
validate_path="${role_root}/tasks/validate-target.yml"
credential_ancestor_path="${role_root}/tasks/validate-dashboard-credential-ancestors.yml"

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
  'Authenticate obsolete Hermes dashboard authentication state' \
  "${configure_path}"
grep --fixed-strings --quiet \
  'hermes_agent_dashboard_legacy_basic_auth_state.stat.nlink == 1' \
  "${configure_path}"
grep --fixed-strings --quiet \
  'not hermes_agent_dashboard_basic_auth_state_file.startswith(' "${validate_path}"
grep --fixed-strings --quiet \
  "hermes_agent_home ~ '/dashboard-basic-auth.yaml'" "${validate_path}"

credential_ancestor_policy="$({
  sed -n \
    '/^- name: Authenticate every existing Hermes dashboard credential ancestor$/,/^- name: Create missing private Hermes dashboard credential parent$/p' \
    "${credential_ancestor_path}"
} | sed '$d')"
grep --fixed-strings --quiet \
  'item.stat.uid | default(-1) == 0' \
  <<<"${credential_ancestor_policy}"
grep --fixed-strings --quiet \
  'item.stat.gid | default(-1) == 0' \
  <<<"${credential_ancestor_policy}"
grep --fixed-strings --quiet \
  "match('^[0-7][0-7][0145][0145]$')" <<<"${credential_ancestor_policy}"
grep --fixed-strings --quiet \
  'hermes_agent_dashboard_credential_ancestor_recheck.results[item].stat.inode ==' \
  "${credential_ancestor_path}"
grep --fixed-strings --quiet \
  'hermes_agent_dashboard_credential_recheck.stat.inode ==' \
  "${credential_ancestor_path}"

bootstrap_parent_assert_line="$(grep -n --fixed-strings \
  -- '- name: Authenticate Hermes dashboard bootstrap password ancestors' \
  "${configure_path}" | cut -d: -f1)"
bootstrap_file_inspect_line="$(grep -n --fixed-strings \
  -- '- name: Inspect Hermes dashboard bootstrap password file' \
  "${configure_path}" | cut -d: -f1)"
bootstrap_managed_state_slurp_line="$(grep -n --fixed-strings \
  -- '- name: Read Hermes dashboard bootstrap password managed state' \
  "${configure_path}" | cut -d: -f1)"
test "${bootstrap_parent_assert_line}" -lt "${bootstrap_file_inspect_line}"
test "${bootstrap_parent_assert_line}" -lt "${bootstrap_managed_state_slurp_line}"

managed_reauth_line="$(grep -n --fixed-strings \
  -- '- name: Read Hermes dashboard bootstrap password managed state' \
  "${configure_path}" | cut -d: -f1)"
managed_consume_line="$(grep -n --fixed-strings \
  -- '- name: Consume Hermes dashboard bootstrap password managed state' \
  "${configure_path}" | cut -d: -f1)"
state_reauth_line="$(grep -n --fixed-strings \
  -- '- name: Reauthenticate Hermes dashboard authentication state before reading' \
  "${configure_path}" | cut -d: -f1)"
state_slurp_line="$(grep -n --fixed-strings \
  -- '- name: Read private Hermes dashboard authentication state' \
  "${configure_path}" | cut -d: -f1)"
test "${managed_reauth_line}" -lt "${managed_consume_line}"
test "${state_reauth_line}" -lt "${state_slurp_line}"

bootstrap_reauthentication="$({
  sed -n \
    '/^- name: Reauthenticate Hermes dashboard bootstrap password before reading$/,/^- name: Read authenticated Hermes dashboard bootstrap password$/p' \
    "${configure_path}"
} | sed '$d')"
grep --fixed-strings --quiet \
  'hermes_agent_dashboard_authenticated_bootstrap_password_file.stat.isreg' \
  <<<"${bootstrap_reauthentication}"
grep --fixed-strings --quiet \
  'not hermes_agent_dashboard_authenticated_bootstrap_password_file.stat.islnk' \
  <<<"${bootstrap_reauthentication}"
grep --fixed-strings --quiet \
  "hermes_agent_dashboard_authenticated_bootstrap_password_file.stat.pw_name == 'root'" \
  <<<"${bootstrap_reauthentication}"
grep --fixed-strings --quiet \
  "hermes_agent_dashboard_authenticated_bootstrap_password_file.stat.gr_name == 'root'" \
  <<<"${bootstrap_reauthentication}"
grep --fixed-strings --quiet \
  "hermes_agent_dashboard_authenticated_bootstrap_password_file.stat.mode == '0600'" \
  <<<"${bootstrap_reauthentication}"
grep --fixed-strings --quiet \
  "hermes_agent_dashboard_bootstrap_password_managed_record.get('sha256', '')" \
  <<<"${bootstrap_reauthentication}"

bootstrap_restat_line="$(grep -n --fixed-strings \
  -- '- name: Reinspect authenticated Hermes dashboard bootstrap password' \
  "${configure_path}" | cut -d: -f1)"
bootstrap_reassert_line="$(grep -n --fixed-strings \
  -- '- name: Reauthenticate Hermes dashboard bootstrap password before reading' \
  "${configure_path}" | cut -d: -f1)"
bootstrap_ancestor_reauth_line="$(grep -n --fixed-strings \
  -- '- name: Reauthenticate Hermes dashboard bootstrap password ancestors before reading' \
  "${configure_path}" | cut -d: -f1)"
bootstrap_password_slurp_line="$(grep -n --fixed-strings \
  -- '- name: Read authenticated Hermes dashboard bootstrap password' \
  "${configure_path}" | cut -d: -f1)"
test "${bootstrap_restat_line}" -lt "${bootstrap_reassert_line}"
test "${bootstrap_reassert_line}" -lt "${bootstrap_ancestor_reauth_line}"
test "${bootstrap_ancestor_reauth_line}" -lt "${bootstrap_password_slurp_line}"

state_task="$({
  sed -n \
    '/^- name: Commit private Hermes dashboard authentication state$/,/^- name: Read private Hermes dashboard authentication state$/p' \
    "${configure_path}"
} | sed '$d')"
grep --fixed-strings --quiet '    owner: root' <<<"${state_task}"
grep --fixed-strings --quiet '    group: root' <<<"${state_task}"
grep --fixed-strings --quiet '    mode: "0600"' <<<"${state_task}"
