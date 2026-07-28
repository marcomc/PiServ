# Jackett Search

## Table of Contents

- [Purpose](#purpose)
- [Apply](#apply)
- [Managed Layout](#managed-layout)
- [Configure Trackers](#configure-trackers)
- [Access and Validation](#access-and-validation)
- [Validation Record](#validation-record)
- [Updates and Recovery](#updates-and-recovery)

## Purpose

Operate Jackett, its FlareSolverr companion, and the `jackett-search` CLI on
PiServ. Jackett is available to the IPv4 LAN and authenticated Tailnet clients;
it is not a public service. FlareSolverr is bound to loopback only.

## Apply

Install dependencies and deploy the stack:

```sh
ansible-galaxy role install -r ansible/requirements.yml --roles-path .ansible/roles --force
ansible-galaxy collection install -r ansible/requirements.yml --force
ansible-playbook ansible/playbooks/jackett.yml
```

If mDNS is unavailable, obtain the current DHCP lease from the operator, then
use it directly for this run only:

```sh
PISERV_IP=<operator-supplied-current-dhcp-lease>
ansible-playbook ansible/playbooks/jackett.yml -e "ansible_host=$PISERV_IP"
```

The playbook delegates installation to the local `jackett_search` role. The
role checks out the upstream project at `/opt/jackett-search` and runs, in
order, `make install`, `make install-flaresolverr`, and `make install-jackett`.
It does not maintain a project-owned Compose file or image tag. The generated
Compose files retain upstream `latest` images.
PiServ pins the upstream checkout to the `v0.2.1` release tag for reproducible
deployments. It currently resolves to
`1053269cbda9bb1d3b69d31f62e48fc100be8d61`.

PiServ adds the host-specific policy around those generated files: Jackett is
published on TCP `9117`, FlareSolverr remains loopback-only on TCP `8191`, and
Docker's `DOCKER-USER` chain permits new Jackett connections only from the
current IPv4 LAN or `tailscale0`. Docker-published ports bypass UFW's normal
input chain, so this policy is applied after every Docker start.

## Managed Layout

All persistent state belongs to the `admin` account:

| Path | Contents |
| --- | --- |
| `/opt/jackett-search` | Upstream source checkout |
| `/home/admin/.config/jackett-search/config.toml` | Private CLI configuration (`0600`) |
| `/home/admin/.config/jackett-search/flaresolverr-compose.yml` | Upstream-generated FlareSolverr Compose file |
| `/home/admin/.config/jackett-search/jackett-compose.yml` | Upstream-generated Jackett Compose file |
| `/home/admin/.config/jackett-search/jackett-config/Jackett` | Jackett credentials, indexers, and server configuration |
| `/home/admin/.config/jackett-search/jackett-downloads` | Jackett download directory |

The role reads the API key from Jackett's generated `ServerConfig.json` as a
runtime-only Ansible fact and writes it only to `admin`'s private CLI config.
The key is neither committed nor emitted in task output.

## Configure Trackers

Open PiServ's LAN hostname on TCP `9117` from the LAN. Through Tailscale, use a
PiServ-reachable LAN hostname or the Tailnet hostname/domain. Create the Jackett
administrator and tracker credentials in the web interface. They remain only in
the managed Jackett data directory and must never be committed here.

Configure FlareSolverr-backed trackers in Jackett with
`http://flaresolverr:8191`. The generated Compose projects share a private
Docker network, while TCP `8191` remains loopback-bound on PiServ.

## Access and Validation

Run on PiServ after a deployment or Docker restart:

```sh
sudo -u admin HOME=/home/admin make -C /opt/jackett-search \
  CONFIG_DIR=/home/admin/.config/jackett-search ps
sudo iptables -S DOCKER-USER
sudo iptables -S PISERV-JACKETT-SEARCH
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:9117/
sudo -u admin HOME=/home/admin /usr/local/bin/jackett-search --version
```

`DOCKER-USER` must contain its tagged DNAT TCP `9117` jump to
`PISERV-JACKETT-SEARCH`. That chain accepts new traffic from the IPv4 LAN or
`tailscale0` before its terminal drop rule. From a LAN client, verify:

```sh
curl -sS -o /dev/null -w '%{http_code}\n' http://<piserv-lan-hostname>:9117/
```

From a Tailnet client, verify the Tailnet address or hostname separately:

```sh
PISERV_TAILSCALE_IP=<piserv-tailnet-ip>
curl -sS -o /dev/null -w '%{http_code}\n' "http://${PISERV_TAILSCALE_IP}:9117/"
```

Then add a non-sensitive test indexer and verify a search through
`jackett-search`. Its managed CLI config uses `127.0.0.1:9117`, so searches
remain local to PiServ even if external DNS is unavailable. Remove a test
tracker that is not part of the intended configuration.

## Validation Record

On 2026-07-28, a converged apply and subsequent `--check` both returned
`changed=0`. The Docker `iptables-save` policy snapshot, excluding timestamp and
packet-counter noise, was identical before and after the check run. Both upstream
Compose services were up with their `latest` image tags, and `jackett-search
--version` returned `0.2.1`.

Loopback, a LAN hostname, and PiServ's Tailnet address each returned HTTP `301`
from TCP `9117`. The role's no-log authenticated API validation also passed.
Recovery tests covered both `make down` followed by the playbook and
`jackett_search_state=absent` followed by `present`; each restored both services
and preserved the private CLI configuration. End-to-end search validation remains
dependent on the operator adding tracker credentials outside Git, as tracked in
[TODO.md](../../TODO.md).

## Updates and Recovery

The upstream Compose files use `latest` image tags, which are not an automatic
image-update policy. PiServ pins the upstream source release, so force the
component installation to pull the latest Jackett image. Refresh FlareSolverr
explicitly, then repeat the access checks:

```sh
ansible-playbook -i ansible/inventory.ini ansible/playbooks/jackett.yml \
  -e jackett_search_force_component_install=true
```

```sh
sudo -u admin HOME=/home/admin docker compose \
  -f /home/admin/.config/jackett-search/flaresolverr-compose.yml pull flaresolverr
sudo -u admin HOME=/home/admin make -C /opt/jackett-search \
  CONFIG_DIR=/home/admin/.config/jackett-search up-flaresolverr
```

For failures, inspect the upstream-managed services and PiServ policy:

```sh
sudo -u admin HOME=/home/admin make -C /opt/jackett-search \
  CONFIG_DIR=/home/admin/.config/jackett-search logs
sudo systemctl status docker.service --no-pager
sudo iptables -S DOCKER-USER
sudo iptables -S PISERV-JACKETT-SEARCH
```

Do not delete `/home/admin/.config/jackett-search/jackett-config` unless
intentionally resetting all Jackett credentials and tracker state. Reapply the
playbook to restore upstream-generated files and the PiServ ingress policy.
