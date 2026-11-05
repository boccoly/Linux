# 5 — Hardening (what `harden.sh` does)

This is **not** a manual procedure. `harden.sh` applies all of it:

```sh
sudo bash scripts/harden.sh --dry-run
sudo bash scripts/harden.sh
```

This file exists so you can verify what it did, troubleshoot when something looks wrong, and know what it deliberately left alone.

## Modules

| Module | What it sets |
|---|---|
| `logindefs` | `PASS_MAX_DAYS 90`, `PASS_MIN_DAYS 7`, `PASS_WARN_AGE 14`, `UMASK 027` |
| `aging` | `chage -M 90 -m 7 -W 14` on every UID ≥ 1000 account |
| `pam` | `pam_pwquality` (minlen 14, all four credits, difok 3) + `pam_faillock` (deny 5, unlock 1800). Strips `nullok`, adds `remember=5` |
| `sysctl` | 29 parameters in `/etc/sysctl.d/99-cyberpatriot.conf` |
| `ufw` | Installs, default deny in / allow out, enables, logging on |
| `perms` | passwd/group 644, shadow/gshadow 640, sudoers 440, grub.cfg 600, `/home/*` 750 |
| `sysaccounts` | Locks system accounts (UID < 1000) that have login shells |
| `root` | `passwd -l root` |
| `apparmor` | Enables the service, sets all profiles to enforce |
| `auditd` | Installs, writes identity/scope/module watch rules, **sets halt actions to syslog** |
| `unattended` | Automatic security updates |
| `sshd` | Safe subset only, validated with `sshd -t` |
| `displaymanager` | lightdm or gdm3 — hide user list, disable guest and autologin |

## Verify it worked

```sh
grep -E '^PASS_(MAX|MIN|WARN)' /etc/login.defs
sysctl kernel.randomize_va_space net.ipv4.tcp_rfc1337
sudo ufw status verbose
ls -l /etc/shadow /etc/sudoers
grep -E 'pwquality|faillock' /etc/pam.d/common-password /etc/pam.d/common-auth
sudo aa-status | head -3
sudo auditctl -l | head -5
sudo sshd -T | grep -iE 'permitrootlogin|permitemptypasswords|maxauthtries'
```

**Test authentication immediately**, in your second terminal:

```sh
su - <normal user>
sudo -v
```

## If something breaks

```sh
sudo bash scripts/harden.sh --rollback /root/harden-backup-<timestamp>
```

Every file it touched was copied there with its full path preserved. You can also restore a single file by hand from `<backup>/files/etc/...`.

## What it deliberately does NOT do

These depend on the README, so they're yours:

- **Firewall ports.** It enables deny-by-default and opens nothing. `sudo ufw allow 22/tcp`
- **`PasswordAuthentication`, `Port`, `AllowUsers` in sshd.** Scenario-dependent; breaking them loses points.
- **Users and passwords** — `users.sh` and `2-users.md`
- **Prohibited software and media** — `recon.sh`
- **Per-service configs** — `6-services.md`
- **Updates** — `4-updates.md`
- **World-writable files, unowned files, unexpected SUID.** `recon.sh` reports these; fixing them blindly breaks things, so you review and fix individually.

## The two values worth knowing by name

`kernel.randomize_va_space = 2` (ASLR) and `net.ipv4.tcp_rfc1337 = 1` (TIME-WAIT assassination protection) both appear by name on scoring reports. Both are in the sysctl module.
