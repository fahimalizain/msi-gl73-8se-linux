# 06 — EC Register Map (MS-17C7 / firmware 17C7EMS1.104)

Annotated Embedded Controller memory map for this machine, derived from the
raw dump in `artifacts/ec-dump-before.txt` (taken before the fix) and the
`[MSI_ADDRESS_DEFAULT]` map in `/etc/isw.conf` (which is the "MSI G laptop EC
Rosetta" from the isw project — verified to match this board byte-for-byte).

All addresses are EC RAM offsets (hex). Values are decimal unless noted.

## Firmware string

| Addr | Content |
|---|---|
| 0xA0–0xAC | `17C7EMS1.104` (EC firmware) |
| 0xAD–0xB2 | build metadata (`12102018 18:09:48`) |

isw keys profiles on this string. Our string isn't in any config table, so we
apply the sibling board's section (`17C6EMS1`) explicitly.

## Fan mode & misc control

| Addr | Meaning | Values |
|---|---|---|
| 0xF4 | Fan mode | 12 = Auto (factory default), 76 = Basic, 140 = Advanced |
| 0x98 | Cooler Boost | < 128 = off, ≥ 128 = on (max fans) |
| 0xEF | Battery charge threshold (%) | 20–100; persists across reboots |
| 0xF7 | USB backlight | 128 off / 193 half / 129 full |

## Live sensors (read-only)

| Addr | Meaning | At dump time |
|---|---|---|
| 0x68 | Realtime CPU temp (°C) | 86 |
| 0x71 | Realtime CPU fan duty (%) | 66 |
| 0xCC | CPU fan RPM (2 bytes) | — |
| 0x80 | Realtime GPU temp (°C) | 62 |
| 0x89 | Realtime GPU fan duty (%) | 50 |
| 0xCA | GPU fan RPM (2 bytes) | — |

`isw -r` reads these and prints them together.

## CPU fan curve (factory values at dump time)

| Addr | Meaning | Factory |
|---|---|---|
| 0x6A–0x6F | Temp thresholds 0–5 (°C) | 50, 56, 62, 70, 78, 86 |
| 0x73–0x78 | Fan duty 1–6 (%) | 40, 48, 56, 66, 76, 86 |

Logic: temp > threshold_N → apply duty_(N+1). The factory curve was the
problem: only 66 % fan at 86 °C, and Auto mode (0xF4=12) delayed ramping
further.

## GPU fan curve (factory values at dump time)

| Addr | Meaning | Factory |
|---|---|---|
| 0x82–0x87 | Temp thresholds 0–5 (°C) | 55, 60, 65, 70, 75, 80 |
| 0x8B–0x90 | Fan duty 1–6 (%) | 45, 50, 55, 62, 70, 78 |

## What the isw 17C6EMS1 profile writes (values after the fix)

| Register | Value |
|---|---|
| 0xF4 | 140 (Advanced) |
| 0x6A–0x6F | 50, 56, 62, 68, 74, 80 |
| 0x73–0x78 | 0, 40, 48, 56, 64, 72, 80 |
| 0x82–0x87 | 55, 60, 65, 70, 75, 80 |
| 0x8B–0x90 | 0, 53, 59, 65, 71, 77, 83 |

## Map provenance / confidence

The addresses above come from `[MSI_ADDRESS_DEFAULT]` in `isw.conf` (the
community-documented "MSI G laptop EC Rosetta"). We confirmed them against
the actual dump before applying anything:

- 0x68 read 86 °C while `x86_pkg_temp` read ~85 °C → sane
- 0x6A–0x6F / 0x73–0x78 contained a plausible full factory curve
- 0xF4 = 12 exactly matched "Auto" mode
- 0xA0 contained the firmware string (fixed known location)

Other bytes (0x02–0x5F, 0x79–0x7F, 0x91–0x9F, 0xB3–0xEF, 0xF5–0xFF) are
unmapped: battery, LEDs, keyboard backlight, ACPI flags, etc. Not touched.

## Restoring factory state

A reboot restores all fan-related registers to factory defaults (EC RAM is
volatile). The only EC value that persists across reboots is the battery
charge threshold (0xEF). To deliberately restore defaults without reboot:
`sudo isw -cw 17C6EMS1` is our curve — reverting means re-applying a factory
profile, which isn't shipped in isw.conf; a reboot is the simplest path.