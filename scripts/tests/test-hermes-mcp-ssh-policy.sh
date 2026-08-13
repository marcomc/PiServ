#!/usr/bin/env bash
# Verify the source-level contract for the PiServ Hermes MCP SSH entry point.
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repository_root=$(cd -- "${script_dir}/../.." && pwd)
task_file="${repository_root}/ansible/tasks/hermes-mcp-ssh.yml"
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
require_text 'Normalize existing Hermes MCP SSH identity records' "${task_file}"
require_text 'Require complete Hermes runtime identity records' "${task_file}"
require_text "piserv_hermes_mcp_ssh_account_passwd_record[5] == '/bin/sh'" \
  "${task_file}"
require_text 'Define the Hermes MCP SSH lifecycle state path' "${task_file}"
require_text 'Inspect existing privileged Hermes MCP SSH artifacts before mutation' \
  "${task_file}"
require_text 'Authenticate existing privileged Hermes MCP SSH artifacts' \
  "${task_file}"
require_text 'Require lifecycle provenance before adopting Hermes MCP SSH state' \
  "${task_file}"
require_text 'Require managed markers before replacing Hermes MCP SSH artifacts' \
  "${task_file}"
require_text 'Provision Hermes MCP SSH lifecycle provenance before account mutation' \
  "${task_file}"
require_text 'Mark Hermes MCP SSH lifecycle provenance active after sudoers publication' \
  "${task_file}"
require_text 'Publish active Hermes MCP SSH lifecycle provenance' \
  "${task_file}"
require_text 'Reject administrator keys that already declare a forced command' \
  "${task_file}"
require_text 'Require plain administrator public keys for automatic MCP SSH access' \
  "${task_file}"
require_text 'mode: "0600"' "${task_file}"
require_text 'mode: "0440"' "${task_file}"
require_text 'validate: /usr/sbin/visudo -cf %s' "${task_file}"
require_text 'Authenticate privileged Hermes MCP SSH publication parents' \
  "${task_file}"
require_text 'Inspect the Hermes MCP runtime launch prerequisites' "${task_file}"
require_text 'Install SSH forced-command policy before publishing MCP keys' \
  "${task_file}"
require_text 'Validate the complete SSH daemon configuration before publishing MCP keys' \
  "${task_file}"
require_text 'Activate SSH forced-command policy before publishing MCP keys' \
  "${task_file}"
require_text 'ansible_check_mode or' "${task_file}"
require_text "piserv_hermes_mcp_ssh_runtime_passwd_record[1] != '0'" \
  "${task_file}"
require_text "piserv_hermes_mcp_ssh_runtime_group_record[1] != '0'" \
  "${task_file}"
require_text "piserv_hermes_mcp_ssh_account_passwd_record[1] != '0'" \
  "${task_file}"
require_text "piserv_hermes_mcp_ssh_account_group_record[1] != '0'" \
  "${task_file}"
require_text 'when: not ansible_check_mode' "${task_file}"
provision_line=$(rg -n --fixed-strings 'Provision Hermes MCP SSH lifecycle provenance before account mutation' "${task_file}" | cut -d: -f1)
ssh_policy_line=$(rg -n --fixed-strings 'Install SSH forced-command policy before publishing MCP keys' "${task_file}" | cut -d: -f1)
keys_line=$(rg -n --fixed-strings 'Publish restricted copies of administrator SSH public keys' "${task_file}" | cut -d: -f1)
sudoers_line=$(rg -n --fixed-strings 'Install restricted Hermes MCP SSH sudoers policy' "${task_file}" | cut -d: -f1)
active_line=$(rg -n --fixed-strings 'Publish active Hermes MCP SSH lifecycle provenance' "${task_file}" | cut -d: -f1)

if (( provision_line >= ssh_policy_line || ssh_policy_line >= keys_line || keys_line >= sudoers_line || sudoers_line >= active_line )); then
  printf 'Hermes MCP SSH publication order must be state, SSH policy, keys, sudoers, active state.\n' >&2
  exit 1
fi
require_text 'command="/usr/bin/sudo -n {{ piserv_hermes_mcp_ssh_wrapper_path }}",restrict' \
  "${keys_template}"
require_text 'Managed by Ansible: automatic administrator key copy for Hermes MCP SSH.' \
  "${keys_template}"
require_text 'Require the automatic Hermes MCP SSH authorized keys marker' \
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
require_text 'For a failed pre-lifecycle deployment or an intentional teardown,' "${runbook}"
require_text 'rm -rf -- /var/lib/codex-hermes-mcp' "${runbook}"
require_text "before a clean apply or \`piserv_hermes_mcp_ssh_manage: false\` is used." \
  "${runbook}"
require_multiline_text 'Do not substitute a successful tool-list response for any matrix row. Do not
test destructive actions or an entity whose restoration is uncertain.' "${runbook}"

if rg --fixed-strings --quiet -- 'NOPASSWD: ALL' "${sudoers_template}"; then
  printf 'The Hermes MCP SSH sudoers policy must not grant NOPASSWD: ALL.\n' >&2
  exit 1
fi

ansible-playbook --inventory localhost, --connection local \
  "${repository_root}/ansible/tests/test-hermes-mcp-ssh-templates.yml" >/dev/null

printf 'HERMES_MCP_SSH_POLICY_OK\n'
