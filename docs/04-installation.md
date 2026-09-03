# 04 — Installation (from scratch)

Everything below is what was actually done on this machine, in order.
Automated version: `sudo ./scripts/setup.sh` (idempotent).

Prereqs: Ubuntu with kernel ≥ 6.x (any recent distro works), internet, and
**Secure Boot disabled** (see step 0 — do it first, the kernel lockout can't
be bypassed in software on Ubuntu 26 kernels).

## Step 0 — Disable Secure Boot (required, once)

1. Reboot, mash `DEL` during POST to enter MSI Click BIOS.
2. `Settings` → `Security` → `Secure Boot` → `Disabled`.
3. Save & exit. Boot back into Ubuntu.
4. Verify: `cat /sys/kernel/security/lockdown` should show `[none]`.

> If Secure Boot stays on, `modprobe ec_sys write_support=1` fails with
> `Operation not permitted` (lockdown refuses "unsafe" module parameters).
> See `07-security.md`.

## Step 1 — Get the software

```bash
mkdir -p ~/projects/msi-gl73-8se
git clone https://github.com/YoyPa/isw.git ~/projects/msi-gl73-8se/isw
```

## Step 2 — Enable EC writes

```bash
echo "options ec_sys write_support=1" | sudo tee /etc/modprobe.d/ec_sys.conf
echo ec_sys | sudo tee /etc/modules-load.d/ec_sys.conf
sudo modprobe ec_sys write_support=1
```

Verify it loaded and debugfs works:

```bash
lsmod | grep ec_sys
sudo cat /sys/kernel/debug/ec/ec0/io | head -c 64
```

## Step 3 — Install isw

```bash
sudo install -m 0755 ~/projects/msi-gl73-8se/isw/isw /usr/bin/isw
sudo install -m 0644 ~/projects/msi-gl73-8se/isw/etc/isw.conf /etc/isw.conf
sudo install -m 0644 ~/projects/msi-gl73-8se/isw/usr/lib/systemd/system/isw@.service /etc/systemd/system/isw@.service
```

> Note: install to `/usr/bin/isw`, NOT `/usr/local/bin` — the systemd unit
> hardcodes `/usr/bin/isw`. (We learned this the hard way: status 203/EXEC —
> see `08-troubleshooting.md`.)

## Step 4 — Safety dump (recommended, once)

Before writing anything, snapshot the EC state so it can be compared later
(or restored manually):

```bash
sudo isw -c | tee ~/projects/msi-gl73-8se/artifacts/ec-dump-before.txt
```

## Step 5 — Apply the GL73 profile

```bash
sudo isw -cw 17C6EMS1
```

You'll see the curve values it wrote (CPU fans 0/40/48/56/64/72/80, GPU fans
0/53/59/65/71/77/83). Fans should become audible immediately.

## Step 6 — Verify

```bash
sudo isw -r 5        # 5 samples: CPU/GPU temp, fan %, RPM
cat /sys/class/thermal/thermal_zone3/temp   # x86_pkg_temp (millidegrees)
```

Expected: CPU fan ≥ 70 % under load, package temp dropping toward 76–80 °C.

## Step 7 — Persist at boot

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now isw@17C6EMS1
sudo systemctl status isw@17C6EMS1   # "inactive (dead)" = success (oneshot)
```

The EC resets to factory defaults on every reboot, so this service is what
makes the fix permanent. The kernel config files from Step 2 make `ec_sys`
auto-load with write support at boot as well.

## Step 8 — Optional niceties

```bash
# Battery charge limit (stop charging at 80 % — EC remembers it across reboots)
sudo isw -t 80

# Cooler Boost toggle anytime
sudo isw -b on      # or: off
```

## Verification checklist

- [ ] `cat /sys/kernel/security/lockdown` → `[none] ...`
- [ ] `lsmod | grep ec_sys` → loaded
- [ ] `sudo isw -cw 17C6EMS1` → writes without error
- [ ] `sudo isw -r 1` → plausible RPM (3–5k under load) and temps
- [ ] `systemctl is-enabled isw@17C6EMS1` → enabled
- [ ] Reboot test: fans spin up on their own within ~5 s of login