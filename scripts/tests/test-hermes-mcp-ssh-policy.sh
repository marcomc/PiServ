#!/usr/bin/env bash
# Verify the source-level contract for the PiServ Hermes MCP SSH entry point.
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repository_root=$(cd -- "${script_dir}/../.." && pwd)
task_file="${repository_root}/ansible/tasks/hermes-mcp-ssh.yml"
wrapper_template="${repository_root}/ansible/playbooks/templates/hermes-mcp-ssh-wrapper.sh.j2"
sudoers_template="${repository_root}/ansible/playbooks/templates/hermes-mcp-ssh-sudoers.j2"
keys_template="${repository_root}/ansible/playbooks/templates/hermes-mcp-ssh-authorized_keys.j2"
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
require_text "piserv_hermes_mcp_ssh_user)[5] == '/bin/sh'" "${task_file}"
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
require_text 'Install SSH forced-command policy for the Hermes MCP account' \
  "${task_file}"
require_text 'ansible_check_mode or' "${task_file}"
require_text "piserv_hermes_mcp_ssh_user)[2] != '0'" "${task_file}"
require_text "piserv_hermes_mcp_ssh_group)[2] != '0'" "${task_file}"
require_text 'when: not ansible_check_mode' "${task_file}"
require_text 'command="/usr/bin/sudo -n {{ piserv_hermes_mcp_ssh_wrapper_path }}",restrict' \
  "${keys_template}"
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
require_text 'Match all' \
  "${repository_root}/ansible/playbooks/templates/hermes-mcp-ssh-sshd.conf.j2"
require_text 'Configure restricted SSH access to the Hermes MCP server' \
  "${playbook}"
require_text 'Reload SSH service' "${playbook}"
require_text '## Configure Codex Client' "${runbook}"
require_text 'codex mcp add hermes-piserv' "${runbook}"
require_text '## Configure Another MCP Client' "${runbook}"

if rg --fixed-strings --quiet -- 'NOPASSWD: ALL' "${sudoers_template}"; then
  printf 'The Hermes MCP SSH sudoers policy must not grant NOPASSWD: ALL.\n' >&2
  exit 1
fi

ansible-playbook --inventory localhost, --connection local \
  "${repository_root}/ansible/tests/test-hermes-mcp-ssh-templates.yml" >/dev/null

printf 'HERMES_MCP_SSH_POLICY_OK\n'
