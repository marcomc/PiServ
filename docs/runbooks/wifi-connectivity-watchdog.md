# Wi-Fi Connectivity Watchdog

## Purpose

The local `wifi_watchdog` role installs `piserv-wifi-watchdog.service` for the
`wlan0` connection used by PiServ. It checks the Wi-Fi link, the active default
gateway, and DNS before starting recovery.

## Recovery policy

1. After five minutes offline, restart the configured NetworkManager connection.
2. After ten minutes offline, restart NetworkManager if the connection restart
   did not restore connectivity.
3. Host reboot is disabled by default. Set
   `wifi_watchdog_reboot_after_seconds` to a positive value only after the
   lower escalation levels have been observed in production.

The watchdog resets its timer as soon as all three checks pass. Recovery events
are written to the system journal with the `piserv-wifi-watchdog` identifier.

## Configuration

PiServ configures the reusable role in
`ansible/playbooks/wifi-watchdog.yml`. The generic role is documented in
[`ansible/roles/wifi_watchdog/README.md`](../../ansible/roles/wifi_watchdog/README.md).

| Variable | Default |
| --- | --- |
| `wifi_watchdog_interface` | `wlan0` |
| `wifi_watchdog_connection` | empty; NetworkManager selects an eligible saved profile |
| `wifi_watchdog_gateway_probe` | IPv4 default gateway on `wifi_watchdog_interface` |
| `wifi_watchdog_dns_probe` | `example.com` |
| `wifi_watchdog_reboot_after_seconds` | `0` |

## Validation

Apply and verify the dedicated playbook:

```bash
ansible-playbook ansible/playbooks/wifi-watchdog.yml
systemctl status piserv-wifi-watchdog.service
journalctl -u piserv-wifi-watchdog.service -f
```

Observed on PiServ: the service is enabled and active after application. A
converged `ansible-playbook --check` reports `changed=0`.

Do not simulate a failure by disconnecting the production host until an
operator has confirmed an alternate access path.
