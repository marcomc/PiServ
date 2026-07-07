# 0001: Project Operating Model

## Status

Accepted on 2026-07-02.

## Context

PiServ is a private work-in-progress project for configuring a Raspberry Pi 5
server. The server is the production target, and the user wants live setup work
performed over SSH before codifying successful commands into automation.

## Decision

Use a production-first workflow:

1. Test setup commands directly on PiServ.
2. Document command intent, result, and validation.
3. Convert confirmed setup into Ansible playbooks or shell scripts.
4. Re-run automation against PiServ.
5. Keep runbooks and decisions current as the server evolves.

## Consequences

- Live server behavior is the source of truth.
- Automation should follow verified setup work instead of speculative design.
- Backward compatibility is not required while the project remains private.
- Documentation updates are part of each meaningful setup change.
