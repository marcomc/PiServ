# Releasing

## Publication Facts

| Fact | Value | Status |
| --- | --- | --- |
| Galaxy namespace | `marcomc` | Set in metadata |
| Galaxy role name | `putio_cli` | Set in metadata |
| Standalone repository | `ansible-putio-cli` | Assumed; create before publication |
| Default branch | `main` | Assumed |
| Initial version | `0.1.0` | Unreleased |
| License | MIT | Set in metadata |

The project-local role is under `ansible/roles/putio_cli`. Galaxy import must
use a standalone repository whose root is the role root.

## Export and validate

```sh
src="/path/to/project/ansible/roles/putio_cli"
dst="/path/to/ansible-putio-cli"
mkdir -p "$dst"
rsync -a --delete --exclude '.git/' "$src"/ "$dst"/
cd "$dst"
markdownlint --config "$HOME/.markdownlint.json" README.md CHANGELOG.md docs/*.md
ansible-playbook -i tests/inventory tests/test.yml
ansible-lint .
```

Review secret-related search hits before publication. Authentication data must
not appear in the role or its examples.

## Release and Galaxy import

```sh
git tag -a v0.1.0 -m "Release v0.1.0"
git push origin main
git push origin v0.1.0
ansible-galaxy role import marcomc ansible-putio-cli \
  --branch main \
  --role-name putio_cli \
  --token "$ANSIBLE_GALAXY_TOKEN"
ansible-galaxy role install marcomc.putio_cli,0.1.0
```

Do not publish until the standalone repository owner, URL, and release version
are confirmed.
