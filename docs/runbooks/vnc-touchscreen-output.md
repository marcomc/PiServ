# VNC Touchscreen Output

## Purpose

Keep VNC aligned with the desktop output shown on the physical Freenove
touchscreen.

## Current State

PiServ keeps the Raspberry Pi OS `wayvnc.service` startup path. The PiServ
oneshot `piserv-wayvnc-output.service` runs after the vendor control service
and selects Wayland output `DSI-1` through the control socket.

## Verify

Run:

```sh
ssh admin@PiServ.local 'sudo systemctl is-active wayvnc.service'
ssh admin@PiServ.local 'sudo wayvncctl -S /tmp/wayvnc/wayvncctl.sock output-list'
ssh admin@PiServ.local 'sudo systemctl status piserv-wayvnc-output.service --no-pager'
```

Expected results are an active service, an output list whose `DSI-1` line starts
with `*`, and a successful one-shot output-selector service.

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

## Operator Access

No macOS VNC client is currently provisioned for PiServ. The selected candidate
is TigerVNC, an open-source client to validate against PiServ before adoption.

On the operator Mac, `piserv` resolves to PiServ's Tailscale hostname and
address. The direct LAN endpoints are `PiServ.local` and `192.168.1.181`.

## Direct TigerVNC Validation

Install TigerVNC on the operator Mac, then validate the direct LAN client
connection.

1. Install the cask:

   ```sh
   brew install --cask tigervnc
   ```

2. Connect TigerVNC to `192.168.1.181:5900`, then repeat with
   `PiServ.local:5900`.
3. Confirm the first-use certificate prompt matches PiServ, then authenticate
   as `admin` with the local PiServ password.
4. Confirm the displayed desktop matches the touchscreen for both direct LAN
   endpoints, then update this runbook with the validation result.

## 2026-07-14 Incident Note

The PiServ `--output DSI-1` startup wrapper did not reliably select the
touchscreen and was removed. PiServ now leaves the vendor WayVNC startup path
unchanged and uses a separate one-shot selector after `wayvnc-control.service`
starts. It completed successfully after a plain service restart and made
`DSI-1` active without an Ansible fallback command.

The PiServ service passed direct TCP and RFB banner checks from the operator
Mac:

```sh
nc -vz -w 3 192.168.1.181 5900
```

The TCP check succeeded. A separate raw RFB read returned `RFB 003.008` with
security types `19`, `129`, and `5` while `DSI-1` was active.

The previous RealVNC Viewer was removed from the operator Mac. It was
unsupported on macOS `26.5.2`, and its current third-party-server licensing
does not fit PiServ's WayVNC service. It failed at `getaddrinfo` for
`PiServ.local` and with `System-65` for the direct LAN IP, while `piserv`
completed RFB 3.8, RA2/AES-256, and PAM authentication through Tailscale.

The iPad Viewer, macOS mDNS, and direct LAN TCP all reached PiServ
successfully. Validate TigerVNC before making any further PiServ-side change.

PiServ authentication, firewall policy, and its mDNS hostname remain
unchanged. The operator confirmed that the VNC image matches the physical
touchscreen, blue fan LEDs remain on, and the other case LEDs are off.

The vendor `wayvnc` 0.9.1-1+rpt5 process exited with `SIGSEGV` during manual
restart diagnostics. Systemd eventually recovered the service, although one
diagnostic sequence included multiple failed restart attempts. No core dump was
retained. This behavior is independent of PiServ's selector.

## Vendor Update Validation

Run this only when `apt-cache policy wayvnc` shows a candidate newer than
`0.9.1-1+rpt5`. Do not repeatedly restart the current package to monitor the
known issue.

1. Apply the WayVNC update through the normal system-update path.
2. Run the following sequence three times, waiting for each iteration to
   complete:

   ```sh
   ssh admin@PiServ.local 'sudo systemctl restart wayvnc.service'
   ssh admin@PiServ.local 'sudo systemctl is-active wayvnc.service'
   ssh admin@PiServ.local \
     'sudo systemctl show wayvnc.service -p NRestarts --value'
   ssh admin@PiServ.local \
     'sudo wayvncctl -S /tmp/wayvnc/wayvncctl.sock output-list'
   ssh admin@PiServ.local 'nc -z -w 3 127.0.0.1 5900'
   ```

3. Each iteration must report `active`, `0` restarts, an active `DSI-1` output,
   and successful TCP port `5900` access. Check the matching journal interval
   contains no `SIGSEGV`:

   ```sh
   ssh admin@PiServ.local \
     'sudo journalctl -u wayvnc.service --since "10 minutes ago" --no-pager'
   ```

4. When all three iterations pass, remove the related TODO item and update this
   runbook, the decision record, and changelog with the validated version. If
   any iteration fails, retain the TODO and capture the journal evidence for an
   upstream issue.

## Recovery

If the display name changes, identify the current Wayland outputs with:

```sh
ssh admin@PiServ.local \
  'sudo -u admin env XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 wlr-randr'
```

Update `base_vnc_output` in the PiServ playbook only after confirming the
replacement output is the physical touchscreen.
