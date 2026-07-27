# Jackett Search

## Table of Contents

- [Purpose](#purpose)
- [Apply](#apply)
- [Configure Trackers](#configure-trackers)
- [Access and Validation](#access-and-validation)
- [Observed Live Deployment](#observed-live-deployment)
- [Updates and Recovery](#updates-and-recovery)

## Purpose

Operate Jackett and its FlareSolverr companion on PiServ. The API is available
only to the current IPv4 LAN and authenticated Tailnet clients; it is not a
public service.

## Apply

Install dependencies and deploy the stack:

```sh
ansible-galaxy role install -r ansible/requirements.yml --roles-path .ansible/roles --force
ansible-galaxy collection install -r ansible/requirements.yml --force
ansible-playbook ansible/playbooks/jackett.yml
```

The playbook installs Docker Compose, creates `/opt/jackett/{config,downloads}`
with `admin` ownership, and starts pinned Jackett and FlareSolverr containers.
It also installs a Docker `DOCKER-USER` policy after every Docker start. That
policy permits TCP `9117` only from the current IPv4 LAN or traffic arriving on
`tailscale0`; Docker port publishing does not use UFW's normal input chain.

## Configure Trackers

Open `http://PiServ.local:9117` from the LAN, or use PiServ's Tailscale hostname
or fully qualified Tailnet domain when connected through Tailscale. Create the
Jackett administrator credentials and tracker credentials in the web interface.
They persist only in `/opt/jackett/config` and must never be committed to this
repository.

Use the `flaresolverr` Docker hostname and port `8191` only when a configured
tracker requires it. The companion service has no published host port.

## Access and Validation

Run on PiServ after every deployment or Docker restart:

```sh
sudo docker-compose -f /opt/jackett/compose.yml ps
sudo iptables -S DOCKER-USER
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:9117/
```

The Docker policy must contain two accepts for TCP `9117` (the current IPv4 LAN
and `tailscale0`) before the matching drop rule. From a LAN client, verify:

```sh
curl -sS -o /dev/null -w '%{http_code}\n' http://PiServ.local:9117/
```

From a Tailnet client, verify the Tailscale hostname/domain resolves to PiServ
and returns an HTTP redirect or page response:

```sh
curl -sS -o /dev/null -w '%{http_code}\n' http://PISERV_TAILSCALE_DOMAIN:9117/
```

Then add a non-sensitive test indexer and verify a search through the existing
Jackett Search CLI. Remove the test tracker if it is not part of the intended
configuration.

## Observed Live Deployment

On 2026-07-27, `PiServ.local` resolution from the controller was flaky, so the
deployment used PiServ's resolved LAN IPv4 address as a temporary Ansible
override:

```sh
ansible-playbook ansible/playbooks/jackett.yml \
  -e ansible_host=<resolved-lan-ipv4>
```

The playbook completed successfully; its repeat run returned `changed=0`. Both
the local loopback request and the request from the LAN returned HTTP `301`.
The managed `PISERV-JACKETT` chain contained the current IPv4-LAN and
`tailscale0` accepts for new TCP `9117` connections, then the matching drop
rule; `DOCKER-USER` contained only its tagged jump to that chain.

A remote Tailnet-peer validation remains pending: the SSH connection used to
run it stopped at an existing host-key mismatch, not at the Jackett service or
Docker policy. Resolve that host-key state through the normal SSH verification
procedure, then rerun the Tailnet HTTP check in [Access and
Validation](#access-and-validation).

## Updates and Recovery

The images are pinned. Change an image tag in `ansible/playbooks/jackett.yml`,
review the release notes, then rerun the playbook and repeat the access checks.

For failures, inspect the containers and Docker policy:

```sh
sudo docker-compose -f /opt/jackett/compose.yml logs --tail=100
sudo systemctl status docker.service --no-pager
sudo iptables -S DOCKER-USER
```

Do not delete `/opt/jackett/config` unless intentionally resetting all Jackett
credentials and tracker state. Reapply the playbook to restore the pinned
compose definition and Docker ingress policy.
