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
delegation_adapter_template="${repository_root}/ansible/playbooks/templates/hermes-delegation-mcp.py.j2"
delegation_config_template="${repository_root}/ansible/playbooks/templates/hermes-delegation-config.yaml.j2"
delegation_wrapper_template="${repository_root}/ansible/playbooks/templates/hermes-delegation-mcp-ssh-wrapper.sh.j2"
delegation_broker_template="${repository_root}/ansible/playbooks/templates/hermes-delegation-home-assistant-mcp-broker.py.j2"
delegation_broker_wrapper_template="${repository_root}/ansible/playbooks/templates/hermes-delegation-home-assistant-mcp-broker-wrapper.sh.j2"
delegation_broker_sudoers_template="${repository_root}/ansible/playbooks/templates/hermes-delegation-home-assistant-mcp-broker-sudoers.j2"
lifecycle_publication_task_file="${repository_root}/ansible/tasks/hermes-mcp-ssh-publish-lifecycle.yml"
playbook="${repository_root}/ansible/playbooks/hermes-agent.yml"
runbook="${repository_root}/docs/runbooks/hermes-mcp-ssh.md"
delegation_runbook="${repository_root}/docs/runbooks/hermes-delegation-mcp-ssh.md"
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
require_text 'piserv_hermes_mcp_ssh_wrapper_template: hermes-mcp-ssh-wrapper.sh.j2' \
  "${group_variables}"
require_text 'piserv_hermes_mcp_ssh_sshd_config_path:' "${group_variables}"
require_text 'shell: /bin/sh' "${task_file}"
require_text 'force: false' "${repository_root}/ansible/tasks/hermes-mcp-ssh-user-owned-mutations.yml"
require_text "piserv_hermes_mcp_ssh_home ~ '/.ssh/authorized_keys'" "${task_file}"
require_text 'Normalize Hermes runtime identity records' "${task_file}"
require_text '((ansible_facts.getent_passwd | default({}, true)).get(hermes_agent_user, []) | default([], true))' "${task_file}"
require_text '((ansible_facts.getent_group | default({}, true)).get(hermes_agent_group, []) | default([], true))' "${task_file}"
require_text 'Classify a fresh check-mode Hermes runtime identity simulation' "${task_file}"
require_text 'Provision Hermes MCP SSH lifecycle provenance before account mutation' \
  "${task_file}"
require_text 'Normalize existing Hermes MCP SSH identity records' "${task_file}"
runtime_prerequisite_tasks=$(sed -n \
  '/^- name: Inspect the Hermes MCP runtime launch prerequisites$/,/^- name: Create the Hermes MCP SSH libexec parent directory$/p' \
  "${task_file}")
if rg --fixed-strings --quiet -- 'when: not ansible_check_mode' <<<"${runtime_prerequisite_tasks}"; then
  printf 'Hermes MCP runtime prerequisite authentication must run during converged check mode.\n' >&2
  exit 1
fi
runtime_prerequisite_when_count=$(rg --fixed-strings --count \
  'when: not piserv_hermes_mcp_ssh_runtime_identity_is_fresh_check_mode' \
  <<<"${runtime_prerequisite_tasks}")
if (( runtime_prerequisite_when_count != 1 )); then
  printf 'Hermes MCP runtime prerequisite authentication must skip only fresh identity simulation.\n' >&2
  exit 1
fi
require_multiline_text '- name: Create password-locked Hermes MCP SSH system user
  ansible.builtin.user:' "${task_file}"
user_creation_tasks=$(sed -n \
  '/^- name: Create password-locked Hermes MCP SSH system user$/,/^- name: Set dedicated Hermes MCP SSH home permissions$/p' \
  "${task_file}")
if ! rg --fixed-strings --quiet -- \
  'when: not piserv_hermes_mcp_ssh_runtime_identity_is_fresh_check_mode' \
  <<<"${user_creation_tasks}"; then
  printf 'Fresh check-mode identity simulation must defer dependent MCP SSH user creation.\n' >&2
  exit 1
fi
user_owned_mutation_task_file="${repository_root}/ansible/tasks/hermes-mcp-ssh-user-owned-mutations.yml"
user_owned_mutation_tasks=$(<"${user_owned_mutation_task_file}")
user_owned_mutation_when_count=$(rg --fixed-strings --count \
  'piserv_hermes_mcp_ssh_runtime_identity_is_fresh_check_mode' \
  <<<"${user_owned_mutation_tasks}")
if (( user_owned_mutation_when_count != 5 )); then
  printf 'Fresh check-mode identity simulation must defer all five user-owned MCP SSH mutations.\n' >&2
  exit 1
fi
for mutation in home legacy-skeletons ssh-directory manual-key automatic-key; do
  require_text "piserv_hermes_mcp_ssh_user_owned_mutation: ${mutation}" "${task_file}"
done
for mutation_task in \
  'Set dedicated Hermes MCP SSH home permissions' \
  'Remove legacy Hermes MCP SSH account skeleton files' \
  'Create private Hermes MCP SSH directory' \
  'Create an empty operator-managed Hermes MCP SSH authorized keys file' \
  'Publish restricted copies of administrator SSH public keys'; do
  require_text "${mutation_task}" "${user_owned_mutation_task_file}"
done
require_text 'Read passwd records before adopting the Hermes MCP SSH group' "${task_file}"
require_text 'Identify existing primary-GID users of the Hermes MCP SSH group' "${task_file}"
require_text 'hermes-mcp-ssh-primary-gid-users.yml' "${task_file}"
require_text 'item.key != piserv_hermes_mcp_ssh_user' \
  "${repository_root}/ansible/tasks/hermes-mcp-ssh-primary-gid-users.yml"
require_text 'item.value[2] == piserv_hermes_mcp_ssh_account_group_record[1]' \
  "${repository_root}/ansible/tasks/hermes-mcp-ssh-primary-gid-users.yml"
require_text 'piserv_hermes_mcp_ssh_account_group_primary_gid_users | length == 0' \
  "${task_file}"
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
require_multiline_text "piserv_hermes_mcp_ssh_account_passwd_record[5] == '/bin/sh' and
        piserv_hermes_mcp_ssh_account_group_record | length == 3 and
        piserv_hermes_mcp_ssh_account_group_record[1] != '0' and
        piserv_hermes_mcp_ssh_account_group_record[2] == '')" "${task_file}"
require_text 'Define the Hermes MCP SSH lifecycle key provenance' "${task_file}"
require_text 'piserv_hermes_mcp_ssh_state_path:' "${group_variables}"
require_text 'piserv_hermes_mcp_ssh_trusted_preceding_match_configs: []' \
  "${group_variables}"
require_text 'Inspect existing privileged Hermes MCP SSH artifacts before mutation' \
  "${task_file}"
require_text 'not (item.stat.ismount | default(false))' "${task_file}"
require_text 'Authenticate existing privileged Hermes MCP SSH artifacts' \
  "${task_file}"
require_text 'Require lifecycle provenance before adopting Hermes MCP SSH state' \
  "${provenance_task_file}"
require_text 'Require managed markers before replacing Hermes MCP SSH artifacts' \
  "${task_file}"
require_text 'Provision Hermes MCP SSH lifecycle provenance before account mutation' \
  "${task_file}"
require_text 'hermes-mcp-ssh-publish-lifecycle.yml' "${task_file}"
require_text 'Mark Hermes MCP SSH lifecycle provenance active after credential publication' \
  "${task_file}"
require_text 'Publish active Hermes MCP SSH lifecycle provenance' \
  "${task_file}"
require_multiline_text '- name: Publish Hermes MCP SSH lifecycle provenance
  ansible.builtin.template:
    src: "{{ piserv_hermes_mcp_ssh_lifecycle_template_source }}"
    dest: "{{ piserv_hermes_mcp_ssh_state_path }}"
    owner: root
    group: root
    mode: "0600"
  register: piserv_hermes_mcp_ssh_lifecycle_publication
  when: >-
    not ansible_check_mode or
    (piserv_hermes_mcp_ssh_publication_parent_state.results |
    selectattr('\''item.path'\'', '\''equalto'\'', piserv_hermes_mcp_ssh_wrapper_path | dirname) |
    map(attribute='\''stat.exists'\'') | first)' "${lifecycle_publication_task_file}"
require_text 'Exercise provisioning lifecycle publication guard on a fresh host' \
  "${repository_root}/ansible/tests/test-hermes-mcp-ssh-templates.yml"
require_text 'piserv_hermes_mcp_ssh_lifecycle_publication is skipped' \
  "${repository_root}/ansible/tests/test-hermes-mcp-ssh-templates.yml"
require_text 'Exercise active lifecycle publication guard on a fresh host' \
  "${repository_root}/ansible/tests/test-hermes-mcp-ssh-templates.yml"
require_text 'ansible.builtin.include_tasks: ../tasks/hermes-mcp-ssh-publish-lifecycle.yml' \
  "${repository_root}/ansible/tests/test-hermes-mcp-ssh-templates.yml"
require_text 'Exercise the production provenance gate for a group-only resume' \
  "${repository_root}/ansible/tests/test-hermes-mcp-ssh-templates.yml"
require_text 'Verify the active group-only fixture failed provenance validation' \
  "${repository_root}/ansible/tests/test-hermes-mcp-ssh-templates.yml"
require_text 'Verify the absent group-only fixture failed provenance validation' \
  "${repository_root}/ansible/tests/test-hermes-mcp-ssh-templates.yml"
require_text 'Reject administrator SSH key options before automatic MCP SSH access' \
  "${task_file}"
require_text 'Verify automatic key copy rejects every SSH key option' \
  "${repository_root}/ansible/tests/test-hermes-mcp-ssh-templates.yml"
require_text 'is not match(hermes_mcp_ssh_plain_public_key_pattern)' \
  "${repository_root}/ansible/tests/test-hermes-mcp-ssh-templates.yml"
require_text "no-command=\"not a forced command\"" \
  "${repository_root}/ansible/tests/test-hermes-mcp-ssh-templates.yml"
require_text 'environment="X ssh-ed25519 placeholder",command="unsafe"' \
  "${repository_root}/ansible/tests/test-hermes-mcp-ssh-templates.yml"
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
require_text '- item.isreg' "${task_file}"
require_text 'Inspect consumed SSH configuration leaves before the Hermes MCP policy' \
  "${task_file}"
require_text 'Authenticate consumed SSH configuration leaves before the Hermes MCP policy' \
  "${task_file}"
require_text 'Read authenticated SSH configuration before the Hermes MCP policy' \
  "${task_file}"
require_text 'Reinspect consumed SSH configuration leaves after reading policy' \
  "${task_file}"
require_text 'Require consumed SSH configuration leaves to retain their authenticated inode and content' \
  "${task_file}"
require_text 'Reject scoped SSH Match policy and unverified Includes before the Hermes MCP policy' \
  "${task_file}"
require_text "selectattr('path', 'lt', piserv_hermes_mcp_ssh_sshd_config_path)" \
  "${task_file}"
require_text 'Authenticate trusted preceding Hermes MCP SSH Match policies' \
  "${task_file}"
require_text 'piserv_hermes_mcp_ssh_trusted_preceding_match_configs' \
  "${task_file}"
require_text "'(?im)^\\\\s*Match\\\\s+(?!all\\\\s*(?:#.*)?$)'" \
  "${task_file}"
require_text "item.content | b64decode is not search('(?im)^\\\\s*Include\\\\s+')" \
  "${task_file}"
require_text "'(?im)^\\\\s*Include\\\\s+(?!/etc/ssh/sshd_config\\\\.d/\\\\*\\\\.conf\\\\s*(?:#.*)?$)'" \
  "${task_file}"
require_text "map(attribute='stat.inode') | first" "${task_file}"
require_text "map(attribute='stat.dev') | first" "${task_file}"
require_text 'get_checksum: true' "${task_file}"
require_text 'checksum_algorithm: sha256' "${task_file}"
require_text "map(attribute='content') | first) | b64decode | hash('sha256')" "${task_file}"
ssh_configuration_audit_tasks=$(sed -n \
  '/^- name: Reject symlinked SSH configuration drop-ins before the Hermes MCP policy$/,/^- name: Install SSH forced-command policy before publishing MCP keys$/p' \
  "${task_file}")
if rg --fixed-strings --quiet -- 'when: not ansible_check_mode' <<<"${ssh_configuration_audit_tasks}"; then
  printf 'Hermes MCP SSH configuration-leaf audit must run during converged check mode.\n' >&2
  exit 1
fi
require_text 'Validate the complete SSH daemon configuration before publishing MCP keys' \
  "${task_file}"
require_text 'Activate a changed SSH forced-command policy before publishing MCP keys' \
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
require_text "'trustedusercakeys none' in piserv_hermes_mcp_ssh_effective_policy.stdout_lines" \
  "${task_file}"
require_text "'pubkeyauthentication yes' in piserv_hermes_mcp_ssh_effective_policy.stdout_lines" \
  "${task_file}"
require_text "'authenticationmethods publickey' in piserv_hermes_mcp_ssh_effective_policy.stdout_lines" \
  "${task_file}"
require_text "'passwordauthentication no' in piserv_hermes_mcp_ssh_effective_policy.stdout_lines" \
  "${task_file}"
require_text "'kbdinteractiveauthentication no' in piserv_hermes_mcp_ssh_effective_policy.stdout_lines" \
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
require_text 'Inspect existing Hermes MCP SSH authorized keys file before mutation' \
  "${task_file}"
require_text 'Require a safe existing Hermes MCP SSH authorized keys file' \
  "${task_file}"
require_text 'PermitUserRC no' "${repository_root}/ansible/playbooks/templates/hermes-mcp-ssh-sshd.conf.j2"
require_text 'TrustedUserCAKeys none' "${repository_root}/ansible/playbooks/templates/hermes-mcp-ssh-sshd.conf.j2"
require_text 'PubkeyAuthentication yes' "${repository_root}/ansible/playbooks/templates/hermes-mcp-ssh-sshd.conf.j2"
require_text 'AuthenticationMethods publickey' "${repository_root}/ansible/playbooks/templates/hermes-mcp-ssh-sshd.conf.j2"
require_text 'PasswordAuthentication no' "${repository_root}/ansible/playbooks/templates/hermes-mcp-ssh-sshd.conf.j2"
require_text 'KbdInteractiveAuthentication no' "${repository_root}/ansible/playbooks/templates/hermes-mcp-ssh-sshd.conf.j2"
require_text 'Require global SSH admission for the Hermes MCP SSH account before publishing keys' \
  "${task_file}"
require_text "allow_users=\$(setting allowusers)" "${task_file}"
require_text "deny_users=\$(setting denyusers)" "${task_file}"
require_text "allow_groups=\$(setting allowgroups)" "${task_file}"
require_text "deny_groups=\$(setting denygroups)" "${task_file}"
require_text "if (\$0 != \"\" && \$0 != \"none\") {" "${task_file}"
require_text "values = values (values == \"\" ? \"\" : \" \") \$0" "${task_file}"
require_text 'print "none"' "${task_file}"
require_text 'set -f' "${task_file}"
ssh_admission_audit_tasks=$(sed -n \
  '/^- name: Require global SSH admission for the Hermes MCP SSH account before publishing keys$/,/^- name: Inspect legacy Hermes MCP SSH account skeleton files before removal$/p' \
  "${task_file}")
if rg --fixed-strings --quiet -- 'when: not ansible_check_mode' <<<"${ssh_admission_audit_tasks}"; then
  printf 'Hermes MCP SSH global-admission audit must run during converged check mode.\n' >&2
  exit 1
fi
ssh_admission_when_count=$(rg --fixed-strings --count \
  'when: not piserv_hermes_mcp_ssh_runtime_identity_is_fresh_check_mode' \
  <<<"${ssh_admission_audit_tasks}")
if (( ssh_admission_when_count != 1 )); then
  printf 'Hermes MCP SSH global-admission audit must skip only fresh identity simulation.\n' >&2
  exit 1
fi
require_multiline_text '- name: Install SSH forced-command policy before publishing MCP keys
  ansible.builtin.template:' "${task_file}"
require_multiline_text '    validate: /usr/sbin/sshd -t -f %s
  register: piserv_hermes_mcp_ssh_forced_command_policy
  notify: Reload SSH service' "${task_file}"
require_multiline_text '- name: Activate a changed SSH forced-command policy before publishing MCP keys
  ansible.builtin.meta: flush_handlers
  when: not ansible_check_mode' "${task_file}"
require_multiline_text '- name: Reload the existing SSH forced-command policy when resuming provisioning
  ansible.builtin.systemd_service:
    name: ssh
    state: reloaded
  when:
    - not ansible_check_mode
    - piserv_hermes_mcp_ssh_lifecycle_phase == '\''provisioning'\''
    - not piserv_hermes_mcp_ssh_forced_command_policy.changed' "${task_file}"
require_multiline_text '- name: Read the effective Hermes MCP SSH forced-command policy before publishing MCP keys
  ansible.builtin.command:
    argv:
      - /usr/sbin/sshd
      - -T
      - -C
      - >-
        user={{ piserv_hermes_mcp_ssh_user }},addr=127.0.0.1,host=localhost
  register: piserv_hermes_mcp_ssh_effective_policy
  changed_when: false
  check_mode: false
  when: not piserv_hermes_mcp_ssh_runtime_identity_is_fresh_check_mode' "${task_file}"
require_multiline_text '- name: Require the effective Hermes MCP SSH forced-command policy before publishing MCP keys
  ansible.builtin.assert:' "${task_file}"
effective_policy_tasks=$(sed -n \
  '/^- name: Read the effective Hermes MCP SSH forced-command policy before publishing MCP keys$/,/^- name: Create Hermes MCP SSH system group$/p' \
  "${task_file}")
if rg --fixed-strings --quiet -- 'when: not ansible_check_mode' <<<"${effective_policy_tasks}"; then
  printf 'Effective Hermes MCP SSH policy verification must run during converged check mode.\n' >&2
  exit 1
fi
effective_policy_when_count=$(rg --fixed-strings --count \
  'when: not piserv_hermes_mcp_ssh_runtime_identity_is_fresh_check_mode' \
  <<<"${effective_policy_tasks}")
if (( effective_policy_when_count != 2 )); then
  printf 'Effective Hermes MCP SSH policy read and assertion must skip only fresh identity simulation.\n' >&2
  exit 1
fi
sudo_policy_audit_tasks=$(sed -n \
  '/^- name: Verify the dedicated Hermes MCP SSH account has only the wrapper privilege$/,/^- name: Reinspect administrator authorized keys immediately before automatic MCP SSH publication$/p' \
  "${task_file}")
if rg --fixed-strings --quiet -- 'when: not ansible_check_mode' <<<"${sudo_policy_audit_tasks}"; then
  printf 'Hermes MCP SSH sudo-policy audit must run during converged check mode.\n' >&2
  exit 1
fi
sudo_policy_when_count=$(rg --fixed-strings --count \
  'when: not piserv_hermes_mcp_ssh_runtime_identity_is_fresh_check_mode' \
  <<<"${sudo_policy_audit_tasks}")
if (( sudo_policy_when_count != 2 )); then
  printf 'Hermes MCP SSH sudo-policy read and assertion must skip only fresh identity simulation.\n' >&2
  exit 1
fi
require_multiline_text "piserv_hermes_mcp_ssh_sudo_policy.stdout is regex(
          '(?m)(?:^|,)\\s*!use_pty(?:\\s|,|\$)'" "${task_file}"
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
require_text 'dest: "{{ piserv_hermes_mcp_ssh_sshd_config_path }}"' \
  "${task_file}"
require_text 'templates/{{ piserv_hermes_mcp_ssh_wrapper_template }}' \
  "${task_file}"
require_text 'when: not ansible_check_mode' "${task_file}"
provision_line=$(rg -n --fixed-strings 'Provision Hermes MCP SSH lifecycle provenance before account mutation' "${task_file}" | cut -d: -f1)
wrapper_ancestor_auth_line=$(rg -n --fixed-strings 'Authenticate every Hermes MCP SSH wrapper ancestor before mutation' "${task_file}" | cut -d: -f1)
wrapper_ancestor_realpath_line=$(rg -n --fixed-strings 'Authenticate the Hermes MCP SSH ancestor canonicalization executable' "${task_file}" | cut -d: -f1)
wrapper_ancestor_canonical_command_line=$(rg -n --fixed-strings 'Canonicalize every existing Hermes MCP SSH wrapper ancestor before mutation' "${task_file}" | cut -d: -f1)
wrapper_ancestor_canonical_line=$(rg -n --fixed-strings 'Require exact canonical Hermes MCP SSH wrapper ancestors before mutation' "${task_file}" | cut -d: -f1)
authorized_keys_inspect_line=$(rg -n --fixed-strings 'Inspect existing Hermes MCP SSH authorized keys file before mutation' "${task_file}" | cut -d: -f1)
authorized_keys_auth_line=$(rg -n --fixed-strings 'Require a safe existing Hermes MCP SSH authorized keys file' "${task_file}" | cut -d: -f1)
admin_key_ancestor_inspect_line=$(rg -n --fixed-strings 'Inspect administrator authorized keys ancestors before automatic copy' "${task_file}" | cut -d: -f1)
admin_key_ancestor_auth_line=$(rg -n --fixed-strings 'Require safe administrator authorized keys ancestors before automatic copy' "${task_file}" | cut -d: -f1)
admin_key_ancestor_canonical_line=$(rg -n --fixed-strings 'Require exact administrator authorized keys ancestors before automatic copy' "${task_file}" | cut -d: -f1)
authorized_keys_inspect_count=$(rg --fixed-strings --count 'Inspect existing Hermes MCP SSH authorized keys file' "${task_file}")
authorized_keys_auth_count=$(rg --fixed-strings --count 'Require a safe existing Hermes MCP SSH authorized keys file' "${task_file}")
libexec_directory_line=$(rg -n --fixed-strings 'Create the Hermes MCP SSH libexec parent directory' "${task_file}" | cut -d: -f1)
wrapper_directory_line=$(rg -n --fixed-strings 'Create the dedicated Hermes MCP SSH wrapper directory' "${task_file}" | cut -d: -f1)
user_create_line=$(rg -n --fixed-strings 'Create password-locked Hermes MCP SSH system user' "${task_file}" | cut -d: -f1)
ssh_policy_line=$(rg -n --fixed-strings 'Install SSH forced-command policy before publishing MCP keys' "${task_file}" | cut -d: -f1)
ssh_context_discover_line=$(rg -n --fixed-strings 'Discover SSH configuration drop-ins before the Hermes MCP policy' "${task_file}" | cut -d: -f1)
ssh_context_define_line=$(rg -n --fixed-strings 'Define SSH configuration files before the Hermes MCP policy' "${task_file}" | cut -d: -f1)
ssh_context_symlink_reject_line=$(rg -n --fixed-strings 'Reject symlinked SSH configuration drop-ins before the Hermes MCP policy' "${task_file}" | cut -d: -f1)
ssh_context_inspect_line=$(rg -n --fixed-strings 'Inspect consumed SSH configuration leaves before the Hermes MCP policy' "${task_file}" | cut -d: -f1)
ssh_context_authenticate_line=$(rg -n --fixed-strings 'Authenticate consumed SSH configuration leaves before the Hermes MCP policy' "${task_file}" | cut -d: -f1)
ssh_context_read_line=$(rg -n --fixed-strings 'Read authenticated SSH configuration before the Hermes MCP policy' "${task_file}" | cut -d: -f1)
ssh_context_reinspect_line=$(rg -n --fixed-strings 'Reinspect consumed SSH configuration leaves after reading policy' "${task_file}" | cut -d: -f1)
ssh_context_inode_line=$(rg -n --fixed-strings 'Require consumed SSH configuration leaves to retain their authenticated inode' "${task_file}" | cut -d: -f1)
ssh_context_reject_line=$(rg -n --fixed-strings 'Reject scoped SSH Match policy and unverified Includes before the Hermes MCP policy' "${task_file}" | cut -d: -f1)
ssh_reload_line=$(rg -n --fixed-strings 'Activate a changed SSH forced-command policy before publishing MCP keys' "${task_file}" | cut -d: -f1)
ssh_provisioning_reload_line=$(rg -n --fixed-strings 'Reload the existing SSH forced-command policy when resuming provisioning' "${task_file}" | cut -d: -f1)
ssh_effective_policy_line=$(rg -n --fixed-strings 'Read the effective Hermes MCP SSH forced-command policy before publishing MCP keys' "${task_file}" | cut -d: -f1)
ssh_effective_policy_assert_line=$(rg -n --fixed-strings 'Require the effective Hermes MCP SSH forced-command policy before publishing MCP keys' "${task_file}" | cut -d: -f1)
keys_line=$(rg -n --fixed-strings 'Publish restricted copies of administrator SSH public keys' "${task_file}" | cut -d: -f1)
sudoers_line=$(rg -n --fixed-strings 'Install restricted Hermes MCP SSH sudoers policy' "${task_file}" | cut -d: -f1)
sudo_verify_line=$(rg -n --fixed-strings 'Require the exact Hermes MCP SSH sudo privilege' "${task_file}" | cut -d: -f1)
active_line=$(rg -n --fixed-strings 'Publish active Hermes MCP SSH lifecycle provenance' "${task_file}" | cut -d: -f1)

if (( authorized_keys_inspect_count != 1 || authorized_keys_auth_count != 1 )); then
  printf 'Hermes MCP SSH authorized_keys preflight must have one current inspection and authentication task.\n' >&2
  exit 1
fi

if (( ssh_context_discover_line >= ssh_context_define_line || ssh_context_define_line >= ssh_context_symlink_reject_line || ssh_context_symlink_reject_line >= ssh_context_inspect_line || ssh_context_inspect_line >= ssh_context_authenticate_line || ssh_context_authenticate_line >= ssh_context_read_line || ssh_context_read_line >= ssh_context_reinspect_line || ssh_context_reinspect_line >= ssh_context_inode_line || ssh_context_inode_line >= ssh_context_reject_line || ssh_context_reject_line >= provision_line || provision_line >= ssh_policy_line || ssh_policy_line >= ssh_reload_line || ssh_reload_line >= ssh_provisioning_reload_line || ssh_provisioning_reload_line >= ssh_effective_policy_line || ssh_effective_policy_line >= ssh_effective_policy_assert_line || ssh_effective_policy_assert_line >= user_create_line || user_create_line >= sudoers_line || sudoers_line >= sudo_verify_line || sudo_verify_line >= keys_line || keys_line >= active_line )); then
  printf 'Hermes MCP SSH publication order must authenticate earlier SSH policy before lifecycle state, policy activation, and credential publication.\n' >&2
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

if (( authorized_keys_inspect_line >= authorized_keys_auth_line || authorized_keys_auth_line >= libexec_directory_line )); then
  printf 'Existing Hermes MCP SSH authorized_keys must be authenticated before any managed-path mutation.\n' >&2
  exit 1
fi

if (( admin_key_ancestor_inspect_line >= admin_key_ancestor_auth_line || admin_key_ancestor_auth_line >= admin_key_ancestor_canonical_line || admin_key_ancestor_canonical_line >= libexec_directory_line )); then
  printf 'Administrator authorized_keys ancestors must be authenticated and canonicalized before managed-path mutation.\n' >&2
  exit 1
fi
require_multiline_text '- path: /home
      owner: root
      group: root' "${task_file}"
require_text "item.stat.mode is match('^0[0-7][05][05]$')" "${task_file}"
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
    path: "{{ item }}"
    follow: false
  loop:
    - "{{ piserv_hermes_mcp_ssh_home }}/.bash_logout"
    - "{{ piserv_hermes_mcp_ssh_home }}/.bashrc"
    - "{{ piserv_hermes_mcp_ssh_home }}/.profile"
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
  register: piserv_hermes_mcp_ssh_skeleton_mutation
  when:
    - piserv_hermes_mcp_ssh_user_owned_mutation == '\''legacy-skeletons'\''
    - not piserv_hermes_mcp_ssh_runtime_identity_is_fresh_check_mode
    - item.stat.exists' "${user_owned_mutation_task_file}"
require_multiline_text '- name: Publish restricted copies of administrator SSH public keys
  ansible.builtin.template:
    src: "{{ playbook_dir }}/templates/hermes-mcp-ssh-authorized_keys.j2"' \
  "${user_owned_mutation_task_file}"
require_text 'Reinspect administrator authorized keys immediately before automatic MCP SSH publication' \
  "${task_file}"
require_text 'Revalidate the administrator authorized keys source before automatic MCP SSH publication' \
  "${task_file}"
require_text 'Reread administrator authorized keys immediately before automatic MCP SSH publication' \
  "${task_file}"
require_text 'Reinspect administrator authorized keys after automatic MCP SSH reread' \
  "${task_file}"
require_text 'Renormalize administrator public keys before automatic MCP SSH publication' \
  "${task_file}"
require_text 'Require unchanged administrator key material across automatic MCP SSH publication guard' \
  "${task_file}"
require_text 'Reject newly added administrator SSH key options before automatic MCP SSH publication' \
  "${task_file}"
require_text 'Require plain administrator public keys before automatic MCP SSH publication' \
  "${task_file}"
source_reinspect_line=$(rg -n --fixed-strings \
  'Reinspect administrator authorized keys immediately before automatic MCP SSH publication' \
  "${task_file}" | cut -d: -f1)
source_revalidate_line=$(rg -n --fixed-strings \
  'Revalidate the administrator authorized keys source before automatic MCP SSH publication' \
  "${task_file}" | cut -d: -f1)
source_reread_line=$(rg -n --fixed-strings \
  'Reread administrator authorized keys immediately before automatic MCP SSH publication' \
  "${task_file}" | cut -d: -f1)
source_reread_reinspect_line=$(rg -n --fixed-strings \
  'Reinspect administrator authorized keys after automatic MCP SSH reread' \
  "${task_file}" | cut -d: -f1)
source_renormalize_line=$(rg -n --fixed-strings \
  'Renormalize administrator public keys before automatic MCP SSH publication' \
  "${task_file}" | cut -d: -f1)
source_unchanged_line=$(rg -n --fixed-strings \
  'Require unchanged administrator key material across automatic MCP SSH publication guard' \
  "${task_file}" | cut -d: -f1)
source_reject_line=$(rg -n --fixed-strings \
  'Reject newly added administrator SSH key options before automatic MCP SSH publication' \
  "${task_file}" | cut -d: -f1)
source_plain_line=$(rg -n --fixed-strings \
  'Require plain administrator public keys before automatic MCP SSH publication' \
  "${task_file}" | cut -d: -f1)
if (( source_reinspect_line >= source_reread_line || source_reread_line >= source_reread_reinspect_line || source_reread_reinspect_line >= source_revalidate_line || source_revalidate_line >= source_renormalize_line || source_renormalize_line >= source_unchanged_line || source_unchanged_line >= source_reject_line || source_reject_line >= source_plain_line || source_plain_line >= keys_line )); then
  printf 'Administrator key material must be reauthenticated, reread, and revalidated immediately before publication.\n' >&2
  exit 1
fi
require_text "hash('sha256') ==" "${task_file}"
require_text 'piserv_hermes_mcp_ssh_source_authorized_keys_checksum' "${task_file}"
require_text 'piserv_hermes_mcp_ssh_source_authorized_keys_reread_state.stat.checksum' \
  "${task_file}"
require_text 'piserv_hermes_mcp_ssh_source_public_key_lines_before_publication' \
  "${task_file}"
require_text 'hermes-mcp-ssh-lifecycle-phase.yml' "${task_file}"
require_text 'Preserve active lifecycle provenance through the production phase selector' \
  "${repository_root}/ansible/tests/test-hermes-mcp-ssh-templates.yml"
require_multiline_text '- name: Install root-owned Hermes MCP SSH wrapper
  ansible.builtin.template:
    src: "{{ playbook_dir }}/templates/{{ piserv_hermes_mcp_ssh_wrapper_template }}"' \
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
require_text 'AuthorizedKeysFile {{ piserv_hermes_mcp_ssh_authorized_keys_path }}' \
  "${repository_root}/ansible/playbooks/templates/hermes-mcp-ssh-sshd.conf.j2"
require_text 'AuthorizedKeysCommand none' \
  "${repository_root}/ansible/playbooks/templates/hermes-mcp-ssh-sshd.conf.j2"
require_text 'DisableForwarding yes' \
  "${repository_root}/ansible/playbooks/templates/hermes-mcp-ssh-sshd.conf.j2"
require_text 'PermitTTY no' \
  "${repository_root}/ansible/playbooks/templates/hermes-mcp-ssh-sshd.conf.j2"
require_text 'X11Forwarding no' \
  "${repository_root}/ansible/playbooks/templates/hermes-mcp-ssh-sshd.conf.j2"
require_text 'Match all' \
  "${repository_root}/ansible/playbooks/templates/hermes-mcp-ssh-sshd.conf.j2"
require_multiline_text "'authorizedkeysfile ' ~ piserv_hermes_mcp_ssh_authorized_keys_path
        in piserv_hermes_mcp_ssh_effective_policy.stdout_lines" "${task_file}"
require_text "'authorizedkeyscommand none' in piserv_hermes_mcp_ssh_effective_policy.stdout_lines" \
  "${task_file}"
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
require_text "\"\$user:\$group:700\"" "${runbook}"
require_text 'umask 077' "${runbook}"
require_text "cleanup_staged() { rm -f -- \"\$staged\"; }" "${runbook}"
require_text 'trap cleanup_staged EXIT' "${runbook}"
require_text "/usr/bin/awk \"1\" \"\$keys\" >\"\$staged\"" "${runbook}"
require_text 'mv --' "${runbook}"
require_text "Ansible deliberately fails closed if the existing home or \`.ssh\` directory has" \
  "${runbook}"
require_text 'manual permission repair requires manual key provenance' "${runbook}"
require_text 'Re-authenticate the root-owned manual-key policy immediately before' "${runbook}"
require_text "reauthenticated_lifecycle_values=\$(read_manual_lifecycle)" "${runbook}"
require_text "test \"\$reauthenticated_lifecycle_values\" = \"\$lifecycle_values\"" "${runbook}"
manual_stage_line=$(rg -n --fixed-strings "staged=\$(mktemp \"\${keys}.XXXXXX\")" "${runbook}" | cut -d: -f1)
manual_reauth_line=$(rg -n --fixed-strings \
  "reauthenticated_lifecycle_values=\$(read_manual_lifecycle)" "${runbook}" | cut -d: -f1)
manual_replace_line=$(rg -n --fixed-strings "mv -- \"\$staged\" \"\$keys\"" "${runbook}" | cut -d: -f1)
if (( manual_stage_line >= manual_reauth_line || manual_reauth_line >= manual_replace_line )); then
  printf 'Manual key publication must reauthenticate lifecycle policy after staging and before atomic replacement.\n' >&2
  exit 1
fi
require_text "test -d \"\$home\" && test ! -L \"\$home\"" "${runbook}"
require_text "test -d \"\$ssh_directory\" && test ! -L \"\$ssh_directory\"" "${runbook}"
require_text "test -f \"\$keys\" && test ! -L \"\$keys\"" "${runbook}"
require_text 'require_expected_home_filesystem() {' "${runbook}"
require_text 'findmnt --noheadings --output SOURCE,FSTYPE --target /var/lib' "${runbook}"
require_text "findmnt --noheadings --output SOURCE,FSTYPE --target \"\$home\"" "${runbook}"
require_text 'refusing manual permission repair of lifecycle home mountpoint:' "${runbook}"
require_text 'refusing manual permission repair of lifecycle SSH directory mountpoint:' "${runbook}"
require_text "if mountpoint -q -- \"\$home\"; then" "${runbook}"
require_text "if mountpoint -q -- \"\$ssh_directory\"; then" "${runbook}"
require_multiline_text "  require_expected_home_filesystem

  chown -- \"\$user:\$group\" \"\$home\" \"\$ssh_directory\" \"\$keys\"" "${runbook}"
require_text "chmod 0750 \"\$home\"" "${runbook}"
require_text "chmod 0700 \"\$ssh_directory\"" "${runbook}"
require_text "chmod 0600 \"\$keys\"" "${runbook}"
require_text 'do not weaken the Ansible preflight or broaden this command' "${runbook}"
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
require_text 'manual keys require manual-operator-managed lifecycle provenance' "${runbook}"
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
require_text 'require_expected_home_filesystem() {' "${runbook}"
require_text 'findmnt --noheadings --output SOURCE,FSTYPE --target /var/lib' "${runbook}"
require_text "findmnt --noheadings --output SOURCE,FSTYPE --target \"\$home\"" "${runbook}"
require_text 'refusing teardown of lifecycle home mountpoint:' "${runbook}"
require_text 'refusing teardown of lifecycle SSH directory mountpoint:' "${runbook}"
require_text 'require_expected_home_filesystem' "${runbook}"
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
require_text 'require_safe_sshd_config_fragment() {' "${runbook}"
require_text 'for sshd_fragment in /etc/ssh/sshd_config.d/*.conf; do' "${runbook}"
require_text "require_safe_sshd_config_fragment \"\$sshd_fragment\"" "${runbook}"
require_text "test \"\$(stat -c '%U:%G' -- \"\$1\")\" = root:root" "${runbook}"
require_text 'test -f /etc/ssh/sshd_config && test ! -L /etc/ssh/sshd_config' "${runbook}"
require_text "test \"\$(stat -c '%U:%G' -- /etc/ssh/sshd_config)\" = root:root" "${runbook}"
require_text '[0-7][0145][0145]' "${runbook}"
require_text "' /etc/ssh/sshd_config)" "${runbook}"
require_text 'lower !~ /^include[[:space:]]+\/etc\/ssh\/sshd_config\.d\/\*\.conf([[:space:]]+#.*)?$/' \
  "${runbook}"
require_text 'refusing SSH teardown with scoped Match directives or unproven Includes in the main configuration:' \
  "${runbook}"
require_text 'refusing SSH teardown with preceding scoped Match directives or Includes:' "${runbook}"
require_text "find /etc/ssh/sshd_config.d -xdev -maxdepth 1 -type l" "${runbook}"
require_text 'refusing SSH teardown with symlinked configuration fragments:' "${runbook}"
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
require_text 'UsePAM no' "${runbook}"
require_text 'Revoke the managed authorization material after authenticating its state.' "${runbook}"
require_text 'An OpenSSH 10 sshd-auth child accepted before the reload can still complete' "${runbook}"
require_text "active_sshd_auth_children=\$(ps -eo pid=,user=,comm=,args= |" "${runbook}"
require_text "\$2 == \"root\" && \$3 == \"sshd-auth\"" "${runbook}"
require_text "sshd_auth_drain_attempt=\$((sshd_auth_drain_attempt + 1))" "${runbook}"
require_text 'refusing teardown while OpenSSH pre-authentication children remain' "${runbook}"
require_text "active_sshd_sessions=\$(ps -eo pid=,user=,comm=,args= |" "${runbook}"
require_text "\$3 == \"sshd\" || \$3 == \"sshd-session\"" "${runbook}"
require_text "index(\$0, \"sshd-session: \" user \" [priv]\")" "${runbook}"
require_text "index(\$0, \"sshd-session: \" user \"@\")" "${runbook}"
require_text "index(\$0, \"sshd-session: \" user \" at \")" "${runbook}"
require_text "index(\$0, \"sshd: \" user \" [priv]\")" \
  "${runbook}"
require_text 'refusing teardown while %s has active SSH session processes' "${runbook}"
require_text 'When PAM is enabled, retain logind as an independent, broader check.' "${runbook}"
require_text "active_sessions=\$(loginctl list-sessions --no-legend |" "${runbook}"
require_text "refusing teardown while %s has active SSH sessions" \
  "${runbook}"
require_text 'sshd -t' "${runbook}"
require_text "if path_exists_or_is_symlink \"\$home/.ssh\"; then rmdir -- \"\$home/.ssh\"; fi" \
  "${runbook}"
require_text "! getent passwd \"\$user\" && ! getent group \"\$group\"" "${runbook}"
require_text 'state=/usr/local/libexec/hermes-agent/.codex-hermes-mcp-state.json' "${runbook}"
require_text 'if state.get("phase") != "active":' "${runbook}"
require_text 'lifecycle identity is incomplete' "${runbook}"
require_text 'unexpected lifecycle authorized_keys path' "${runbook}"
require_text "/usr/bin/sudo -n -u \"\$user\" /bin/sh -ceu" "${runbook}"
require_text "\"\$user:\$group:600\"" "${runbook}"
require_text "\"\$user:\$group:700\"" "${runbook}"
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
teardown_pre_auth_drain_line=$(rg -n --fixed-strings 'active_sshd_auth_children=$(ps -eo pid=,user=,comm=,args= |' "${runbook}" | cut -d: -f1)
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

if (( teardown_primary_gid_check_line >= teardown_dropin_match_line || teardown_dropin_match_line >= teardown_dropin_wrapper_line || teardown_dropin_wrapper_line >= teardown_sudoers_user_line || teardown_sudoers_user_line >= teardown_sudoers_wrapper_line || teardown_sudoers_wrapper_line >= teardown_deny_line || teardown_deny_line >= teardown_deny_publish_line || teardown_deny_publish_line >= teardown_deny_validate_line || teardown_deny_validate_line >= teardown_deny_reload_line || teardown_deny_reload_line >= teardown_deny_effective_line || teardown_deny_effective_line >= teardown_keys_line || teardown_keys_line >= teardown_pre_auth_drain_line || teardown_pre_auth_drain_line >= teardown_activity_check_line || teardown_activity_check_line >= teardown_skeleton_line || teardown_skeleton_line >= teardown_artifacts_line || teardown_artifacts_line >= teardown_reload_line || teardown_reload_line >= teardown_deny_remove_line || teardown_deny_remove_line >= teardown_final_validate_line || teardown_final_validate_line >= teardown_final_reload_line || teardown_final_reload_line >= teardown_state_line )); then
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

require_text 'piserv_hermes_delegation_mcp_ssh_state_path:' "${group_variables}"
require_text '.codex-hermes-delegation-mcp-state.json' "${group_variables}"
require_text 'piserv_hermes_delegation_mcp_ssh_trusted_preceding_match_configs:' \
  "${group_variables}"
for toolset in delegation file memory session_search skills terminal todo; do
  require_text "  - ${toolset}" "${group_variables}"
done
require_text 'Configure restricted SSH access to Hermes delegation' "${playbook}"
require_text 'piserv_hermes_mcp_ssh_trusted_preceding_match_configs:' "${playbook}"
require_text 'if (piserv_hermes_mcp_ssh_manage | bool) else []' "${playbook}"
require_text 'piserv_hermes_delegation_mcp_native_toolsets' \
  "${delegation_adapter_template}"
require_text 'piserv_hermes_delegation_mcp_integration_toolsets' \
  "${delegation_adapter_template}"
require_text '"--toolsets"' "${delegation_adapter_template}"
require_text '"--yolo"' "${delegation_adapter_template}"
require_text 'subprocess.Popen(' "${delegation_adapter_template}"
require_text 'start_new_session=True' "${delegation_adapter_template}"
if rg --fixed-strings --quiet -- 'shell=True' "${delegation_adapter_template}"; then
  printf 'Hermes delegation must never interpolate prompts through a shell.\n' >&2
  exit 1
fi
require_text 'exec /usr/bin/systemd-run --quiet --wait --pipe --collect --service-type=exec' \
  "${delegation_wrapper_template}"
require_text '--property=NoNewPrivileges=true' "${delegation_wrapper_template}"
require_text '--property=ProtectSystem=strict' "${delegation_wrapper_template}"
require_text 'BindReadOnlyPaths=' "${delegation_wrapper_template}"
require_text 'MemoryMax={{ piserv_hermes_delegation_mcp_memory_max_bytes }}' \
  "${delegation_wrapper_template}"
require_text 'LimitAS={{ piserv_hermes_delegation_mcp_limit_as_bytes }}' \
  "${delegation_wrapper_template}"
require_text 'InaccessiblePaths={{ hermes_agent_home_assistant_mcp_token_env_file | quote }}' \
  "${delegation_wrapper_template}"
require_text 'UnsetEnvironment={{ hermes_agent_home_assistant_mcp_token_env_var }}' \
  "${delegation_wrapper_template}"
if rg --fixed-strings --quiet \
  'EnvironmentFile={{ hermes_agent_home_assistant_mcp_token_env_file | quote }}' \
  "${delegation_wrapper_template}"; then
  printf 'Delegated Hermes must not inherit the Home Assistant bearer token.\n' >&2
  exit 1
fi
require_text 'piserv_hermes_delegation_mcp_config_path' \
  "${delegation_wrapper_template}"
require_text "'memory': {'write_approval': false}" "${delegation_config_template}"
require_text "'skills': {'write_approval': false}" "${delegation_config_template}"
require_text "['env', 'headers', 'url']" "${delegation_config_template}"
require_text "['dashboard', 'mcp_servers']" "${delegation_config_template}"
require_text "difference(piserv_hermes_delegation_mcp_native_toolsets) | sort" \
  "${delegation_config_template}"
require_text "'platform_toolsets'" "${delegation_config_template}"
require_text 'forward_frame' "${delegation_broker_template}"
require_text 'MAX_FRAME_BYTES' "${delegation_broker_template}"
require_text '_bounded_frames' "${delegation_broker_template}"
require_text 'DynamicUser=yes' "${delegation_broker_wrapper_template}"
require_text 'EnvironmentFile={{ hermes_agent_home_assistant_mcp_token_env_file | quote }}' \
  "${delegation_broker_wrapper_template}"
require_text 'NOPASSWD: {{ piserv_hermes_delegation_mcp_broker_wrapper_path }} ""' \
  "${delegation_broker_sudoers_template}"
require_text '## Operator Acceptance Matrix' "${delegation_runbook}"
require_text '| Exact target state |' "${delegation_runbook}"
require_text '| Configured target forwarding |' "${delegation_runbook}"
require_text '| Source-scoped tool call |' "${delegation_runbook}"
require_text '| Sibling-entity negative |' "${delegation_runbook}"
require_text '| Unreachable-dependency negative |' "${delegation_runbook}"
require_multiline_text 'The hardened broker
deployment requires the matrix above' "${delegation_runbook}"

ansible-playbook --inventory localhost, --connection local \
  "${repository_root}/ansible/tests/test-hermes-mcp-ssh-templates.yml" >/dev/null
ansible-playbook --inventory localhost, --connection local \
  "${repository_root}/ansible/tests/test-hermes-delegation-mcp-templates.yml" \
  >/dev/null
ansible-playbook --inventory localhost, --connection local \
  "${repository_root}/ansible/tests/test-hermes-delegation-mcp-validation.yml" \
  >/dev/null
ansible-playbook --inventory localhost, --connection local --check \
  "${repository_root}/ansible/tests/test-hermes-delegation-mcp-fresh-check-mode.yml" \
  >/dev/null
ansible-playbook --inventory localhost, --connection local \
  "${repository_root}/ansible/tests/test-hermes-mcp-ssh-shared-topology.yml" \
  >/dev/null
ansible-playbook --inventory localhost, --connection local \
  "${repository_root}/ansible/tests/test-hermes-mcp-ssh-primary-gid-users.yml" \
  >/dev/null
ansible-playbook --inventory localhost, --connection local \
  "${repository_root}/ansible/tests/test-hermes-mcp-ssh-path-authentication.yml" \
  >/dev/null

ansible-playbook --inventory localhost, --connection local --check \
  "${repository_root}/ansible/tests/test-hermes-mcp-ssh-templates.yml" >/dev/null

printf 'HERMES_MCP_SSH_POLICY_OK\n'
