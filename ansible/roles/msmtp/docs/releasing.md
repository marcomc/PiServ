# Releasing

## Purpose

Publish the msmtp role to Ansible Galaxy from a standalone public role
repository.

## Publication Facts

| Fact | Value | Status |
| --- | --- | --- |
| Galaxy namespace | `marcomc` | Assumed |
| Galaxy role name | `msmtp` | Set in metadata |
| Source role path | `/path/to/ansible/roles/msmtp/` | Example |
| Standalone repo name | `msmtp` | Assumed |
| Default branch | `main` | Assumed |
| Initial version | `0.1.0` | Assumed |
| License | MIT | Role-level license |
| Minimum Ansible version | `2.15` | Role metadata |
| Upstream inspiration | `Fauch922/ansible-msmtp-setup` at `ad915e0a2162bf1fa7b77211f1392a8bc879c94b` | Documented |

## Export Role

Galaxy imports standalone roles from a public GitHub repository whose root is
the role root. Export this subrole into a standalone repository before import.

Example:

```sh
src="/path/to/ansible/roles/msmtp"
dst="/path/to/msmtp"

mkdir -p "$dst"
rsync -a --delete \
  --exclude '.git/' \
  "$src"/ "$dst"/
```

## Preflight

Run from the standalone role repository:

```sh
markdownlint --config "$HOME/.markdownlint.json" README.md CHANGELOG.md docs/*.md
sed -e 's#{{ msmtp_config_path }}#/etc/msmtprc#g' \
  -e 's#{{ msmtp_binary_path }}#/usr/bin/msmtp#g' \
  templates/msmtp-system.sh.j2 | shellcheck --enable=all -s sh -
ansible-playbook --syntax-check tests/test.yml
ansible-lint .
rg -n 'password|secret|token|private-email' . --glob '!docs/releasing.md'
```

## Release

Create and push a SemVer tag from the standalone public repository:

```sh
git tag -a v0.1.0 -m "Release v0.1.0"
git push origin main
git push origin v0.1.0
```

Import the role into Ansible Galaxy:

```sh
ansible-galaxy role import marcomc msmtp \
  --branch main \
  --role-name msmtp \
  --token "$ANSIBLE_GALAXY_TOKEN"
```

Check import status:

```sh
ansible-galaxy role import --status marcomc msmtp \
  --token "$ANSIBLE_GALAXY_TOKEN"
```

Check published role metadata:

```sh
ansible-galaxy role info marcomc.msmtp
```

Verify pinned install:

```sh
tmp_dir="$(mktemp -d)"
ansible-galaxy role install --roles-path "$tmp_dir" marcomc.msmtp,0.1.0
rm -rf "$tmp_dir"
```
