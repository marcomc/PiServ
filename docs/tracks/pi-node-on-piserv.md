# Pi Node on PiServ Investigation

## Table of Contents

- [Result](#result)
- [How Pi Node works](#how-pi-node-works)
- [Multiple nodes and accounts](#multiple-nodes-and-accounts)
- [PiServ compatibility](#piserv-compatibility)
- [Headless Linux operation](#headless-linux-operation)
- [Recommended deployment](#recommended-deployment)
- [Validation plan](#validation-plan)
- [Sources](#sources)

## Result

Pi Node cannot currently be installed natively on PiServ through the official
Linux distribution path.

| Constraint | PiServ | Official Linux requirement | Result |
| --- | --- | --- | --- |
| Architecture | `arm64` Raspberry Pi 5 | `amd64` package and APT source | Blocking incompatibility |
| RAM | 4 GB | 4 GB | Meets minimum |
| CPU | 4-core Raspberry Pi 5 | 4 vCPUs | Meets nominal minimum; performance still needs validation |
| Primary disk | 128 GB NVMe | 150 GB minimum, ideally 300 GB | Below minimum |
| External SSD | Planned 4 TB | Could provide space for Docker volumes | Solves storage only, not architecture |
| Headless operation | SSH/systemd environment | Official `pi-node` CLI | Operationally suitable if hardware is supported |

The decisive evidence is the official APT repository: the current `pi-node`
package is `Architecture: amd64`, while the published `arm64` package index is
empty. The official instructions also explicitly add the APT source with
`arch=amd64` and recommend Ubuntu 24.04 LTS `x64`.

The separate official desktop release repository does not change this result:
its current releases publish macOS universal and Windows installers, but no
Linux ARM64 installer. macOS Apple Silicon support therefore confirms only
that Pi Network ships an ARM64 build for that desktop target; it does not imply
that the Linux CLI or its Docker node images are available for `arm64`.

## How Pi Node works

Pi Node runs the Pi blockchain components in Docker containers. The official
Linux package supplies the `pi-node` CLI, which initializes the node, manages
the containers, follows logs, reports status, and applies protocol updates.

The current Linux instructions require:

- Debian-based Linux distribution, with Ubuntu 24.04 LTS `x64` suggested.
- Docker Engine and Docker Compose v2.
- At least 150 GB of disk space, ideally 300 GB.
- 4 vCPUs and 4 GB RAM.
- A node initialization containing a node private key and PostgreSQL password.

The older Pi Node overview describes the role as participating in validation
and, for SuperNodes, consensus based on the Stellar Consensus Protocol. That
overview also contains a disclaimer that its original Testnet description may
be outdated and does not describe the current Mainnet Linux packaging. The
current Linux CLI documentation is therefore the authoritative installation
reference.

## Multiple nodes and accounts

The official Pi Node FAQ currently states that one Pi account should run only
one node and that one person is allowed one Pi account. Therefore:

| Scenario | Assessment |
| --- | --- |
| Two nodes using the same Pi account | Not supported by the published policy. Do not configure this. |
| Two nodes on the same LAN using different legitimate accounts | Not clearly documented by Pi Network. It may require distinct node identities, separate storage, and separate inbound port mappings. Treat as unverified. |
| One Pi account on PiServ plus another machine | The published policy points to one node for the account, so moving the node between machines requires a controlled migration rather than running both. |

The official documentation requires the ability to open ports on the local
router as part of node selection criteria, but the current Linux installation
page does not document a supported multi-node NAT/port-mapping configuration.
No multi-node setup should be automated until Pi Network publishes the required
port and identity behavior.

## PiServ compatibility

PiServ is a Raspberry Pi OS/Debian 13 `trixie` `arm64` host. It meets the RAM
and nominal CPU count, but fails the two hard requirements that matter most:

1. The official CLI package is not available for `arm64`.
2. The current NVMe root volume is smaller than the documented minimum disk
   requirement.

Installing the `amd64` `.deb` with `--force-architecture`, using Docker
emulation, or compiling an unofficial replacement would not be a supported
Pi Node deployment. It would also add substantial operational risk to a host
already intended to run storage, backup, and network services.

The 4 TB SSD should not be formatted or dedicated to Pi Node solely to work
around this investigation. It can later provide storage for a supported
`amd64` host or for other PiServ workloads, but it cannot make an `amd64`
package executable on the Raspberry Pi.

## Headless Linux operation

The official Linux CLI is compatible with a headless operational model after
initial operator setup:

```sh
pi-node initialize
pi-node status
pi-node logs -f
pi-node start
pi-node stop
pi-node restart
pi-node update-protocol
```

The initialization can also receive values non-interactively, including the
Pi folder, Docker volume path, node private key, PostgreSQL password, and a
`--start-node` flag. This is suitable for Ansible only after the secrets and
storage layout have been designed. The node private key must never be stored in
the repository, shell history, or unprotected logs.

## Recommended deployment

| Rank | Option | Recommendation |
| --- | --- | --- |
| 1 | Dedicated supported `amd64` Linux host on the same LAN | Preferred. Use a small x86-64 mini PC, VM, or existing server with at least 300 GB allocated storage, 4 vCPUs, and 4 GB RAM. |
| 2 | Wait for an official ARM64 Pi Node package | Best if PiServ must host the node. Monitor the official APT repository and Linux documentation. |
| 3 | Run `amd64` binaries through emulation on PiServ | Do not pursue unless Pi Network explicitly supports it and a disposable benchmark proves acceptable reliability. |

The PiServ project should track Pi Node as an external-host integration, not as
a current PiServ service. If a supported `amd64` host becomes available, PiServ
can manage its monitoring, backups, firewall documentation, and operational
checks without pretending that the Raspberry Pi is the node runtime.

## Validation plan

Before any installation is attempted:

- Confirm the target host architecture with `dpkg --print-architecture` and
  `uname -m`.
- Confirm the official APT repository publishes a package for that architecture.
- Confirm Docker Engine and Compose v2 versions on the candidate host.
- Confirm at least 300 GB of durable storage for the node data and migrations.
- Confirm router port-forwarding requirements from the current Pi Node UI or
  official support channel.
- Confirm the account-to-node policy again before moving an existing node.
- Back up the node private key and PostgreSQL credential through the project
  secret-management path before initialization.

## Sources

- [Official Pi Node overview](https://minepi.com/pi-node/)
- [Official Linux Node installation instructions](https://minepi.com/pi-blockchain/pi-node/linux/)
- [Official Linux Node release announcement](https://minepi.com/blog/pi-linux-node/)
- [Official Pi Node package repository](https://apt.minepi.com/dists/stable/Release)
- [Official Pi Node AMD64 package index](https://apt.minepi.com/dists/stable/main/binary-amd64/Packages)
- [Official Pi Node ARM64 package index](https://apt.minepi.com/dists/stable/main/binary-arm64/Packages)
- [Official Pi Node desktop releases](https://github.com/pi-node/pi-node/releases)
- [Official Pi Node status and protocol update announcement](https://minepi.com/blog/pi-day-2026/)
