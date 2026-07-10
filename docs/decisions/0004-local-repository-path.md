# 0004: Local Repository Path

## Status

Accepted on 2026-07-07.

## Context

Tooling and future agent sessions need a durable project-level instruction so
downloads, generated files, and validation commands land in the canonical repo.

## Decision

Use this as the canonical local path:

```text
$HOME/Development/RaspberryPi/PiServ
```

Use the canonical path for commands, downloads, generated files, and
documentation updates.

## Consequences

- Future agents should use the canonical path as the workspace path.
- Downloaded upstream resources belong under the active `PiServ` repository.
