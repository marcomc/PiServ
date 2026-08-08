# Raspberry Pi 5 Intermittent Reboot Failure Research

## Scope

This report investigates PiServ shutdowns where `systemctl reboot` completes
userspace teardown but the Raspberry Pi 5 does not visibly restart. The host
uses a Freenove FNK0100K case, an NVMe root filesystem, an external USB SSD,
Debian 13 `trixie`, kernels `6.18.34+rpt-rpi-2712` and
`6.18.39+rpt-rpi-2712`, and bootloader EEPROM `2026-05-26`.

Research date: 2026-08-01. Sources are restricted to Raspberry Pi, Linux,
systemd, and Freenove primary sources and first-party issue reports.

## Executive Finding

The available evidence does **not** identify the Freenove cleanup failure,
Plymouth SIGSEGV, `reboot=w`, or a shutdown overlay as the deterministic root
cause.

The leading hypothesis is an intermittent failure after persistent logging has
stopped: either the Pi 5 warm-reset request does not complete, or reset occurs
but the bootloader cannot re-establish a required PCIe, NVMe, USB, or power
state. Those two cases are indistinguishable without UART output spanning the
kernel-to-bootloader transition.

A controlled warm-reset series reproduced the symptom on attempt 3: attempts 1
and 2 restarted, while attempt 3 stayed off. Including two preceding controlled
warm resets, the observed result is four successful warm resets out of five.
After physical recovery, five one-shot cold resets all succeeded. This is useful
directional evidence, but the sample is too small to estimate failure rates or
attribute causality.

Kernel `6.18.39` was then installed with the previous kernel and a complete boot
partition archive retained for rollback. Nine of ten controlled warm resets
succeeded; the tenth again completed shutdown and stayed off. The newer kernel
therefore does not resolve the defect.

The external USB SSD and its USB bridge were then physically disconnected. Five
warm resets succeeded and the sixth stayed off. The external SSD is therefore
not required to reproduce the failure.

`reboot=w` is the Raspberry Pi 5 kernel DTB default, not a PiServ-specific
workaround. PiServ has no workload that requires retained warm-reset state, and
its full reboots are limited to kernel, firmware, boot configuration, or host
maintenance changes. Based on five successful cold resets and repeated warm
failures, the selected operational mitigation is a managed final `reboot=c`
kernel token with a stable pre-policy backup and a `default` rollback mode.
This changes the production reset path but does not prove the underlying cause.

The managed policy was applied on 2026-08-01. Its activation reboot used a
one-shot cold selection, followed by three reboots driven only by the persistent
`reboot=c` token. All four returned in 33-40 seconds with the kernel reporting
`cold`, NVMe root and boot mounts intact, no failed systemd units, and the
Freenove service active. Combined with the five earlier one-shot tests, the
observed cold-reset result is nine successes out of nine attempts.

## Proven Live Facts

| Observation | Result | Consequence |
| --- | --- | --- |
| Failed shutdown progress | Reached `systemd-shutdown`; storage and swap were unmounted; journal stopped | Failure is later than normal service teardown |
| Freenove cleanup | One controlled reboot succeeded with cleanup bypassed; another succeeded with patched cleanup | Cleanup is not a deterministic root cause |
| Plymouth | The same SIGSEGV occurred on successful and failed reboots | SIGSEGV is a defect, but not sufficient to cause this symptom |
| Historical reproduction baseline | Successes and failures used kernel `6.18.34`, EEPROM `2026-05-26`, and `reboot=w` | None of these facts alone predicted failure |
| Warm-reset tests | Four of five controlled warm resets succeeded; the fifth completed shutdown but stayed off | Reproduces an intermittent failure without a deterministic userspace correlate |
| Historical reset support | PSCI 1.1 reported `SYSTEM_RESET2`; active test mode was `warm` | Kernel could request the Pi 5 warm-reset path |
| Cold-reset tests | Five one-shot and four managed-policy cold resets succeeded in 27-40 seconds | Nine of nine observed cold resets returned without physical intervention |
| Shutdown overlays | No live `gpio-poweroff` or `gpio-shutdown` node/overlay | These overlays are eliminated for the observed configuration |
| Bootloader policy | No `POWER_OFF_ON_HALT` or `WAIT_FOR_POWER_BUTTON` override | Default halt policy is in use |
| Kernel update | `6.18.39` booted successfully, but only nine of ten warm resets returned | The newer kernel does not resolve the defect |
| External USB SSD | Physically absent for six warm-reset attempts; attempt 6 stayed off | The external SSD is not the root cause |
| Operational policy | PiServ selects a final `reboot=c` token through the base role; repeat convergence reports `changed=0` | Cold reset is deployed as the reversible production mitigation while root cause remains open |

## Primary-Source Reset Path

The Raspberry Pi `rpi-6.18.y` Pi 5 device tree appends `reboot=w` to the kernel
command line [in `bcm2712-rpi.dtsi`][pi5-dtb]. The Linux reboot parser maps `w`
to `REBOOT_WARM` and exposes warm/cold mode selection [in `kernel/reboot.c`][linux-reboot].

On arm64, the restart path invokes registered restart handlers
[from `machine_restart()`][arm64-restart]. The PSCI handler uses
`SYSTEM_RESET2` for warm or soft mode when firmware reports support; otherwise
it uses `SYSTEM_RESET` [in the PSCI driver][psci-reset]. The BCM watchdog driver
also registers a full-reset handler that ignores the selected reboot mode
[in `bcm2835_wdt.c`][bcm-watchdog].

This establishes what Linux requests, but not which stage failed on PiServ.
The journal ending after `systemd-shutdown` is expected: systemd performs final
cleanup and then calls the reboot operation [in `shutdown.c`][systemd-shutdown].
A userspace service failure can delay or complicate teardown, but once this
path has reached the final reboot call, neither a prior Freenove exception nor
Plymouth's earlier SIGSEGV proves that it prevented hardware reset.

The official `gpio-poweroff` overlay documentation warns that it interferes
with normal reset and that reboot changes its GPIO state
[in the overlay reference][gpio-poweroff]. That warning is relevant generally,
but the overlay is absent on PiServ. Similarly, `POWER_OFF_ON_HALT` and
`WAIT_FOR_POWER_BUTTON` are bootloader halt policies, not documented reboot
repairs [in the Raspberry Pi power documentation][pi-power].

## Freenove Evidence

Freenove's current `task_manager.py` SIGTERM handler calls a nonexistent
`stop_all_tasks()` method [in the official source][freenove-handler], while the
implemented cleanup method is `stop_monitoring()`
[later in the same source][freenove-cleanup]. This explains the observed
cleanup exception and justifies the local patch.

The FNK0100 API exposes an I2C `power_on_check` register
[in `api_expansion.py`][freenove-api], but Freenove does not document that the
SIGTERM exception converts an OS reboot into power-off. The controlled success
with cleanup bypassed and the success with normal patched cleanup reject that
exception as a deterministic trigger. A separate case-controller or physical
power-path interaction remains possible, but is currently only a hypothesis.

## Related First-Party Reports

| Report | Direct evidence | Applicability and limit |
| --- | --- | --- |
| [Pi 5 does not reboot, Linux #7121][linux-7121] | Pi 5 can boot from hard power but fail or take a long time after reboot; Raspberry Pi maintainer requests serial logs | Closest symptom, unresolved, different hardware details |
| [Second PCIe boot fails, EEPROM #718][eeprom-718] | UART shows NVMe present after power-on reset but PCIe timeout/no NVMe after reboot | Strong evidence for warm-reset PCIe/NVMe state sensitivity; not the same NVMe hardware |
| [Pi 5 reboot error, EEPROM #798][eeprom-798] | Cold boot worked while reboot failed with an NVMe HAT; final cause was a physical HAT power contact | Proves power-path faults can be reboot-specific; does not implicate FNK0100 |
| [WD SN5100 PCIe link down, EEPROM #859][eeprom-859] | Same kernel `6.18.34` and EEPROM `2026-05-26`; bootloader NVMe probing leaves the kernel PCIe link down | Confirms current-version PCIe handoff defects exist; different drive and failure stage |

These reports support prioritising UART and PCIe/NVMe evidence. They do not
prove that PiServ's bootloader started after the failed reset, nor that its NVMe
was absent.

## Update Assessment

| Component | Available state | Relevant primary-source change | Assessment |
| --- | --- | --- | --- |
| Kernel | `6.18.39` installed; `6.18.34` retained | The range includes a generic arm64 cpufreq hotplug/suspend reboot race fix [commit `6e175c0`][cpufreq-fix] | Nine of ten warm resets returned; the update does not resolve this defect |
| EEPROM | Packaged default is `2026-05-26` and live EEPROM is current | Newer upstream test builds are listed, but their notes contain no matching Pi 5 warm-reset/NVMe fix [in release notes][eeprom-notes] | Do not switch release channels solely for this symptom |
| Device tree | Candidate kernel still contains `reboot=w` | Warm reset remains Raspberry Pi's selected Pi 5 default [in Pi 5 DTB source][pi5-dtb] | Override it with a final managed `reboot=c`; retain `default` rollback |

Upgrading to `6.18.39` is reasonable because it includes stable kernel fixes and
one generic reboot-race fix. It must be treated as an experiment, not as a
known resolution. The EEPROM release notes after the packaged default discuss
other bootloader changes, not this failure mode.

## Ranked Diagnostic Matrix

| Rank | Candidate | Evidence for | Evidence against / missing | Confidence | Decisive safe test |
| --- | --- | --- | --- | --- | --- |
| 1 | Warm reset or early bootloader PCIe/NVMe transition intermittently fails | Failure occurs after journal stops; first-party Pi 5 reports reproduce warm-only reset/NVMe failures; root is NVMe | No UART capture from a failed PiServ reboot | Medium-high | Capture UART continuously across repeated warm/cold resets |
| 2 | Peripheral or power-path state blocks reset or early boot | NVMe and FNK0100 add reset/power dependencies; issue #798 proves a reboot-specific physical power path is possible | The failure recurred with the external USB SSD physically absent; no undervoltage/overcurrent evidence | Medium | Repeat the matrix with the FNK0100 GPIO controller physically disconnected |
| 3 | Kernel-specific late reboot/device-shutdown race | `6.18.39` includes a generic arm64 cpufreq reboot-race fix | The failure recurred on the newer kernel after nine successful warm resets | Low | Retain both kernels while prioritising peripheral isolation and UART capture |
| 4 | Freenove userspace cleanup exception | Official source contains the invalid method call | Successful bypassed and patched-cleanup reboots; failed run also stopped service cleanly | Low | No further service-only testing unless failures correlate with FNK0100 hardware state |
| 5 | Plymouth SIGSEGV prevents reset | It occurs during reboot | It occurs on both successful and failed reboots; final shutdown continues past it | Very low | Repair separately, but do not use it as reboot-success evidence |
| 6 | `gpio-poweroff` or halt-policy configuration converts reboot to power-off | Official overlay can prevent normal reset | Overlay/node and relevant EEPROM overrides are absent live | Eliminated for current state | Keep an automated configuration assertion; no reboot test needed |

## Safe Test Plan

1. **Capture the missing boundary first.** Attach a Raspberry Pi Debug Probe or
   3.3 V UART adapter and retain output from the final kernel message through
   EEPROM boot. Raspberry Pi documents the Debug Probe UART connection
   [in the Debug Probe UART guide][debug-probe]. This distinguishes "reset
   request never completed" from
   "firmware restarted but PCIe/NVMe/USB boot failed".
2. **Continue monitoring the persistent cold policy.** The completed series is
   four of five initial warm resets and nine of nine cold resets. Preserve boot
   ID, kernel, `/sys/kernel/reboot/mode`, EEPROM version, USB/PCIe topology, and
   timestamp for future controlled reboots. Treat continued success as
   mitigation evidence, not proof of root cause.
3. **Collect post-boot evidence consistently.** For every return collect
   previous-boot journal, `vclog -m`, boot ID, NVMe identity/link information,
   and USB topology. For a failure, preserve the UART transcript before manual
   power-on.
4. **Retain the kernel comparison evidence.** Kernel `6.18.39` is installed,
   `6.18.34` remains installed, and the boot partition was archived before the
   change. The warm-reset failure recurred on attempt 10. Do not combine further
   kernel tests with EEPROM-channel changes.
5. **Continue non-root peripheral isolation.** The failure recurred on warm
   attempt 6 with the external USB SSD physically disconnected. In a separate
   maintenance run, disconnect the FNK0100 GPIO controller without changing
   the NVMe root path. This is a reversible isolation test; do not disconnect
   the NVMe root device during this phase.
6. **Only if evidence points to NVMe reset, test an alternate boot path.** Boot
   a temporary SD installation while leaving the NVMe visible but unused, then
   repeat warm resets. This separates bootloader/reset reliability from the
   NVMe root dependency without modifying NVMe contents.

Do not enable `gpio-poweroff`, invent `POWER_OFF_ON_REBOOT`, or change EEPROM
release channels while validating cold mode. Each would combine another reset
mechanism with the selected mitigation and weaken the evidence.

## Conclusion

The Freenove source defect is real but is no longer the primary reboot
suspect. Plymouth is also non-discriminating. The evidence currently ends at
the exact point where Linux hands control to reset firmware, and Raspberry Pi's
own issue history shows intermittent warm-reboot failures can arise from both
reset handling and PCIe/NVMe power/link reinitialisation.

PiServ now uses a managed cold-reset override because it has no requirement for
warm-reset state and all nine observed cold resets returned while warm mode
failed intermittently. Four of those cold resets validated the deployed policy,
including three driven only by its persistent kernel token. The external USB
SSD has been excluded as a necessary trigger. UART capture or hardware
isolation remains the next diagnostic step if cold mode also fails; until then,
the mitigation can be operated independently from the still-open root cause.

[arm64-restart]: https://github.com/raspberrypi/linux/blob/rpi-6.18.y/arch/arm64/kernel/process.c#L119-L138
[bcm-watchdog]: https://github.com/raspberrypi/linux/blob/rpi-6.18.y/drivers/watchdog/bcm2835_wdt.c#L105-L139
[cpufreq-fix]: https://github.com/raspberrypi/linux/commit/6e175c00c62d
[debug-probe]: https://www.raspberrypi.com/documentation/microcontrollers/debug-probe.html#uart-serial-bus
[eeprom-718]: https://github.com/raspberrypi/rpi-eeprom/issues/718
[eeprom-798]: https://github.com/raspberrypi/rpi-eeprom/issues/798
[eeprom-859]: https://github.com/raspberrypi/rpi-eeprom/issues/859
[eeprom-notes]: https://github.com/raspberrypi/rpi-eeprom/blob/master/firmware-2712/release-notes.md
[freenove-api]: https://github.com/Freenove/Freenove_Computer_Case_Kit_for_Raspberry_Pi/blob/cc6851f8911c0cfbab824cefb28604f7268766df/Code/api_expansion.py#L50-L75
[freenove-cleanup]: https://github.com/Freenove/Freenove_Computer_Case_Kit_for_Raspberry_Pi/blob/cc6851f8911c0cfbab824cefb28604f7268766df/Code/task_manager.py#L314-L328
[freenove-handler]: https://github.com/Freenove/Freenove_Computer_Case_Kit_for_Raspberry_Pi/blob/cc6851f8911c0cfbab824cefb28604f7268766df/Code/task_manager.py#L73-L76
[gpio-poweroff]: https://github.com/raspberrypi/firmware/blob/master/boot/overlays/README#L1590-L1617
[linux-7121]: https://github.com/raspberrypi/linux/issues/7121
[linux-reboot]: https://github.com/raspberrypi/linux/blob/rpi-6.18.y/kernel/reboot.c#L1031-L1115
[pi-power]: https://www.raspberrypi.com/documentation/computers/raspberry-pi.html#power-button
[pi5-dtb]: https://github.com/raspberrypi/linux/blob/rpi-6.18.y/arch/arm64/boot/dts/broadcom/bcm2712-rpi.dtsi#L105-L110
[psci-reset]: https://github.com/raspberrypi/linux/blob/rpi-6.18.y/drivers/firmware/psci/psci.c#L290-L309
[systemd-shutdown]: https://github.com/systemd/systemd/blob/v257/src/shutdown/shutdown.c#L550-L620
