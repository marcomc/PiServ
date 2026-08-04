# Wi-Fi Connectivity Watchdog

## Purpose

The local `wifi_watchdog` role installs `piserv-wifi-watchdog.service` for the
`wlan0` connection used by PiServ. It checks the Wi-Fi link, the active default
gateway, and DNS before starting recovery. PiServ also checks public IPv4
reachability without an interface binding before considering a host reboot.

## Recovery policy

1. After five minutes offline, restart the configured NetworkManager connection.
2. After ten minutes offline, restart NetworkManager if the connection restart
   did not restore connectivity.
3. After fifteen minutes with no route to either configured public probe, reboot
   the host. A healthy route through any interface prevents this escalation.

The Wi-Fi recovery timer resets as soon as link, gateway, and DNS pass through
`wlan0`. The reboot timer resets as soon as either public IP responds through
any host route. Before each automatic reboot, the service requires the live
kernel reboot mode to still be `cold`. Recovery events are written to the
system journal with the `wifi-connectivity-watchdog` identifier. A failed
connection activation or NetworkManager restart is retried on later checks
while the outage continues, without blocking a higher recovery level whose
threshold has elapsed. A successful NetworkManager restart enables another
connection recovery attempt until health checks pass.

## Configuration

PiServ configures the reusable role in
`ansible/playbooks/wifi-watchdog.yml`. The generic role is documented in
[`ansible/roles/wifi_watchdog/README.md`](../../ansible/roles/wifi_watchdog/README.md).

| Variable | Default |
| --- | --- |
| `wifi_watchdog_interface` | `wlan0` |
| `wifi_watchdog_connection` | `piserv_wifi_watchdog_connection` from ignored local vars |
| `wifi_watchdog_gateway_probe` | IPv4 default gateway on `wifi_watchdog_interface` |
| `wifi_watchdog_dns_probe` | `example.com` |
| `wifi_watchdog_reboot_after_seconds` | `900` |
| `wifi_watchdog_internet_probe_addresses` | `1.1.1.1`, `8.8.8.8` |
| `wifi_watchdog_required_reboot_mode` | `cold` |

Before applying the playbook, copy
`ansible/vars/wifi-watchdog.yml.example` to the ignored
`ansible/vars/wifi-watchdog.yml` and set `piserv_wifi_watchdog_connection` to
the saved NetworkManager profile. The playbook fails before host changes when
the value is empty.

## Validation

Apply and verify the dedicated playbook:

```bash
ansible-playbook ansible/playbooks/wifi-watchdog.yml
ssh -o BatchMode=yes admin@PiServ.local 'sudo -n systemctl status piserv-wifi-watchdog.service'
ssh -t -o BatchMode=yes admin@PiServ.local 'sudo -n journalctl -u piserv-wifi-watchdog.service -f'
```

Observed on PiServ: the service is enabled and active after application. A
converged `ansible-playbook --check` reports `changed=0`.

Do not simulate a failure by disconnecting the production host until an
operator has confirmed an alternate access path. With an alternate path, prove
that a Wi-Fi-only outage does not reboot while another route reaches either
public probe, then prove the automatic reboot only under a controlled total
internet outage.
