# 03 — Architecture (how the fix works)

## The Embedded Controller (EC)

MSI laptops (like most modern laptops) delegate all fan and power management to
a small microcontroller — the Embedded Controller. It has its own memory map
(RAM at I/O ports `0x62`/`0x66`) holding, among other things:

- fan mode (Auto / Basic / Advanced)
- fan curves: temp thresholds + matching fan duty values
- real-time temps and fan speeds (the "sensors" that hwmon never exposes)
- cooler boost state, battery charge threshold, USB backlight

The OS talks to the EC through ACPI. On Windows, MSI's Dragon Center writes
these registers; on Linux nothing does by default — that's why the fans
follow the factory curve forever.

## Data flow

```
                user                 kernel                  hardware
   sudo isw -cw 17C6EMS1
        │
        ▼
      isw (python3)  ──read/write──►  /sys/kernel/debug/ec/ec0/io
        │                              (ec_sys module, write_support=1)
        │                                      │
        │                              ACPI Embedded Controller (EC)
        │                                      │
        │                              fan PWM / RPM, thermistors, etc.
```

`/sys/kernel/debug/ec/ec0/io` is a byte-addressable window into EC memory;
isw reads/writes it with a documented register map (`06-ec-register-map.md`).

## Components

### `ec_sys` (kernel module)

Exposes the EC address space at `/sys/kernel/debug/ec/ec0/io`. With the
`write_support=1` parameter it becomes writable.

- Config: `/etc/modprobe.d/ec_sys.conf` → `options ec_sys write_support=1`
- Auto-load: `/etc/modules-load.d/ec_sys.conf` → `ec_sys`
- **Security gate:** `write_support` is an "unsafe" module parameter; it is
  refused when kernel lockdown ≥ integrity. Ubuntu 26 forces integrity mode
  when Secure Boot is enabled (`CONFIG_LOCK_DOWN_IN_SECURE_BOOT=y`) — so
  Secure Boot had to be turned off (`07-security.md`).

### `isw` (Ice-Sealed Wyvern) — userspace

Single Python3 script (`isw/isw` in this folder, installed to `/usr/bin/isw`).

- `/etc/isw.conf` — profile database, one section per EC firmware version,
  plus `[MSI_ADDRESS_DEFAULT]` defining the register map.
- We use section `[17C6EMS1]` (GL73 8RC/8RD, GP73 8RD):
  - `fan_mode = 140` (Advanced; 76 = Basic, 12 = Auto)
  - CPU curve: temps 50/56/62/68/74/80 °C → fans 0/40/48/56/64/72/80 %
  - GPU curve: temps 55/60/65/70/75/80 °C → fans 0/53/59/65/71/77/83 %
- `isw -cw 17C6EMS1` writes the whole section into the EC (the `-c` flag
  forces the section even though our firmware string is `17C7EMS1`, not
  `17C6EMS1`).

### systemd service

`/etc/systemd/system/isw@.service` — templated unit:

```ini
[Service]
ExecStartPre=/usr/bin/sleep 2
ExecStart=/usr/bin/isw -w %I
Type=oneshot
```

- `systemctl enable --now isw@17C6EMS1` → applies the profile at every boot
  (the EC **resets to factory defaults on reboot**, so this re-application is
  mandatory, not optional).
- `%I` = the section name = `17C6EMS1`.
- Type `oneshot` means the service exits after writing; `systemctl status`
  shows `inactive (dead)` after success — **that is normal**, `failed` is not.

## Why not the alternatives?

| Approach | Result |
|---|---|
| In-tree `msi-ec` kernel driver | Rejects this board (`EOPNOTSUPP` — firmware `17C7EMS1.104` not in its config table; no force param in mainline) |
| `msi-fan-control` / `FrostCenter` / `MsiController` | Target newer boards (2020+); no GL73 profile; FrostCenter has MS-17C6 but not MS-17C7, and all depend on the same EC-write mechanism anyway |
| hwmon/pwmconfig | Nothing exposed — MSI EC isn't a Super-I/O chip |

## Why is this safe?

- The registers written are the same ones MSI's own tools write on Windows,
  and the map was verified 1:1 against a dump of *this* machine's EC
  (`06-ec-register-map.md`).
- Fan duty values are clamped 0–100; the EC itself validates/clamps values.
- If anything looks wrong, a reboot restores factory state (the EC is
  volatile RAM).