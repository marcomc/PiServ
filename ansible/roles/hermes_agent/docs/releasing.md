# Releasing

This guide applies only after `hermes_agent` has been extracted from its current
parent repository into the planned standalone repository
`marcomc/ansible-hermes-agent`.

## Preconditions

- The extracted repository is public and its default branch is `main`.
- The role has passed live acceptance testing in its consuming project.
- `CHANGELOG.md` has a finalized `MAJOR.MINOR.PATCH` release entry.
- Ansible Galaxy credentials are available locally as `ANSIBLE_GALAXY_TOKEN`.

## Preflight

From the extracted repository root, run:

```sh
uv run --with-requirements requirements-dev.txt ansible-lint .
uv run --with-requirements requirements-dev.txt molecule test
markdownlint --config "$HOME/.markdownlint.json" README.md CHANGELOG.md docs/*.md
```

Commit and push the release contents, then create and push its matching tag:

```sh
git tag -a vX.Y.Z -m "Release X.Y.Z"
git push origin vX.Y.Z
```

## Galaxy Import

Load the token without printing it, then start and check the role import:

```sh
set -a
. ./.env
set +a
: "${ANSIBLE_GALAXY_TOKEN:?ANSIBLE_GALAXY_TOKEN must be set in .env}"

ansible-galaxy role import marcomc ansible-hermes-agent \
  --branch main \
  --role-name hermes_agent \
  --token "$ANSIBLE_GALAXY_TOKEN"
ansible-galaxy role import --status marcomc ansible-hermes-agent \
  --token "$ANSIBLE_GALAXY_TOKEN"
ansible-galaxy role info marcomc.hermes_agent
```

Verify the published tag with an empty roles directory:

```sh
roles_dir="$(mktemp -d)"
ansible-galaxy role install --roles-path "$roles_dir" \
  marcomc.hermes_agent,vX.Y.Z
rm -rf "$roles_dir"
```

If an import remains stale, first verify repository visibility, the `main`
branch, the pushed tag, and the token before retrying.
