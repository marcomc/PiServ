# put.io CLI

## Purpose

PiServ installs the official `putio-cli` release used by the
`jackett-search --interactive` put.io actions. The CLI is built on PiServ from
the pinned source release because the upstream release assets do not include a
Linux ARM64 binary.

## Install or converge

```sh
ansible-playbook -i ansible/inventory.ini ansible/playbooks/jackett.yml \
  --limit piserv
```

The playbook installs `putio` at `/usr/local/bin/putio` for the `admin` runtime
user and then installs/converges `jackett-search`. The role does not manage
put.io authentication.

The PiServ playbook tracks the upstream `main` branch for `jackett-search` and
updates that checkout on every run; its installed version therefore follows
the upstream branch state at convergence time.

## Safe operator bootstrap

Run the login flow interactively as `admin`; never place the resulting token in
Ansible variables, shell history, logs, or this repository:

```sh
ssh admin@PiServ.local
putio auth login
putio auth status
putio files list --file-type FOLDER --parent-id 0 --page-all --output json
```

The final command is read-only and confirms the folder-discovery contract used
by `jackett-search --interactive`. A real transfer should be tested only after
reviewing the selected folder and magnet.

## Validation

```sh
ssh admin@PiServ.local 'file /usr/local/bin/putio && putio version'
ssh admin@PiServ.local 'command -v putio'
```

Expected architecture is `ARM aarch64`; the expected CLI version is `1.6.2`.
