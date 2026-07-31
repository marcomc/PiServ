# Hermes Agent Ansible Role

## Table of Contents

- [Purpose](#purpose)
- [Security Posture](#security-posture)
- [Provider Login](#provider-login)

## Purpose

Install a pinned Nous Hermes Agent revision and checksum-pinned OpenAI Codex CLI
on Debian ARM64. The role manages an unprivileged runtime identity, persistent
state, a loopback-only dashboard, and optional scheduled backups.

## Security Posture

The default CLI allowlist contains only `memory` and `skills`. Their write paths
require operator approval. Terminal, file, browser, code execution, Home
Assistant, and all other bundled toolsets are disabled.

The dashboard binds to `127.0.0.1`. Reach it through an authenticated SSH
tunnel; do not change the bind address without first configuring dashboard
authentication and the intended firewall boundary.

## Provider Login

The role intentionally does not create credentials. Authenticate as the runtime
user after deployment:

```sh
sudo -u hermes-agent -H env \
  HERMES_HOME=/var/lib/hermes-agent \
  CODEX_HOME=/var/lib/hermes-agent/codex \
  hermes auth add openai-codex
```
