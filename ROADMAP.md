# PiServ Roadmap

## Table of Contents

- [Purpose](#purpose)
- [Planning Model](#planning-model)
- [0.5.0 Hermes Smart Home](#050-hermes-smart-home)
- [Later Releases](#later-releases)
- [Unscheduled Work](#unscheduled-work)
- [Release Gates](#release-gates)

## Purpose

This file describes release-sized outcomes and their ordering. It is not a
second TODO list: executable tasks remain in [TODO.md](TODO.md), while shipped
work is recorded in [CHANGELOG.md](CHANGELOG.md).

## Planning Model

| Artifact | Responsibility |
| --- | --- |
| `TODO.md` | Open, actionable work and deferred propositions |
| `ROADMAP.md` | Release milestones, scope, non-goals, and entry/exit conditions |
| `CHANGELOG.md` | Implemented changes in released versions |
| `docs/tracks/` | Research and implementation detail for a workstream |

## 0.5.0 Hermes Smart Home

**Status:** Complete

**Outcome:** Hermes can inspect and operate an explicitly approved smart-home
surface through Home Assistant, while Apple Home remains part of the same
operational picture where the platform permits it.

### Scope

1. Revalidate the existing Hermes to Home Assistant MCP path after backup
   restore, including authentication, discovery, reads, reversible writes,
   timeout handling, and audit evidence.
2. Define the Home Assistant Assist exposure policy for the desired operation
   surface. Hermes has activity-scoped autonomy; physical security actions
   remain confirmation-gated.
3. Validate Home Assistant HomeKit Bridge for the selected entities and verify
   the resulting state in Apple Home and Siri.
4. Run a bounded feasibility test for Apple Home-only entities. HomeKit Bridge
   normally exposes Home Assistant entities to Apple Home; it does not make
   Apple Home-only entities visible to Home Assistant. Direct Apple Home access
   therefore needs a separate bridge such as HomeClaw.
5. Use HomeClaw locally as a read-only observer during an explicitly started
   acceptance test. Direct HomeClaw control through SSH or Supergateway remains
   a later release decision.
6. Install and validate `homeassistant-cli` on PiServ against the same private
   token and Home Assistant server used by Hermes. Use it as the full REST and
   WebSocket control path; keep the Assist MCP available as a secondary path.

### Non-goals

- Extracting `hermes_agent` into an Ansible Galaxy role.
- PiServ reliability experiments and unrelated future service workflows.
- Full HomeClaw automation, unless the feasibility test proves it is required
  for the Apple Home-only entities.
- Repeated Hermes dependency work without a qualifying upstream release or a
  new security finding.

### Current Implementation

The acceptance harness is implemented in
[`scripts/verify-hermes-home-apple-home.py`](scripts/verify-hermes-home-apple-home.py)
with the procedure documented in
[`docs/runbooks/hermes-home-apple-home.md`](docs/runbooks/hermes-home-apple-home.md).
The acceptance run passed before and after a Hermes dashboard restart on
2026-08-08. The backup/import proof, Assist policy review, Apple Home-only
observation, and manual Siri control check also passed. Advanced climate
controls remain a separate allowlisted MCP-extension proposition. The PiServ
Home Assistant CLI is installed and validated against the same authenticated
Home Assistant API token used by Hermes. It is the primary full-control entry
point, while the Assist MCP remains a secondary limited observer/control path.

## Later Releases

### 0.6.0 Candidate Themes

- Extract and publish the reusable `hermes_agent` role after its interface is
  stable and independent CI is restored.
- Complete the selected HomeClaw transport and its authenticated write path if
  it was deferred from 0.5.0.
- Select one storage, backup, or service proposition for a bounded release.

## Unscheduled Work

The remaining reliability, storage, Google Drive, GitHub backup, Jackett,
torrent/VPN, Pi Node, camera, and administration proposals stay in `TODO.md`
until they receive a release scope.

## Release Gates

Work moves from this roadmap into `TODO.md` only when it has an ownerable
implementation slice. A release is ready for changelog entry when its stated
outcome has live or reproducible validation, documentation, and rollback or
failure behavior where applicable.

The Hermes dependency audit is reopened only when a new upstream Hermes release
is selected, the release carries `undici >= 6.28.0`, or a new security finding
requires earlier action. Otherwise it remains deferred and should not be
reintroduced as a recurring 0.5.0 task.
