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

Keep the system `wayvnc` service and manage a PiServ-owned startup wrapper and
systemd drop-in that select `DSI-1` with `wayvnc --output DSI-1`.

## Consequences

- VNC clients see the same desktop output shown on the physical touchscreen.
- VNC remains a system service and keeps the existing authentication and
  firewall policy.
- The wrapper must be reapplied if Raspberry Pi OS changes its VNC service
  integration.
- The output name is hardware-specific and must be revalidated if the display
  is replaced.

## Validation

Before automation, the live control command switched the running server:

```sh
sudo wayvncctl -S /tmp/wayvnc/wayvncctl.sock output-set DSI-1
```

The running Wayland session reported both `HDMI-A-1` and `DSI-1`, and the
PiServ base playbook now validates that the running `wayvnc` command line
contains `--output DSI-1`.
