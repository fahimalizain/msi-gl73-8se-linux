# 02 — Diagnosis (the full investigation)

A step-by-step record of how we found the root cause, with every reading we
took. Original session date: 2026-09-03.

## 1. Initial symptom

User reported the laptop running hot. First readings:

```
acpitz (mobo):        85 °C
pch_cannonlake:       64 °C
iwlwifi_1:            66 °C
x86_pkg_temp (CPU):   92 °C     <-- hot
```

Notably, the **load average was only ~1.1 with 97.5 % CPU idle** — the machine
was essentially idle and still at 92 °C. That rules out "you're just gaming".

## 2. What was actually using CPU

```
PID   %CPU  COMMAND
1088371 88.0 opencode      <- the AI agent session, one core pegged
931256  13.3 rustdesk      <- remote desktop (also does GPU video encoding)
1088157  5.8 ptyxis        <- terminal
```

One fully-loaded core on a 12-thread CPU explains a load average of ~1, but a
single core *shouldn't* heat a package to 92 °C — which made us suspect the
cooling side.

## 3. Frequency scaling — ruled out

```
scaling_governor: powersave        (all cores)
scaling_cur_freq: ~2.7 GHz base    (cores do downclock correctly)
scaling_max_freq: 4100000          (4.1 GHz turbo)
```

No stuck boost, no misconfigured governor. The CPU was behaving normally —
while boosting one core to 4.1 GHz it still draws most of the 45 W package
budget, but this alone shouldn't produce 92 °C with fans expected to be at
high RPM.

## 4. Fans — the missing piece

- `ls /sys/class/hwmon/*/fan*_input` → **nothing**. No fan sensors exposed.
- No `msi-ec` driver loaded; no fan control driver of any kind.
- `dmesg` → nothing fan-related.

Without any fan speed feedback, the suspicion grew that the EC was running
fans on its factory-conservative curve.

## 5. msi-ec kernel driver — tried, rejected

The in-tree `msi-ec` driver (present in kernel 7.0, `/lib/modules/.../msi-ec.ko`)
was the natural first choice:

```
$ sudo modprobe msi-ec
modprobe: ERROR: could not insert 'msi_ec': Operation not supported
```

That error (`-EOPNOTSUPP`) comes from `load_configuration()` in the driver:
it reads the EC firmware version and rejects the device if that version isn't
in its config table. We checked both mainline and upstream
(`BeardOverflow/msi-ec`) config tables: **neither contains 17C7EMS1** (and the
mainline driver has no `force` parameter, unlike the upstream tree). Dead end —
the GL73 is simply older than everything the modern driver supports.

## 6. ec_sys — blocked by kernel lockdown

`ec_sys` is the classic back door: it exposes the EC address space through
debugfs (`/sys/kernel/debug/ec/ec0/io`), and with `write_support=1` you can
write registers directly. But:

```
$ sudo modprobe ec_sys write_support=1
modprobe: ERROR: could not insert 'ec_sys': Operation not permitted

$ cat /sys/kernel/security/lockdown
none [integrity] confidentiality

$ sudo dmesg | tail
Lockdown: modprobe: unsafe module parameters is restricted
```

**Root cause found:** Ubuntu 26 kernels run with lockdown in *integrity* mode.
`write_support` is marked an unsafe module parameter and is refused under
lockdown. And lockdown is forced because:

```
CONFIG_LOCK_DOWN_IN_SECURE_BOOT=y   <- in /boot/config-7.0.0-30-generic
mokutil --sb-state                  -> SecureBoot enabled
```

Secure Boot was ON → kernel hard-enables lockdown at boot → no EC writes.
(Details & tradeoffs: `07-security.md`.)

## 7. Confirmation — the EC dump

After disabling Secure Boot and loading `ec_sys write_support=1`, we dumped
the EC (see `artifacts/ec-dump-before.txt`). The story was written right
there in the registers:

| Register | Value | Meaning |
|---|---|---|
| 0xF4 | `0x0c` = 12 | **Fan mode = Auto** (12 = Auto, 76 = Basic, 140 = Advanced) |
| 0x68 | `0x56` = 86 °C | Real-time CPU temp |
| 0x71 | `0x42` = 66 % | CPU fan duty — only 66 % at 86 °C |
| 0x6A–0x6F | 50, 56, 62, 70, 78, 86 | CPU temp thresholds (factory) |
| 0x73–0x78 | 40, 48, 56, 66, 76, 86 | CPU fan speeds (factory) — **too weak, ramps too late** |
| 0x82–0x87 | 55, 60, 65, 70, 75, 80 | GPU temp thresholds |
| 0x8B–0x90 | 45, 50, 55, 62, 70, 78 | GPU fan speeds (factory) |
| 0xA0–0xAC | `17C7EMS1.104` | EC firmware string |

The factory curve spins the CPU fan at only **66 % at 86 °C** — in Auto mode
the EC is simply too timid, which is exactly the symptom.

The dump also confirmed the register map matches the GL73 (17C6EMS1) profile:
threshold/fan-speed registers align 1:1, so applying that profile is safe.

## 8. Root causes (summary)

1. **Primary:** EC fan curve too weak + fan mode stuck at `Auto` (12). The EC
   only reached 66 % fan at 86 °C CPU.
2. **Contributing:** idle GPU at ~69 °C (rustdesk encoding) heating the shared
   heat pipes, inflating the ACPI zone.
3. **Enabling:** Secure Boot → kernel lockdown → EC writes impossible (blocked
   the fix until disabled).
4. **By the way:** the opencode AI session pegging one core at ~90 % was the
   only real load present.

## 9. Fix & verification

Applied the GL73 profile: `sudo isw -cw 17C6EMS1` (fan mode → 140
"Advanced", CPU curve 0/40/48/56/64/72/80 %, GPU curve 0/53/59/65/71/77/83 %).

**Before → After (30 s):**

| Metric | Before | After |
|---|---|---|
| x86_pkg_temp | 94 °C | **76 °C** |
| CPU fan | 66 % | 72–80 % (3.2–4.7k RPM) |
| GPU fan | 50 % | 59–65 % (3.5–3.9k RPM) |
| EC CPU temp | 86 °C | 74–79 °C |

Fans audibly spin up and the package sheds ~18 °C. Persisted via
`isw@17C6EMS1.service` for every boot.