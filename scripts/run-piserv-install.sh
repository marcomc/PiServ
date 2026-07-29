#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/run-piserv-install.sh [ansible-playbook options]

Run the complete PiServ installation and convergence entry point.

The wrapper rejects partial-execution controls because they can bypass required
preflight and firewall ordering. Safe full-run options such as --check, --diff,
--limit, and -e are passed to ansible-playbook unchanged.
EOF
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

if [[ -n "${ANSIBLE_RUN_TAGS+x}" || -n "${ANSIBLE_SKIP_TAGS+x}" ]]; then
  fail "ANSIBLE_RUN_TAGS and ANSIBLE_SKIP_TAGS are unsupported for full PiServ convergence"
fi

for argument in "$@"; do
  case "${argument}" in
    --start-at-task | --start-at-task=* | --step | --step=* | --skip-tags | --skip-tags=* | --tags | --tags=* | -t | -t?*)
      fail "partial-execution option is unsupported for full PiServ convergence: ${argument}"
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      ;;
  esac
done

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repository_root=$(cd -- "${script_dir}/.." && pwd)
cd "${repository_root}"

exec ansible-playbook ansible/playbooks/piserv-install.yml "$@"
