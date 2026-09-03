# 05 — Usage (daily operation)

Everything you can do with the fan-control setup after install. All commands
need root (`sudo`).

## Monitoring

```bash
# One live sample: CPU temp, CPU fan %, RPM | GPU temp, GPU fan %, RPM
sudo isw -r 1

# Continuous: N samples, one per second
sudo isw -r 10

# Combined system view (thermal zones + GPU + EC) — helper script
./scripts/monitor.sh 10
```

Quick manual readings:

```bash
cat /sys/class/thermal/thermal_zone3/temp    # CPU package, millidegrees
nvidia-smi --query-gpu=temperature.gpu,utilization.gpu --format=csv
```

## Re-applying the profile (manual)

The EC forgets everything on reboot — the systemd service re-applies it
automatically. To force it manually:

```bash
sudo isw -cw 17C6EMS1
```

## Cooler Boost (max fans)

Same as the MSI Dragon Center button (EC register 0x98 ≥ 128):

```bash
sudo isw -b on
sudo isw -b off
```

Useful before gaming or heavy encodes. It's loud — that's the point.

## Battery charge threshold

Limits charging to N % (20–100). Good for battery longevity if the laptop
mostly sits plugged in. **The EC remembers this across reboots** (it does NOT
need the boot service):

```bash
sudo isw -t 80     # stop charging at 80 %
sudo isw -t 100    # back to full
```

## USB backlight

```bash
sudo isw -u off | half | full
```

## Single EC register writes (advanced)

```bash
sudo isw -s 0x98 128    # address in hex, value in decimal
```

Only for experiments — see `06-ec-register-map.md` for the map.

## Editing the fan curve

The active curve for our machine is in `/etc/isw.conf`, section `[17C6EMS1]`:

```ini
[17C6EMS1]
address_profile = MSI_ADDRESS_DEFAULT
fan_mode = 140            # 140=Advanced, 76=Basic, 12=Auto
cpu_temp_0 = 50           # °C thresholds
cpu_fan_speed_0 = 0       # % duty at/below cpu_temp_0
...
```

Logic (per point): if realtime temp is above `cpu_temp_N`, apply
`cpu_fan_speed_(N+1)`. GPU works the same way.

To tune:

1. Edit `/etc/isw.conf` (backup first: `sudo cp /etc/isw.conf /etc/isw.conf.bak`).
2. Apply: `sudo isw -cw 17C6EMS1`.
3. Watch: `sudo isw -r 5`.

Current values (as deployed):

| | CPU | GPU |
|---|---|---|
| Temp thresholds (°C) | 50 / 56 / 62 / 68 / 74 / 80 | 55 / 60 / 65 / 70 / 75 / 80 |
| Fan duty (%) | 0 / 40 / 48 / 56 / 64 / 72 / 80 | 0 / 53 / 59 / 65 / 71 / 77 / 83 |

So at ~80 °C the CPU fan is at 80 %, the GPU fan at 83 %. The EC temp
(register 0x68) typically reads a few degrees below the `x86_pkg_temp` DTS
sensor, so the curve "bottoms out" around 74–79 °C under load — matching
what we measured.

## Services

```bash
systemctl status isw@17C6EMS1    # inactive (dead) = success (oneshot!)
systemctl restart isw@17C6EMS1   # re-apply curve without reboot
systemctl disable isw@17C6EMS1   # stop applying at boot (fans revert to factory)
```

## Housekeeping

- After a kernel upgrade, `ec_sys` may need re-loading: the `modules-load.d`
  entry handles it at boot, but a live system needs
  `sudo modprobe ec_sys write_support=1` again.
- Keep `/etc/isw.conf` in sync with this repo's copy if you edit the curve —
  `cp /etc/isw.conf ~/projects/msi-gl73-8se/artifacts/isw.conf.as-installed`.