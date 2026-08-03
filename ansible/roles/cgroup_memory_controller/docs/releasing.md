# Releasing

## Purpose

Publish the cgroup_memory_controller role to Ansible Galaxy from a standalone
public role repository.

## Publication Facts

| Fact | Value | Status |
| --- | --- | --- |
| Galaxy namespace | `marcomc` | Set in metadata |
| Galaxy role name | `cgroup_memory_controller` | Set in metadata |
| Source role path | `/path/to/ansible/roles/cgroup_memory_controller/` | Example |
| Standalone repository name | `ansible-cgroup-memory-controller` | Assumed |
| Default branch | `main` | Assumed |
| Initial version | `0.1.0` | Unreleased |
| License | MIT | Role-level license |
| Minimum Ansible version | `2.15` | Role metadata |

## Export Role

Galaxy imports standalone roles from a public GitHub repository whose root is
the role root. Export this subrole into a standalone repository before import.

```sh
src="/path/to/ansible/roles/cgroup_memory_controller"
dst="/path/to/ansible-cgroup-memory-controller"

mkdir -p "$dst"
rsync -a --delete \
  --exclude '.git/' \
  "$src"/ "$dst"/
```

## Preflight

Run from the standalone role repository:

```sh
markdownlint --config "$HOME/.markdownlint.json" README.md CHANGELOG.md docs/*.md
role_root=$(pwd)
tmp_dir=$(mktemp -d)
mkdir -p "$tmp_dir/roles"
ln -s "$role_root" "$tmp_dir/roles/cgroup_memory_controller"
ANSIBLE_ROLES_PATH="$tmp_dir/roles" ansible-playbook --syntax-check tests/test.yml
ANSIBLE_ROLES_PATH="$tmp_dir/roles" ansible-playbook tests/test-input-validation.yml
ANSIBLE_ROLES_PATH="$tmp_dir/roles" ansible-playbook tests/test-recovery-backup-transaction.yml
ANSIBLE_ROLES_PATH="$tmp_dir/roles" ansible-playbook --check tests/test-recovery-backup-transaction.yml
ANSIBLE_ROLES_PATH="$tmp_dir/roles" ansible-playbook tests/test-rendered-helpers.yml
ANSIBLE_ROLES_PATH="$tmp_dir/roles" ansible-playbook tests/test-disabled-role-cleanup.yml
ANSIBLE_ROLES_PATH="$tmp_dir/roles" ansible-playbook --check tests/test-disabled-role-cleanup.yml
ANSIBLE_ROLES_PATH="$tmp_dir/roles" ansible-lint .
rm -rf "$tmp_dir"
rg -n 'password|secret|token|private' . --glob '!docs/releasing.md'
```

## Release

Load the Galaxy token without printing it, then create and push a SemVer tag
from the standalone public repository:

```sh
set -a
. ./.env
set +a
: "${ANSIBLE_GALAXY_TOKEN:?ANSIBLE_GALAXY_TOKEN must be set in .env}"

git push origin main
git tag -a v0.1.0 -m "Release v0.1.0"
git push origin v0.1.0
```

Import the role into Ansible Galaxy:

```sh
ansible-galaxy role import marcomc ansible-cgroup-memory-controller \
  --branch main \
  --role-name cgroup_memory_controller \
  --token "$ANSIBLE_GALAXY_TOKEN"
```

Check import status and published metadata:

```sh
ansible-galaxy role import --status marcomc ansible-cgroup-memory-controller \
  --token "$ANSIBLE_GALAXY_TOKEN"
ansible-galaxy role info marcomc.cgroup_memory_controller
```

Verify a pinned install:

```sh
roles_dir=$(mktemp -d)
ansible-galaxy role install --roles-path "$roles_dir" \
  marcomc.cgroup_memory_controller,0.1.0
rm -rf "$roles_dir"
```

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Galaxy imports wrong files | Confirm the public repository root is the role root |
| Galaxy metadata is stale | Confirm the branch and tag are pushed before import |
| Version is absent | Confirm the tag uses `v0.1.0` or another SemVer tag |
| Token failure | Confirm `.env` was sourced and `ANSIBLE_GALAXY_TOKEN` is set |
| Role name mismatch | Confirm `meta/main.yml` and `--role-name` match |
