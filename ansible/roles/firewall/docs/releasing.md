# Releasing

## Purpose

Publish the firewall role to Ansible Galaxy from a standalone public role
repository.

## Publication Facts

| Fact | Value | Status |
| --- | --- | --- |
| Galaxy namespace | `marcomc` | Assumed |
| Galaxy role name | `firewall` | Set in metadata |
| Source role path | `/path/to/ansible/roles/firewall/` | Example |
| Standalone repo name | `firewall` | Assumed |
| Default branch | `main` | Assumed |
| Initial version | `0.1.0` | Assumed |
| License | MIT | Role-level license |
| Minimum Ansible version | `2.17` | Role metadata |
| Collection dependency | `community.general >= 13.1.0` | Documented |

## Export Role

Galaxy imports standalone roles from a public GitHub repository whose root is
the role root. Export this subrole into a standalone repository before import.

Example:

```sh
src="/path/to/ansible/roles/firewall"
dst="/path/to/firewall"

mkdir -p "$dst"
rsync -a --delete \
  --exclude '.git/' \
  "$src"/ "$dst"/
```

## Preflight

Run from the standalone role repository:

```sh
markdownlint --config "$HOME/.markdownlint.json" README.md CHANGELOG.md docs/*.md
ansible-galaxy collection install community.general:13.1.0
ansible-playbook --syntax-check tests/test.yml
ansible-lint .
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
ansible-galaxy role import marcomc firewall \
  --branch main \
  --role-name firewall \
  --token "$ANSIBLE_GALAXY_TOKEN"
```

Verify the published role:

```sh
ansible-galaxy role info marcomc.firewall
```
