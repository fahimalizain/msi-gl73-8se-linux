# 08 — Troubleshooting

Every error hit during this project, plus common issues, with exact fixes.

## Errors actually encountered

### 1. `modprobe: ERROR: could not insert 'msi_ec': Operation not supported`

The in-tree `msi-ec` driver refuses this board. Its `load_configuration()`
reads the EC firmware version and returns `-EOPNOTSUPP` when the version
isn't in its config table — GL73 (17C7EMS1.104) isn't, in mainline or in the
upstream `BeardOverflow/msi-ec` tree. Mainline has no `force` parameter.

**Fix:** don't use msi-ec; use isw (`docs/04-installation.md`).

### 2. `modprobe: ERROR: could not insert 'ec_sys': Operation not permitted` + `Lockdown: unsafe module parameters is restricted`

Kernel lockdown ≥ integrity blocks `write_support` (an unsafe param).
Ubuntu 26 forces lockdown when Secure Boot is on.

**Fix:** disable Secure Boot in BIOS, reboot, verify with
`cat /sys/kernel/security/lockdown` → `[none]`. (`docs/07-security.md`)

### 3. `isw@17C6EMS1.service: Failed at step EXEC spawning /usr/bin/isw: No such file or directory` (status 203/EXEC)

The systemd unit hardcodes `/usr/bin/isw`, but isw was installed to
`/usr/local/bin/isw`.

**Fix:** `sudo install -m 0755 <repo>/isw/isw /usr/bin/isw`, then
`sudo systemctl restart isw@17C6EMS1`.

### 4. `isw@17C6EMS1.service` shows `inactive (dead)`

**This is success.** The unit is `Type=oneshot` — it applies the profile and
exits. `systemctl is-active` reports `inactive` for finished oneshots.
Only `failed` means a problem (check `journalctl -u isw@17C6EMS1`).

## General problems

### Fans quiet again after reboot

The EC resets all fan registers to factory defaults on every power cycle.

- Check the service: `systemctl status isw@17C6EMS1`
- Check module: `lsmod | grep ec_sys` (may need `sudo modprobe ec_sys
  write_support=1` after kernel updates)
- Re-apply manually: `sudo isw -cw 17C6EMS1`

### `isw` says it wrote the profile but fans don't change

1. Is `ec_sys` loaded with `write_support=1`? `cat
   /sys/kernel/debug/ec/ec0/io` must exist and be writable.
2. Is lockdown active? `cat /sys/kernel/security/lockdown` — must show
   `[none]`.
3. Verify the fan mode took: `sudo isw -p` / dump and check 0xF4 = 140.
4. Secure Boot might have been re-enabled.

### Fans ramp fine but package still hits 90+ °C

- Check what's burning CPU: `ps -eo pid,pcpu,comm --sort=-pcpu | head`
- GPU at idle should be < 65 °C; if hot, find what keeps the dGPU busy
  (`nvidia-smi` — often remote-desktop/encoding).
- Hardware aging: a 2018 laptop with an RTX 2060 may need a **repaste** and
  heatsink dusting. Fans spinning fast + package still hot = cooling system
  (paste/fins) is the limit, not the fan curve.

### Hibernation/suspend quirks

isw.conf comments note Advanced fan mode (140) works better with
suspend/hibernate than Basic. If you see odd behavior after resume, re-apply
the profile (`sudo systemctl restart isw@17C6EMS1`).

### Kernel update to a locked-down future

If a future kernel changes the lockdown behavior or `ec_sys` interface, the
symptom will be #2 again (refused `write_support`). Check
`modinfo ec_sys` and `cat /sys/kernel/security/lockdown` first.

## Safety notes

- Only write registers documented in `docs/06-ec-register-map.md`; the EC has
  no write-protection and wrong writes could misbehave.
- A reboot always restores factory EC state, so experimentation is bounded.
- The battery charge threshold (0xEF) is the one value that persists — don't
  test with it.
- `isw` runs as root and reads/writes `/sys/kernel/debug/ec/ec0/io` — treat
  the binary as trusted (it's a plain Python script; audit it in the `isw/`
  folder anytime).