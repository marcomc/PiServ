# Mobile-Readable Upgrade Email Research

## Finding

The supplied Gmail mobile screenshot confirms that the current unattended-upgrades
message makes the package-manager transcript the primary content. This is useful
for diagnosis but makes the outcome and any required action difficult to scan.

`unattended-upgrades` retains its full operational and `dpkg` logs in
`/var/log/unattended-upgrades/` and provides a plugin interface for custom result
handling. Its documented mail settings control the recipient and reporting mode,
not a presentation template. This supports a separate concise notification while
preserving the authoritative host log. [Upstream documentation](https://github.com/mvo5/unattended-upgrades/blob/master/README.md#plugin-support)

## Recommended Direction

| Rank | Option | Recommendation |
| --- | --- | --- |
| 1 | HTML digest with plain-text alternative | Use a custom result handler to send a short, mobile-first outcome and restrict native mail to errors. Keep the full log on PiServ; include a bounded error excerpt or a `.log` attachment only on failure. |
| 2 | Plain-text digest | Smaller implementation, robust across all clients, but less visually scannable than HTML. |
| 3 | Native `only-on-error` reporting | Reduces noise but removes successful-upgrade visibility; use only if routine confirmations are not useful. |

The preferred pattern is **alert, then drill-down**: one screen of outcome and
action, with technical detail available separately. Use `multipart/alternative`
with a concise `text/plain` part first and the HTML representation last. MIME
defines these parts as alternative versions of the same information and instructs
senders to order them from the plainest to the richest format. [RFC 2046, section 5.1.4](https://www.rfc-editor.org/rfc/rfc2046.html#section-5.1.4)

## Proposed Content

**Subject:** `[PiServ] Upgrade complete: 3 packages; no reboot required`

```text
Upgrade complete
16 Jul 2026, 06:19 CEST

At a glance
- Status: completed
- Packages upgraded: 3
- Reboot: not required
- Errors: none

Changed packages
- libntfs-3g89t64  1:2022.10.3-5+deb13u1 -> 1:2022.10.3-5+deb13u2
- libxfont2        <previous version> -> <installed version>
- ntfs-3g          1:2022.10.3-5+deb13u1 -> 1:2022.10.3-5+deb13u2
- <new package>    new -> <installed version>

Technical detail
Full log retained on PiServ: /var/log/unattended-upgrades/
```

The custom handler should obtain the version pairs from the package-manager
transaction record, rather than presenting only the plugin's package-name list.
Show `previous -> installed` for upgrades and `new -> installed` for newly
installed dependencies. Do not show a removed package as an upgrade; list it
separately as `removed: <previous version>`.

## Live Validation

On 2026-07-16, PiServ was running `unattended-upgrades 2.12`. Its installed
`/usr/bin/unattended-upgrade` includes the `PluginDataPostrun` plugin API and
the `packages_upgraded` and `log_dpkg` result fields. The plugin directories
are defined by the upstream program. The PiServ plugin is now installed at
`/etc/unattended-upgrades/plugins/UnattendedUpgradesPluginPiServMail.py`.

This command confirmed that `/var/log/apt/history.log` contains the exact
version transitions needed for the digest:

```sh
ssh admin@piserv.local 'sudo tail -n 30 /var/log/apt/history.log'
```

The 06:19 unattended run recorded:

```text
ntfs-3g:arm64 (1:2022.10.3-5+deb13u1, 1:2022.10.3-5+deb13u2)
libntfs-3g89t64:arm64 (1:2022.10.3-5+deb13u1, 1:2022.10.3-5+deb13u2)
libxfont2:arm64 (1:2.0.6-1+b3, 1:2.0.6-1+deb13u1)
```

The current implementation retains upstream native mail as an error-only
fallback, so an unexpected top-level failure cannot become silent. That fallback
remains verbose; a future custom failure wrapper should lead with `Upgrade
requires attention`, the failed package or command, and the required operator
action. Do not rely on a red or green status alone: status words are required in
addition to colour. Normal-sized text should have at least a 4.5:1 contrast
ratio. [WCAG use of color](https://www.w3.org/WAI/WCAG22/Understanding/use-of-color.html) [WCAG contrast](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html)

Use one responsive, single-column layout; avoid wide tables and unbroken log
lines in the HTML body. WCAG reflow targets readable vertical content at an
equivalent width of 320 CSS pixels without two-dimensional scrolling. Gmail
supports inline style blocks and screen-width media queries, making this practical
for the client shown in the screenshot. [WCAG reflow](https://www.w3.org/WAI/WCAG22/Understanding/reflow.html) [Gmail CSS support](https://developers.google.com/workspace/gmail/design/css)

## Implementation Status

On 2026-07-16, the PiServ base playbook installed the custom plugin and set
native `Unattended-Upgrade::MailReport` to `only-on-error` to prevent duplicate
routine raw mail while retaining an unexpected-failure fallback.
`unattended-upgrade --dry-run --debug` passed after the change. A real success
digest using the recorded July package transitions was delivered through the
root alias. Local behavior tests cover successful changes, no-op suppression,
and held-package alerts. The plugin deliberately does not send failure mail:
native error-only mail handles that path. Inspect the delivered message in Gmail
mobile before relying on the next scheduled upgrade as the final visual
confirmation.
