#!/usr/bin/env bash
# Verify the source-level contract for the PiServ Hermes MCP SSH entry point.
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repository_root=$(cd -- "${script_dir}/../.." && pwd)
task_file="${repository_root}/ansible/tasks/hermes-mcp-ssh.yml"
provenance_task_file="${repository_root}/ansible/tasks/hermes-mcp-ssh-provenance.yml"
wrapper_template="${repository_root}/ansible/playbooks/templates/hermes-mcp-ssh-wrapper.sh.j2"
sudoers_template="${repository_root}/ansible/playbooks/templates/hermes-mcp-ssh-sudoers.j2"
keys_template="${repository_root}/ansible/playbooks/templates/hermes-mcp-ssh-authorized_keys.j2"
state_template="${repository_root}/ansible/playbooks/templates/hermes-mcp-ssh-state.json.j2"
playbook="${repository_root}/ansible/playbooks/hermes-agent.yml"
runbook="${repository_root}/docs/runbooks/hermes-mcp-ssh.md"
variables_example="${repository_root}/ansible/vars/hermes-agent.yml.example"
group_variables="${repository_root}/ansible/group_vars/piserv.yml"

require_text() {
  local expected=$1
  local file_path=$2

  if ! rg --fixed-strings --quiet -- "${expected}" "${file_path}"; then
    printf 'Missing required policy text in %s: %s\n' "${file_path}" \
      "${expected}" >&2
    exit 1
  fi
}

require_multiline_text() {
  local expected=$1
  local file_path=$2

  if ! rg --multiline --fixed-strings --quiet -- "${expected}" "${file_path}"; then
    printf 'Missing required multiline policy text in %s:\n%s\n' "${file_path}" \
      "${expected}" >&2
    exit 1
  fi
}

require_text 'password_lock: true' "${task_file}"
require_text 'piserv_hermes_mcp_ssh_manage: true' "${variables_example}"
require_text 'piserv_hermes_mcp_ssh_copy_admin_authorized_keys: true' \
  "${variables_example}"
require_text 'piserv_hermes_mcp_ssh_manage: true' "${group_variables}"
require_text 'piserv_hermes_mcp_ssh_copy_admin_authorized_keys: true' \
  "${group_variables}"
require_text 'shell: /bin/sh' "${task_file}"
require_text 'force: false' "${task_file}"
require_text "piserv_hermes_mcp_ssh_home ~ '/.ssh/authorized_keys'" "${task_file}"
require_text 'Normalize Hermes runtime identity records' "${task_file}"
require_text 'Classify a fresh check-mode Hermes runtime identity simulation' "${task_file}"
require_text 'Provision Hermes MCP SSH lifecycle provenance before account mutation' \
  "${task_file}"
require_text 'Normalize existing Hermes MCP SSH identity records' "${task_file}"
require_text '((ansible_facts.getent_passwd | default({}, true)).get(piserv_hermes_mcp_ssh_user, []) | default([], true))' "${task_file}"
require_text '((ansible_facts.getent_group | default({}, true)).get(piserv_hermes_mcp_ssh_group, []) | default([], true))' "${task_file}"
require_text 'Classify an absent Hermes MCP SSH account identity' "${task_file}"
require_text 'Validate Hermes MCP SSH lifecycle provenance before adoption' "${task_file}"
require_text 'hermes-mcp-ssh-provenance.yml' "${task_file}"
require_text 'Classify an authenticated group-only provisioning resume' "${provenance_task_file}"
require_multiline_text "piserv_hermes_mcp_ssh_account_passwd_record | length == 0 and
      piserv_hermes_mcp_ssh_account_group_record | length == 3 and
      piserv_hermes_mcp_ssh_account_group_record[1] != '0' and
      piserv_hermes_mcp_ssh_account_group_record[2] == '' and
      (piserv_hermes_mcp_ssh_lifecycle_state | default({}, true)).phase | default('') ==
      'provisioning' and
      piserv_hermes_mcp_ssh_account_path_state.results |
      selectattr('stat.exists') | list | length == 0" "${provenance_task_file}"
require_multiline_text "piserv_hermes_mcp_ssh_account_identity_is_absent or
        piserv_hermes_mcp_ssh_account_group_only_provisioning_resume or
        (piserv_hermes_mcp_ssh_account_passwd_record | length == 6 and
        piserv_hermes_mcp_ssh_account_group_record | length == 3)" "${provenance_task_file}"
require_text 'Require complete Hermes runtime identity records' "${task_file}"
require_text "piserv_hermes_mcp_ssh_account_passwd_record[5] == '/bin/sh'" \
  "${task_file}"
require_text 'Define the Hermes MCP SSH lifecycle state path' "${task_file}"
require_text 'Inspect existing privileged Hermes MCP SSH artifacts before mutation' \
  "${task_file}"
require_text 'Authenticate existing privileged Hermes MCP SSH artifacts' \
  "${task_file}"
require_text 'Require lifecycle provenance before adopting Hermes MCP SSH state' \
  "${provenance_task_file}"
require_text 'Require managed markers before replacing Hermes MCP SSH artifacts' \
  "${task_file}"
require_text 'Provision Hermes MCP SSH lifecycle provenance before account mutation' \
  "${task_file}"
require_multiline_text '- name: Provision Hermes MCP SSH lifecycle provenance before account mutation
  ansible.builtin.template:
    src: "{{ playbook_dir }}/templates/hermes-mcp-ssh-state.json.j2"
    dest: "{{ piserv_hermes_mcp_ssh_state_path }}"
    owner: root
    group: root
    mode: "0600"
  when: >-
    not ansible_check_mode or
    (piserv_hermes_mcp_ssh_publication_parent_state.results |
    selectattr('\''item.path'\'', '\''equalto'\'', piserv_hermes_mcp_ssh_wrapper_path | dirname) |
    map(attribute='\''stat.exists'\'') | first)' "${task_file}"
require_text 'Mark Hermes MCP SSH lifecycle provenance active after sudoers publication' \
  "${task_file}"
require_text 'Publish active Hermes MCP SSH lifecycle provenance' \
  "${task_file}"
require_multiline_text '- name: Publish active Hermes MCP SSH lifecycle provenance
  ansible.builtin.template:
    src: "{{ playbook_dir }}/templates/hermes-mcp-ssh-state.json.j2"
    dest: "{{ piserv_hermes_mcp_ssh_state_path }}"
    owner: root
    group: root
    mode: "0600"
  when: >-
    not ansible_check_mode or
    (piserv_hermes_mcp_ssh_publication_parent_state.results |
    selectattr('\''item.path'\'', '\''equalto'\'', piserv_hermes_mcp_ssh_wrapper_path | dirname) |
    map(attribute='\''stat.exists'\'') | first)' "${task_file}"
require_text 'Exercise provisioning lifecycle publication guard on a fresh host' \
  "${repository_root}/ansible/tests/test-hermes-mcp-ssh-templates.yml"
require_text 'hermes_mcp_ssh_fresh_provisioning_state_publication is skipped' \
  "${repository_root}/ansible/tests/test-hermes-mcp-ssh-templates.yml"
require_text 'Exercise active lifecycle publication guard on a fresh host' \
  "${repository_root}/ansible/tests/test-hermes-mcp-ssh-templates.yml"
require_text 'hermes_mcp_ssh_fresh_active_state_publication is skipped' \
  "${repository_root}/ansible/tests/test-hermes-mcp-ssh-templates.yml"
require_text 'Exercise the production provenance gate for a group-only resume' \
  "${repository_root}/ansible/tests/test-hermes-mcp-ssh-templates.yml"
require_text 'Verify the active group-only fixture failed provenance validation' \
  "${repository_root}/ansible/tests/test-hermes-mcp-ssh-templates.yml"
require_text 'Verify the absent group-only fixture failed provenance validation' \
  "${repository_root}/ansible/tests/test-hermes-mcp-ssh-templates.yml"
require_text 'Reject administrator keys that already declare a forced command' \
  "${task_file}"
require_text 'Require plain administrator public keys for automatic MCP SSH access' \
  "${task_file}"
require_text 'mode: "0600"' "${task_file}"
require_text 'mode: "0440"' "${task_file}"
require_text 'validate: /usr/sbin/visudo -cf %s' "${task_file}"
require_text 'Inspect every Hermes MCP SSH wrapper ancestor before mutation' \
  "${task_file}"
require_text 'Authenticate every Hermes MCP SSH wrapper ancestor before mutation' \
  "${task_file}"
require_multiline_text "((item.item.policy | default('safe-system-directory')) == 'managed-wrapper-directory' and
        item.stat.mode == '0755')" "${task_file}"
require_text 'Canonicalize every existing Hermes MCP SSH wrapper ancestor before mutation' \
  "${task_file}"
require_text 'Require exact canonical Hermes MCP SSH wrapper ancestors before mutation' \
  "${task_file}"
require_multiline_text '    - path: /
      required: true
      mode: "0755"
    - path: /usr
      required: true
      mode: "0755"
    - path: /usr/local
      required: true
      mode: "0755"' "${task_file}"
require_multiline_text '    - path: /etc
      required: true
      mode: "0755"
      create_if_absent: false
      policy: safe-system-directory
    - path: /etc/ssh
      required: true
      mode: "0755"
      create_if_absent: false
      policy: safe-system-directory' "${task_file}"
require_multiline_text '    - path: /usr/local/libexec
      required: false
      mode: "0755"
      create_if_absent: true
      policy: managed-wrapper-directory
    - path: "{{ piserv_hermes_mcp_ssh_wrapper_path | dirname }}"
      required: false
      mode: "0755"' "${task_file}"
require_text 'Authenticate the Hermes MCP SSH ancestor canonicalization executable' \
  "${task_file}"
require_text 'Inspect the Hermes MCP runtime launch prerequisites' "${task_file}"
require_text 'Install SSH forced-command policy before publishing MCP keys' \
  "${task_file}"
require_text 'Discover SSH configuration drop-ins before the Hermes MCP policy' \
  "${task_file}"
require_text 'Define SSH configuration files before the Hermes MCP policy' \
  "${task_file}"
require_text 'Reject symlinked SSH configuration drop-ins before the Hermes MCP policy' \
  "${task_file}"
require_text 'Inspect consumed SSH configuration leaves before the Hermes MCP policy' \
  "${task_file}"
require_text 'Authenticate consumed SSH configuration leaves before the Hermes MCP policy' \
  "${task_file}"
require_text 'Read authenticated SSH configuration before the Hermes MCP policy' \
  "${task_file}"
require_text 'Reinspect consumed SSH configuration leaves after reading policy' \
  "${task_file}"
require_text 'Require consumed SSH configuration leaves to retain their authenticated inode' \
  "${task_file}"
require_text 'Reject scoped SSH Match policy and unverified Includes before the Hermes MCP policy' \
  "${task_file}"
require_text "selectattr('path', 'lt', '/etc/ssh/sshd_config.d/60-codex-hermes-mcp.conf')" \
  "${task_file}"
require_text "'(?im)^\\\\s*Match\\\\s+(?!all\\\\s*(?:#.*)?$)'" \
  "${task_file}"
require_text "item.content | b64decode is not search('(?im)^\\\\s*Include\\\\s+')" \
  "${task_file}"
require_text "'(?im)^\\\\s*Include\\\\s+(?!/etc/ssh/sshd_config\\\\.d/\\\\*\\\\.conf\\\\s*(?:#.*)?$)'" \
  "${task_file}"
require_text "map(attribute='stat.inode') | first" "${task_file}"
require_text "map(attribute='stat.dev') | first" "${task_file}"
ssh_configuration_audit_tasks=$(sed -n \
  '/^- name: Reject symlinked SSH configuration drop-ins before the Hermes MCP policy$/,/^- name: Install SSH forced-command policy before publishing MCP keys$/p' \
  "${task_file}")
if rg --fixed-strings --quiet -- 'when: not ansible_check_mode' <<<"${ssh_configuration_audit_tasks}"; then
  printf 'Hermes MCP SSH configuration-leaf audit must run during converged check mode.\n' >&2
  exit 1
fi
require_text 'Validate the complete SSH daemon configuration before publishing MCP keys' \
  "${task_file}"
require_text 'Reload SSH service to activate forced-command policy before publishing MCP keys' \
  "${task_file}"
require_text 'Read the effective Hermes MCP SSH forced-command policy before publishing MCP keys' \
  "${task_file}"
require_text 'Require the effective Hermes MCP SSH forced-command policy before publishing MCP keys' \
  "${task_file}"
require_text '      - /usr/sbin/sshd' "${task_file}"
require_text '      - -T' "${task_file}"
require_text '      - -C' "${task_file}"
require_text 'user={{ piserv_hermes_mcp_ssh_user }},addr=127.0.0.1,host=localhost' \
  "${task_file}"
require_text "'forcecommand /usr/bin/sudo -n ' ~ piserv_hermes_mcp_ssh_wrapper_path" \
  "${task_file}"
require_text "'disableforwarding yes' in piserv_hermes_mcp_ssh_effective_policy.stdout_lines" \
  "${task_file}"
require_text "'permittty no' in piserv_hermes_mcp_ssh_effective_policy.stdout_lines" \
  "${task_file}"
require_text "'permituserrc no' in piserv_hermes_mcp_ssh_effective_policy.stdout_lines" \
  "${task_file}"
require_text "'x11forwarding no' in piserv_hermes_mcp_ssh_effective_policy.stdout_lines" \
  "${task_file}"
require_text 'Inspect the Hermes MCP SSH user RC hook before mutation' "${task_file}"
require_text 'Reject an existing Hermes MCP SSH user RC hook' "${task_file}"
require_text 'PermitUserRC no' "${repository_root}/ansible/playbooks/templates/hermes-mcp-ssh-sshd.conf.j2"
require_multiline_text '- name: Reload SSH service to activate forced-command policy before publishing MCP keys
  ansible.builtin.systemd_service:
    name: ssh
    state: reloaded' "${task_file}"
require_multiline_text 'piserv_hermes_mcp_ssh_runtime_identity_is_fresh_check_mode or
        (piserv_hermes_mcp_ssh_runtime_passwd_record | length == 6 and
        piserv_hermes_mcp_ssh_runtime_passwd_record[1] != '\''0'\'')' "${task_file}"
require_multiline_text 'piserv_hermes_mcp_ssh_runtime_identity_is_fresh_check_mode or
        (piserv_hermes_mcp_ssh_runtime_group_record | length == 3 and
        piserv_hermes_mcp_ssh_runtime_group_record[1] != '\''0'\'')' "${task_file}"
runtime_identity_tasks=$(sed -n \
  '/^- name: Require complete Hermes runtime identity records$/,/^- name: Read existing Hermes MCP SSH account and group$/p' \
  "${task_file}")
if rg --fixed-strings --quiet -- 'ansible_check_mode or' <<<"${runtime_identity_tasks}"; then
  printf 'Converged Hermes runtime identities must not bypass validation in check mode.\n' >&2
  exit 1
fi
require_text "piserv_hermes_mcp_ssh_account_passwd_record[1] != '0'" \
  "${task_file}"
require_text "piserv_hermes_mcp_ssh_account_group_record[1] != '0'" \
  "${task_file}"
require_text 'when: not ansible_check_mode' "${task_file}"
provision_line=$(rg -n --fixed-strings 'Provision Hermes MCP SSH lifecycle provenance before account mutation' "${task_file}" | cut -d: -f1)
wrapper_ancestor_auth_line=$(rg -n --fixed-strings 'Authenticate every Hermes MCP SSH wrapper ancestor before mutation' "${task_file}" | cut -d: -f1)
wrapper_ancestor_realpath_line=$(rg -n --fixed-strings 'Authenticate the Hermes MCP SSH ancestor canonicalization executable' "${task_file}" | cut -d: -f1)
wrapper_ancestor_canonical_command_line=$(rg -n --fixed-strings 'Canonicalize every existing Hermes MCP SSH wrapper ancestor before mutation' "${task_file}" | cut -d: -f1)
wrapper_ancestor_canonical_line=$(rg -n --fixed-strings 'Require exact canonical Hermes MCP SSH wrapper ancestors before mutation' "${task_file}" | cut -d: -f1)
libexec_directory_line=$(rg -n --fixed-strings 'Create the Hermes MCP SSH libexec parent directory' "${task_file}" | cut -d: -f1)
wrapper_directory_line=$(rg -n --fixed-strings 'Create the dedicated Hermes MCP SSH wrapper directory' "${task_file}" | cut -d: -f1)
user_create_line=$(rg -n --fixed-strings 'Create password-locked Hermes MCP SSH system user' "${task_file}" | cut -d: -f1)
ssh_policy_line=$(rg -n --fixed-strings 'Install SSH forced-command policy before publishing MCP keys' "${task_file}" | cut -d: -f1)
ssh_context_discover_line=$(rg -n --fixed-strings 'Discover SSH configuration drop-ins before the Hermes MCP policy' "${task_file}" | cut -d: -f1)
ssh_context_symlink_reject_line=$(rg -n --fixed-strings 'Reject symlinked SSH configuration drop-ins before the Hermes MCP policy' "${task_file}" | cut -d: -f1)
ssh_context_reject_line=$(rg -n --fixed-strings 'Reject scoped SSH Match policy and unverified Includes before the Hermes MCP policy' "${task_file}" | cut -d: -f1)
ssh_reload_line=$(rg -n --fixed-strings 'Reload SSH service to activate forced-command policy before publishing MCP keys' "${task_file}" | cut -d: -f1)
ssh_effective_policy_line=$(rg -n --fixed-strings 'Read the effective Hermes MCP SSH forced-command policy before publishing MCP keys' "${task_file}" | cut -d: -f1)
ssh_effective_policy_assert_line=$(rg -n --fixed-strings 'Require the effective Hermes MCP SSH forced-command policy before publishing MCP keys' "${task_file}" | cut -d: -f1)
keys_line=$(rg -n --fixed-strings 'Publish restricted copies of administrator SSH public keys' "${task_file}" | cut -d: -f1)
sudoers_line=$(rg -n --fixed-strings 'Install restricted Hermes MCP SSH sudoers policy' "${task_file}" | cut -d: -f1)
active_line=$(rg -n --fixed-strings 'Publish active Hermes MCP SSH lifecycle provenance' "${task_file}" | cut -d: -f1)

if (( provision_line >= ssh_context_discover_line || ssh_context_discover_line >= ssh_context_symlink_reject_line || ssh_context_symlink_reject_line >= ssh_context_reject_line || ssh_context_reject_line >= ssh_policy_line || ssh_policy_line >= ssh_reload_line || ssh_reload_line >= ssh_effective_policy_line || ssh_effective_policy_line >= ssh_effective_policy_assert_line || ssh_effective_policy_assert_line >= user_create_line || user_create_line >= keys_line || keys_line >= sudoers_line || sudoers_line >= active_line )); then
  printf 'Hermes MCP SSH publication order must reject earlier scoped policy and symlinked drop-ins before policy activation and credential publication.\n' >&2
  exit 1
fi

if (( wrapper_ancestor_auth_line >= wrapper_ancestor_realpath_line || wrapper_ancestor_realpath_line >= wrapper_ancestor_canonical_command_line || wrapper_ancestor_canonical_command_line >= wrapper_ancestor_canonical_line || wrapper_ancestor_canonical_line >= libexec_directory_line || libexec_directory_line >= wrapper_directory_line )); then
  printf 'Hermes MCP SSH wrapper ancestors must be authenticated and canonicalized before parent and leaf creation.\n' >&2
  exit 1
fi

if (( wrapper_ancestor_canonical_line >= user_create_line )); then
  printf 'Hermes MCP SSH home ancestors must be canonicalized before user create_home.\n' >&2
  exit 1
fi
require_multiline_text '- path: /usr/local/libexec
      required: false
      mode: "0755"
      create_if_absent: true' "${task_file}"
require_multiline_text '- path: /var
      required: true
      mode: "0755"
      create_if_absent: false
      policy: safe-system-directory
    - path: /var/lib
      required: true
      mode: "0755"
      create_if_absent: false
      policy: safe-system-directory' "${task_file}"
require_multiline_text "selectattr('item.path', 'equalto', piserv_hermes_mcp_ssh_wrapper_path | dirname) |
    map(attribute='stat.exists') | first" "${task_file}"
require_text 'command="/usr/bin/sudo -n {{ piserv_hermes_mcp_ssh_wrapper_path }}",restrict' \
  "${keys_template}"
require_text 'Managed by Ansible: automatic administrator key copy for Hermes MCP SSH.' \
  "${keys_template}"
require_text 'Require the automatic Hermes MCP SSH authorized keys marker' \
  "${task_file}"
require_text 'create_home: false' "${task_file}"
require_multiline_text '- name: Inspect legacy Hermes MCP SSH account skeleton files before removal
  ansible.builtin.stat:
    path: "{{ piserv_hermes_mcp_ssh_home }}/{{ item }}"
    follow: false
  loop:
    - .bash_logout
    - .bashrc
    - .profile
  register: piserv_hermes_mcp_ssh_skeleton_file_state
  changed_when: false
  check_mode: false' "${task_file}"
require_text 'Require safe legacy Hermes MCP SSH account skeleton files' "${task_file}"
require_text "item.stat.mode == '0644'" "${task_file}"
require_multiline_text '- name: Remove legacy Hermes MCP SSH account skeleton files
  ansible.builtin.file:
    path: "{{ item.item }}"
    state: absent
  loop: "{{ piserv_hermes_mcp_ssh_skeleton_file_state.results }}"
  loop_control:
    label: "{{ item.item }}"
  when: item.stat.exists' "${task_file}"
require_multiline_text '- name: Publish restricted copies of administrator SSH public keys
  ansible.builtin.template:
    src: "{{ playbook_dir }}/templates/hermes-mcp-ssh-authorized_keys.j2"' \
  "${task_file}"
require_multiline_text '- name: Install root-owned Hermes MCP SSH wrapper
  ansible.builtin.template:
    src: "{{ playbook_dir }}/templates/hermes-mcp-ssh-wrapper.sh.j2"' \
  "${task_file}"
require_text "selectattr('item', 'equalto', piserv_hermes_mcp_ssh_home ~ '/.ssh')" \
  "${task_file}"
require_text '"schema": "piserv-hermes-mcp-ssh-state-v1"' "${state_template}"
require_text '"phase": {{ piserv_hermes_mcp_ssh_lifecycle_phase | default('\''active'\'') | to_json }}' \
  "${state_template}"
require_text '"mcp_ssh_user": {{ piserv_hermes_mcp_ssh_user | to_json }}' \
  "${state_template}"
require_text '"key_provenance": {{ piserv_hermes_mcp_ssh_key_provenance | to_json }}' \
  "${state_template}"
require_text 'exec /usr/bin/systemd-run --quiet --wait --pipe --collect --service-type=exec' \
  "${wrapper_template}"
require_text '--property=User={{ hermes_agent_user | quote }}' "${wrapper_template}"
require_text '--property=Group={{ hermes_agent_group | quote }}' "${wrapper_template}"
require_text 'PYTHONWARNINGS=ignore' "${wrapper_template}"
require_text '--property=NoNewPrivileges=true' "${wrapper_template}"
require_text 'BindReadOnlyPaths=' "${wrapper_template}"
require_text 'EnvironmentFile={{ hermes_agent_home_assistant_mcp_token_env_file | quote }}' \
  "${wrapper_template}"
require_text 'WorkingDirectory={{ (hermes_agent_home ~ '\''/workspace'\'') | quote }}' \
  "${wrapper_template}"
require_text '{{ hermes_agent_binary_path | quote }} mcp serve' "${wrapper_template}"
require_text 'NOPASSWD: {{ piserv_hermes_mcp_ssh_wrapper_path }} ""' \
  "${sudoers_template}"
require_text 'Defaults:{{ piserv_hermes_mcp_ssh_user }} !use_pty' \
  "${sudoers_template}"
require_text 'ForceCommand /usr/bin/sudo -n {{ piserv_hermes_mcp_ssh_wrapper_path }}' \
  "${repository_root}/ansible/playbooks/templates/hermes-mcp-ssh-sshd.conf.j2"
require_text 'DisableForwarding yes' \
  "${repository_root}/ansible/playbooks/templates/hermes-mcp-ssh-sshd.conf.j2"
require_text 'PermitTTY no' \
  "${repository_root}/ansible/playbooks/templates/hermes-mcp-ssh-sshd.conf.j2"
require_text 'X11Forwarding no' \
  "${repository_root}/ansible/playbooks/templates/hermes-mcp-ssh-sshd.conf.j2"
require_text 'Match all' \
  "${repository_root}/ansible/playbooks/templates/hermes-mcp-ssh-sshd.conf.j2"
require_text 'Configure restricted SSH access to the Hermes MCP server' \
  "${playbook}"
require_text 'Reload SSH service' "${playbook}"
require_text '## Configure Codex Client' "${runbook}"
require_text 'codex mcp add hermes-piserv' "${runbook}"
require_text '## Configure Another MCP Client' "${runbook}"
require_text '## Operator Acceptance Matrix' "${runbook}"
require_text 'This is a transport smoke test only:' "${runbook}"
require_text '| Approved reversible entity |' "${runbook}"
require_text '| Configured target forwarding |' "${runbook}"
require_text '| Sibling-entity negative |' "${runbook}"
require_text '| Unreachable-dependency negative |' "${runbook}"
require_text 'For an intentional teardown, first remove the local Codex MCP' "${runbook}"
require_text 'It fails closed on a' "${runbook}"
require_text 'missing or invalid lifecycle record, symlink, unexpected' "${runbook}"
require_text 'Authenticate containment before touching a path' "${runbook}"
require_text 'path_exists_or_is_symlink() {' "${runbook}"
require_text "test -e \"\$1\" || test -L \"\$1\"" "${runbook}"
require_text 'require_safe_parent() {' "${runbook}"
require_text "test \"\${metadata%%:*}\" = root" "${runbook}"
require_text '[0-7][0145][0145]' "${runbook}"
require_text 'recovers the account, group, home, key,' "${runbook}"
require_text "key_directory=\${keys%/*}" "${runbook}"
require_text 'codex-hermes-mcp:codex-hermes-mcp:700' "${runbook}"
require_text 'umask 077' "${runbook}"
require_text "cleanup_staged() { rm -f -- \"\$staged\"; }" "${runbook}"
require_text 'trap cleanup_staged EXIT' "${runbook}"
require_text "/usr/bin/awk \"1\" \"\$keys\" >\"\$staged\"" "${runbook}"
require_text 'mv --' "${runbook}"
require_text 'wrapper, and sudoers paths from the root-owned lifecycle record' "${runbook}"
require_text 'load_lifecycle_state() {' "${runbook}"
require_text 'lifecycle identity is incomplete' "${runbook}"
require_text 're.fullmatch(r"/etc/sudoers\.d/[a-z0-9_-]+", sudoers)' "${runbook}"
require_text 'refusing to leave recovered home without its lifecycle account:' "${runbook}"
require_text "test \"\$group_gid\" != 0" "${runbook}"
require_text 'group_only_resume=false' "${runbook}"
require_text 'A prior run can stop after userdel but before groupdel.' "${runbook}"
require_text 'test -z ' "${runbook}"
require_text 'cut -d: -f4)' "${runbook}"
require_text 'A standalone group is permitted only after the exact deny policy has been' \
  "${runbook}"
require_text "if \"\$group_only_resume\"; then" "${runbook}"
require_text "teardown_drain_verified=false" "${runbook}"
require_text "teardown_drain_verified=true" "${runbook}"
require_text "test \"\$teardown_drain_verified\" = true" "${runbook}"
require_text "elif \"\$group_only_resume\"; then" "${runbook}"
require_text "Debian's USERGROUPS_ENAB policy can remove the account's private group" \
  "${runbook}"
require_multiline_text "remove_private_group_if_present() {
  if getent group \"\$group\" >/dev/null; then
    groupdel \"\$group\"
  fi
}" "${runbook}"
require_text '  remove_private_group_if_present' "${runbook}"
require_text 'unexpected lifecycle authorized_keys path' "${runbook}"
require_text 'unexpected lifecycle wrapper path' "${runbook}"
require_text 'unexpected lifecycle sudoers path' "${runbook}"
require_text 'if state.get("phase") not in {"provisioning", "active"}:' "${runbook}"
require_text 'print("|".join((user, group, home, keys, wrapper, sudoers)))' "${runbook}"
require_text "IFS='|' read -r user group home keys wrapper sudoers" "${runbook}"
require_text 'load_lifecycle_state' "${runbook}"
require_text "find \"\$home/.ssh\" -xdev -mindepth 1 -print -quit" "${runbook}"
require_text 'Older deployments can contain these bounded useradd skeleton paths;' \
  "${runbook}"
require_text 'for skeleton_file in .bash_logout .bashrc .profile; do' "${runbook}"
skeleton_home_file_ref="\$home/\$skeleton_file"
skeleton_identity_ref="\${user}:\${group}:644"
require_multiline_text "for skeleton_file in .bash_logout .bashrc .profile; do
      if path_exists_or_is_symlink \"${skeleton_home_file_ref}\"; then
        require_regular \"${skeleton_home_file_ref}\" \"${skeleton_identity_ref}\"
      fi
    done" "${runbook}"
require_text 'Current provisioning creates the dedicated home explicitly and keeps it' \
  "${runbook}"
require_multiline_text 'authenticate and remove any that remain, but accept a current clean home.' \
  "${runbook}"
require_text 'make the bounded-home check fail closed.' \
  "${runbook}"
require_text "require_regular \"\$home/\$skeleton_file\" \"\${user}:\${group}:644\"" "${runbook}"
require_text "rm -f -- \"\$home/\$skeleton_file\"" "${runbook}"
require_text 'primary GID is the target group' "${runbook}"
require_text "primary_gid_users=\$(getent passwd | awk -F:" "${runbook}"
require_text "'\$1 != user && \$4 == gid { print \$1 }'" "${runbook}"
require_text 'refusing to delete a group used as a primary GID by:' "${runbook}"
require_text 'Authenticate every existing managed artifact.' "${runbook}"
require_text 'require_exact_line() {' "${runbook}"
require_text "require_marker \"\$dropin\" '# Managed by Ansible. Restrict this principal even when its authorized_keys'" \
  "${runbook}"
require_text "require_exact_line \"\$dropin\" \"Match User \$user\"" "${runbook}"
require_text "require_exact_line \"\$dropin\" \"    ForceCommand /usr/bin/sudo -n \$wrapper\"" \
  "${runbook}"
require_text "require_marker \"\$sudoers\" '# Managed by Ansible. Permit only the no-argument Hermes MCP entry point.'" \
  "${runbook}"
require_text "require_exact_line \"\$sudoers\" \"Defaults:\$user !use_pty\"" "${runbook}"
require_text "require_exact_line \"\$sudoers\" \"\$user ALL=(root) NOPASSWD: \$wrapper \\\"\\\"\"" \
  "${runbook}"
require_text "visudo -cf \"\$sudoers\"" "${runbook}"
require_text '# Drain the SSH principal before revoking it.' \
  "${runbook}"
require_text 'ForceCommand /usr/bin/false' "${runbook}"
require_text 'require_unscoped_preceding_match_context() {' "${runbook}"
require_text 'require_regular /etc/ssh/sshd_config root:root:644' "${runbook}"
require_text "' /etc/ssh/sshd_config)" "${runbook}"
require_text 'refusing SSH teardown with scoped Match directives or unproven Includes in the main configuration:' \
  "${runbook}"
require_text 'refusing SSH teardown with preceding scoped Match directives or Includes:' "${runbook}"
require_text "require_unscoped_preceding_match_context" "${runbook}"
require_text 'Resume a prior safe drain only when its exact root-owned policy remains.' "${runbook}"
require_text "require_regular \"\$teardown_deny\" root:root:644" "${runbook}"
require_text "cmp -s -- \"\$expected_deny\" \"\$teardown_deny\"" "${runbook}"
require_text "test \"\$teardown_drain_verified\" = true" "${runbook}"
require_text "sshd -T -C \"user=\${user},addr=127.0.0.1,host=localhost\"" "${runbook}"
require_text "grep -Fx 'forcecommand /usr/bin/false'" "${runbook}"
require_text "grep -Fx 'disableforwarding yes'" "${runbook}"
require_text 'PermitUserRC no' "${runbook}"
require_text "grep -Fx 'permituserrc no'" "${runbook}"
require_text "'sudo -n /bin/sh -seu'" "${runbook}"
require_text 'systemctl reload ssh' "${runbook}"
require_text "active_sessions=\$(loginctl list-sessions --no-legend |" "${runbook}"
require_text "refusing teardown while %s has active SSH sessions" \
  "${runbook}"
require_text 'sshd -t' "${runbook}"
require_text "if path_exists_or_is_symlink \"\$home/.ssh\"; then rmdir -- \"\$home/.ssh\"; fi" \
  "${runbook}"
require_text "! getent passwd \"\$user\" && ! getent group \"\$group\"" "${runbook}"
require_text "! path_exists_or_is_symlink \"\$home\"" "${runbook}"
require_text "! path_exists_or_is_symlink \"\$home/.ssh\"" "${runbook}"
require_text "! path_exists_or_is_symlink \"\$keys\"" "${runbook}"
require_text "! path_exists_or_is_symlink \"\$wrapper\"" "${runbook}"
require_text "! path_exists_or_is_symlink \"\$sudoers\"" "${runbook}"
if rg --fixed-strings --quiet -- 'test "$teardown_resume" = true' "${runbook}"; then
  printf 'Hermes MCP SSH teardown may accept missing key material only after the drain is proven effective.\n' >&2
  exit 1
fi
teardown_artifacts_line=$(rg -n --fixed-strings 'rm -f -- "$sudoers" "$wrapper" "$dropin"' "${runbook}" | cut -d: -f1)
teardown_keys_line=$(rg -n --fixed-strings 'rm -f -- "$keys"' "${runbook}" | cut -d: -f1)
teardown_skeleton_line=$(rg -n --fixed-strings 'rm -f -- "$home/$skeleton_file"' "${runbook}" | cut -d: -f1)
teardown_reload_line=$(rg -n --fixed-strings 'systemctl reload ssh' "${runbook}" | \
  awk -F: -v after_line="${teardown_artifacts_line}" '$1 > after_line { print $1; exit }')
teardown_state_line=$(rg -n --fixed-strings 'rm -f -- "$state"' "${runbook}" | cut -d: -f1)
teardown_primary_gid_check_line=$(rg -n --fixed-strings 'primary_gid_users=$(getent passwd | awk -F:' "${runbook}" | cut -d: -f1)
teardown_deny_line=$(rg -n --fixed-strings '# Drain the SSH principal before revoking it.' "${runbook}" | cut -d: -f1)
teardown_deny_publish_line=$(rg -n --fixed-strings 'mv -- "$deny_tmp" "$teardown_deny"' "${runbook}" | cut -d: -f1)
teardown_deny_validate_line=$(rg -n --fixed-strings 'sshd -t' "${runbook}" | awk -F: -v after_line="${teardown_deny_publish_line}" '$1 > after_line { print $1; exit }')
teardown_deny_reload_line=$(rg -n --fixed-strings 'systemctl reload ssh' "${runbook}" | awk -F: -v after_line="${teardown_deny_validate_line}" '$1 > after_line { print $1; exit }')
teardown_deny_effective_line=$(rg -n --fixed-strings 'effective_deny=$(sshd -T -C "user=${user},addr=127.0.0.1,host=localhost")' "${runbook}" | cut -d: -f1)
teardown_activity_check_line=$(rg -n --fixed-strings '# No new principal session can now authenticate.' "${runbook}" | cut -d: -f1)
teardown_deny_remove_line=$(rg -n --fixed-strings 'rm -f -- "$teardown_deny"' "${runbook}" | cut -d: -f1)
teardown_final_validate_line=$(rg -n --fixed-strings 'sshd -t' "${runbook}" | \
  awk -F: -v after_line="${teardown_deny_remove_line}" '$1 > after_line { print $1; exit }')
teardown_final_reload_line=$(rg -n --fixed-strings 'systemctl reload ssh' "${runbook}" | \
  awk -F: -v after_line="${teardown_final_validate_line}" '$1 > after_line { print $1; exit }')
teardown_dropin_match_line=$(rg -n --fixed-strings 'require_exact_line "$dropin" "Match User $user"' "${runbook}" | cut -d: -f1)
teardown_dropin_wrapper_line=$(rg -n --fixed-strings 'require_exact_line "$dropin" "    ForceCommand /usr/bin/sudo -n $wrapper"' "${runbook}" | cut -d: -f1)
teardown_sudoers_user_line=$(rg -n --fixed-strings 'require_exact_line "$sudoers" "Defaults:$user !use_pty"' "${runbook}" | cut -d: -f1)
teardown_sudoers_wrapper_line=$(rg -n --fixed-strings 'require_exact_line "$sudoers" "$user ALL=(root) NOPASSWD: $wrapper \"\""' "${runbook}" | cut -d: -f1)

if (( teardown_primary_gid_check_line >= teardown_dropin_match_line || teardown_dropin_match_line >= teardown_dropin_wrapper_line || teardown_dropin_wrapper_line >= teardown_sudoers_user_line || teardown_sudoers_user_line >= teardown_sudoers_wrapper_line || teardown_sudoers_wrapper_line >= teardown_deny_line || teardown_deny_line >= teardown_deny_publish_line || teardown_deny_publish_line >= teardown_deny_validate_line || teardown_deny_validate_line >= teardown_deny_reload_line || teardown_deny_reload_line >= teardown_deny_effective_line || teardown_deny_effective_line >= teardown_activity_check_line || teardown_activity_check_line >= teardown_keys_line || teardown_keys_line >= teardown_skeleton_line || teardown_skeleton_line >= teardown_artifacts_line || teardown_artifacts_line >= teardown_reload_line || teardown_reload_line >= teardown_deny_remove_line || teardown_deny_remove_line >= teardown_final_validate_line || teardown_final_validate_line >= teardown_final_reload_line || teardown_final_reload_line >= teardown_state_line )); then
  printf 'Hermes MCP SSH teardown must retain authenticated lifecycle state until the deny policy is removed and final SSH validation and reload succeed.\n' >&2
  exit 1
fi

require_multiline_text "no account entry before a clean apply or \`piserv_hermes_mcp_ssh_manage: false\`
is used." "${runbook}"
require_multiline_text 'Do not substitute a successful tool-list response for any matrix row. Do not
test destructive actions or an entity whose restoration is uncertain.' "${runbook}"

if rg --fixed-strings --quiet -- 'NOPASSWD: ALL' "${sudoers_template}"; then
  printf 'The Hermes MCP SSH sudoers policy must not grant NOPASSWD: ALL.\n' >&2
  exit 1
fi

ansible-playbook --inventory localhost, --connection local \
  "${repository_root}/ansible/tests/test-hermes-mcp-ssh-templates.yml" >/dev/null

ansible-playbook --inventory localhost, --connection local --check \
  "${repository_root}/ansible/tests/test-hermes-mcp-ssh-templates.yml" >/dev/null

printf 'HERMES_MCP_SSH_POLICY_OK\n'
