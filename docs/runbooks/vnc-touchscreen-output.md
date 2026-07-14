# VNC Touchscreen Output

## Purpose

Keep VNC aligned with the desktop output shown on the physical Freenove
touchscreen.

## Current State

PiServ uses the system `wayvnc.service`, with the PiServ base role selecting
Wayland output `DSI-1`. The project wrapper is
`/usr/local/libexec/piserv-wayvnc-run`; the systemd drop-in is
`/etc/systemd/system/wayvnc.service.d/10-piserv-output.conf`.

## Verify

Run:

```sh
ssh admin@PiServ.local 'sudo systemctl is-active wayvnc.service'
ssh admin@PiServ.local 'sudo wayvncctl -S /tmp/wayvnc/wayvncctl.sock output-list'
ssh admin@PiServ.local 'sudo pgrep -a -f "[w]ayvnc .*--output DSI-1"'
```

Expected results are an active service, an output list containing `DSI-1`, and
a running `wayvnc` command line containing `--output DSI-1`.

## Apply

Reapply the project baseline:

```sh
ansible-playbook ansible/playbooks/piserv-base.yml
```

For an immediate runtime switch during diagnosis:

```sh
ssh admin@PiServ.local \
  'sudo wayvncctl -S /tmp/wayvnc/wayvncctl.sock output-set DSI-1'
```

## Recovery

If the display name changes, identify the current Wayland outputs with:

```sh
ssh admin@PiServ.local \
  'sudo -u admin env XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 wlr-randr'
```

Update `base_vnc_output` in the PiServ playbook only after confirming the
replacement output is the physical touchscreen.
