# 0013: VNC Uses the Physical Touchscreen Output

## Status

Accepted and implemented on 2026-07-14.

## Context

PiServ runs the Raspberry Pi OS Wayland desktop with two outputs:

- `DSI-1`: the attached 800x480 Freenove touchscreen.
- `HDMI-A-1`: a USB HDMI capture adapter used by the display stack.

The Raspberry Pi OS `wayvnc` service attached to the active `admin` Wayland
session but captured the first output, `HDMI-A-1`, by default. This made VNC
show a different screen from the physical touchscreen.

## Decision

Keep the Raspberry Pi OS `wayvnc` startup path unchanged. Manage a PiServ-owned
oneshot service that runs after `wayvnc-control.service`, selects `DSI-1`
through the control socket, and exits. Assert that `DSI-1` is the active
captured output.

## Consequences

- VNC clients see the same desktop output shown on the physical touchscreen.
- VNC remains a system service and keeps the existing authentication and
  firewall policy.
- The selector runs after either vendor VNC service starts or restarts.
- The selector unit must be reapplied if Raspberry Pi OS changes its VNC
  control-service integration.
- The output name is hardware-specific and must be revalidated if the display
  is replaced.

## Validation

Before automation, the live control command switched the running server:

```sh
sudo wayvncctl -S /tmp/wayvnc/wayvncctl.sock output-set DSI-1
```

The running Wayland session reported both `HDMI-A-1` and `DSI-1`. The deployed
wrapper left `HDMI-A-1` active despite its `--output DSI-1` argument and an
early control-socket loop made WayVNC restart handling unstable. Both were
removed.

On 2026-07-14, the vendor `wayvnc` 0.9.1-1+rpt5 startup path was observed to
exit with `SIGSEGV` during manual restart diagnostics. Systemd eventually
recovered the service, but one diagnostic sequence included multiple failed
restarts. No core dump was retained. A subsequent PiServ selector service
completed successfully and made `DSI-1` active without replacing the vendor
`ExecStart` command.
