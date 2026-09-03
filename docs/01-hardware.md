# 01 — Hardware & Firmware

Identified from DMI/sysfs on the working system.

## Machine

| Field | Value | Source |
|---|---|---|
| Product name | GL73 8SE | `/sys/class/dmi/id/product_name` |
| Board name | MS-17C7 | `/sys/class/dmi/id/board_name` |
| BIOS version | E17C7IMS.106 | `/sys/class/dmi/id/bios_version` |
| EC firmware | 17C7EMS1.104 | EC dump, address 0xA0 (see `06-ec-register-map.md`) |

The GL73 8SE is the RTX-2060 variant of the GL73 family (2018). Sibling boards:

- **MS-17C6** — GL73 8RC / 8RD, GP73 8RD (GTX graphics) — **this is the isw
  profile we use: `17C6EMS1`**
- MS-17C7 — GL73 8SE / 8SF / 8SG (RTX graphics) — our board

The EC layout is identical between the two boards (verified by direct register
dump comparison — see `06-ec-register-map.md`), which is why the `17C6EMS1`
profile applies cleanly to the 8SE.

## CPU

- 12 logical CPUs (`nproc`), max frequency 4.1 GHz
  (`/sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq` = 4100000)
- Intel PCH `pch_cannonlake` thermal zone → 8th-gen Coffee Lake-H platform
  (consistent with the i7-8750H found in GL73 8SE units)
- `intel_pstate` in use; governor `powersave` (the correct default — it still
  scales frequency; "performance" is NOT needed)
- Idle clocks: all cores at base ~2.7 GHz (confirmed via
  `scaling_cur_freq`); no stuck-boost problem

## GPU

- NVIDIA GeForce RTX 2060
- Idle temperature: ~62–69 °C (warm — typical for a gaming laptop with the
  dGPU powered for rustdesk/screen recording)
- Uses shared heat pipes with the CPU → GPU heat shows up in the ACPI zone

## Thermal zones (Linux)

| Zone | Sensor | Notes |
|---|---|---|
| thermal_zone0 | `acpitz` | Motherboard/ambient; reads high (81–85 °C) because it sits near the shared heatsink area; lags the CPU |
| thermal_zone1 | `pch_cannonlake` | Chipset (59–65 °C, fine) |
| thermal_zone2 | `iwlwifi_1` | WiFi card (57–67 °C, fine) |
| thermal_zone3 | `x86_pkg_temp` | CPU package DTS — the "real" CPU temp (76–94 °C) |

There are **no hwmon fan sensors** (`hwmon*/fan*_input` = none). MSI laptops
don't expose fan speed through hwmon; fans are managed exclusively by the
Embedded Controller (see `03-architecture.md`).

## Firmware / EC summary

- EC firmware string stored at EC RAM 0xA0: `17C7EMS1.104`
- isw selects profiles by this firmware string; there is no `17C7EMS1`
  section, so we explicitly apply the sibling `17C6EMS1` section with
  `isw -cw 17C6EMS1`