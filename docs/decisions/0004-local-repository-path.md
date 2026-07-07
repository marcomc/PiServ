# 0004: Local Repository Path

## Status

Accepted on 2026-07-07.

## Context

The local repository directory was renamed from `PiServ` to `PiServ`.
Tooling and future agent sessions need a durable project-level instruction so
downloads, generated files, and validation commands land in the active repo.

## Decision

Use this as the canonical local path:

```text
$HOME/Development/RaspberryPi/PiServ
```

Treat this old path as stale:

```text
$HOME/Development/RaspberryPi/PiServ
```

Do not use the stale path for commands, downloads, generated files, or
documentation updates.

## Consequences

- Future agents should use `PiServ` as the workspace path.
- Project docs may mention `PiServ` only as historical rename context.
- Downloaded upstream resources belong under the active `PiServ` repository.
