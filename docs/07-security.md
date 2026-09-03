# 07 — Security: Secure Boot disabled & kernel lockdown

## What happened

Ubuntu 26 kernels have `CONFIG_LOCK_DOWN_IN_SECURE_BOOT=y`. When the machine
boots with **Secure Boot enabled**, the kernel automatically raises its
"lockdown" level to **integrity** at boot — regardless of anything in GRUB.
Lockdown-integrity refuses, among other things, module parameters marked
"unsafe". `ec_sys`' `write_support` is exactly such a parameter, so EC
register writes become impossible:

```
$ sudo modprobe ec_sys write_support=1
modprobe: ERROR: could not insert 'ec_sys': Operation not permitted
Lockdown: modprobe: unsafe module parameters is restricted
```

We verified there is **no software workaround** on this kernel:

- `CONFIG_LOCK_DOWN_KERNEL_FORCE_NONE=y` — but the Secure-Boot path overrides
  the cmdline anyway, so `lockdown=none` on the kernel cmdline does not help
  while Secure Boot is on.
- The `write_support` param is deliberately gated; no sysctl or debugfs
  alternative exists.
- `/dev/port` access is equally blocked under lockdown.

Therefore: **Secure Boot was disabled in the BIOS** (Settings → Security →
Secure Boot → Disabled). This is a one-time change; lockdown now stays at
`none`:

```
$ cat /sys/kernel/security/lockdown
[none] integrity confidentiality
```

## What you give up

Secure Boot verifies that everything in the boot chain (UEFI firmware →
bootloader → kernel) is signed by a trusted key, before it executes. Its job
is blocking **boot-level malware** (rootkits that hook GRUB or the kernel
early). With it off:

- The boot chain is no longer signature-checked.
- A physical attacker with access to the laptop could in principle swap GRUB
  or the kernel from a live USB / other OS.
- Some corporate security policies require it.

It does **not** protect against anything after the OS is running — user-space
malware, browser exploits, etc. are entirely unaffected by Secure Boot.

## What you keep

- Full-disk encryption (if configured) still protects your data at rest.
- Normal account passwords, firewall, updates — all unchanged.
- The kernel and modules are still the signed Ubuntu ones; nothing needs to
  be manually signed.

## If you re-enable Secure Boot later

- Everything except fan control keeps working — including msi-ec's failure
  mode (which is unrelated; it just won't bind to this board).
- The fan fix silently stops applying: `isw@17C6EMS1` will run and fail to
  write, `isw -cw 17C6EMS1` errors with the lockdown refusal. You'll notice
  fans going quiet again.
- To restore fan control, disable Secure Boot again and reboot. No other
  changes needed.

## Practical risk assessment

For a personal laptop (not a corporate-managed device), disabling Secure Boot
to gain working thermals is a common and reasonable trade. The threat model
where Secure Boot matters (targeted physical/rootkit attack) overlaps little
with the threat model most personal Linux machines actually face. Revisit the
decision if the machine becomes managed by an employer or stores very
sensitive data and is often carried around.