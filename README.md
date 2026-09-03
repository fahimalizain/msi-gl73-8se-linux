# MSI GL73 8SE — Linux Fan Control & Thermal Management

Everything about diagnosing and fixing the overheating/fan problem on this laptop
running Ubuntu 26 (kernel `7.0.0-30-generic`). This folder is the single source
of truth for the setup: documentation, the isw source, artifacts, and scripts.

## TL;DR

The laptop ran at 85–94 °C package temp with **barely audible fans**, even at
low CPU load. Root cause: the Embedded Controller (EC) fan curve was stuck in
its weak factory **Auto** curve. Fixed with the `isw` tool (Ice-Sealed Wyvern),
which writes a proper fan curve into the EC. Package temp dropped from **94 °C
to 76 °C in ~30 seconds**, with fans spinning at 3.2–4.7k RPM as expected.

**One tradeoff: Secure Boot had to be disabled** (Ubuntu 26 kernel forces
"lockdown" when Secure Boot is on, which blocks EC register writes — see
[docs/07-security.md](docs/07-security.md)).

## Quick reference

```bash
# Live CPU/GPU temp + fan speed + RPM (needs root)
sudo isw -r 5

# Re-apply the GL73 fan profile right now
sudo isw -cw 17C6EMS1

# Cooler Boost (max fans, same as MSI's Dragon Center button)
sudo isw -b on      # off to disable

# Set battery charge limit (stops charging at N%)
sudo isw -t 80

# Service state (applies profile at every boot; "inactive" = success for oneshot)
systemctl status isw@17C6EMS1
```

## Folder layout

```
msi-gl73-8se/
├── README.md                  <- this file
├── isw/                       <- upstream isw source (git clone of YoyPa/isw)
├── docs/
│   ├── 01-hardware.md         <- machine, firmware, thermal zones
│   ├── 02-diagnosis.md        <- the full investigation, data & root cause
│   ├── 03-architecture.md     <- how the solution works (EC, ec_sys, isw, systemd)
│   ├── 04-installation.md     <- from-scratch install guide
│   ├── 05-usage.md            <- daily use: monitor, curves, cooler boost, etc.
│   ├── 06-ec-register-map.md  <- annotated EC memory map from the dump
│   ├── 07-security.md         <- Secure Boot / kernel lockdown tradeoff
│   └── 08-troubleshooting.md  <- every error hit + fix
├── scripts/
│   ├── setup.sh               <- idempotent full installer (sudo)
│   └── monitor.sh             <- live temp/fan monitor
└── artifacts/
    ├── ec-dump-before.txt     <- raw EC dump taken before the fix
    ├── isw.conf.as-installed  <- /etc/isw.conf as deployed
    ├── isw@.service           <- systemd unit as deployed
    └── ec_sys.*.conf          <- kernel module configs as deployed
```

## System snapshot

| Item | Value |
|---|---|
| Product | MSI GL73 8SE (board **MS-17C7**) |
| BIOS | E17C7IMS.106 |
| EC firmware | **17C7EMS1.104** (build 2018) |
| CPU | 12 threads, up to 4.1 GHz, Cannon Lake PCH (i7-8750H class) |
| GPU | NVIDIA GeForce RTX 2060 |
| OS / kernel | Ubuntu 26, `7.0.0-30-generic` |
| Fan control | `isw` profile `17C6EMS1` (GL73 8RC/8RD — same chassis/EC) |
| Service | `isw@17C6EMS1.service` (applies curve at boot) |

## Result

| Metric | Before fix | After fix |
|---|---|---|
| Package temp (x86_pkg_temp) | 92–94 °C | **76 °C** (and stable) |
| ACPI/mobo temp | 81–85 °C | 81 °C (slow to decay) |
| CPU fan | 66 % @ 86 °C | 72–80 % @ 3.2–4.7k RPM |
| GPU fan | 50 % @ 62 °C | 59–65 % @ 3.5–3.9k RPM |
| Fan mode register (0xF4) | 12 (Auto) | 140 (Advanced) |

The EC-reported CPU temp responds immediately; the ACPI zone lags because it
measures the whole motherboard/heatsink area.

## Key lessons (also in docs/)

1. **No fan sensors in hwmon** — MSI laptops expose nothing there. Fan control
   is done through the EC, not hwmon/PWM.
2. **The in-tree `msi-ec` kernel driver won't bind** to this 2018 board
   (firmware `17C7EMS1.104` isn't in its config table → `EOPNOTSUPP`).
3. **Ubuntu 26 + Secure Boot = lockdown = no EC writes.** `ec_sys
   write_support=1` is refused with `Operation not permitted` until Secure Boot
   is disabled (kernel config `CONFIG_LOCK_DOWN_IN_SECURE_BOOT=y`).
4. **isw works by writing a complete profile** (fan curves, temps, fan mode)
   into EC registers — the register map was verified against our own EC dump
   and matches the GL73 profile exactly.

See [docs/02-diagnosis.md](docs/02-diagnosis.md) for the full story.