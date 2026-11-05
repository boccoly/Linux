# 0 — Round flow

Two kinds of work. `harden.sh` does everything that's the same on every image. Everything else needs the README, and that's what the rest of this checklist covers.

## Order

| # | Step | Tool | Why here |
|---|---|---|---|
| 1 | README + notes | you | Everything downstream depends on it |
| 2 | Backup | `cp -a` | Your undo button |
| 3 | Forensics | `1-forensics.md` | Hardening destroys the evidence |
| 4 | Discovery | `recon.sh`, `baseline-diff.sh` | Tells you where the time goes |
| 5 | **Hardening** | **`harden.sh`** | One command, ~1 hour of manual work |
| 6 | Users | `users.sh` + `2-users.md` | Highest-scoring category |
| 7 | Updates + reboot | `4-updates.md` | Slow — start early, in the background |
| 8 | Services | `6-services.md` | Only what the image actually runs |
| 9 | Point scrounging | everything above | Where the last 15 points live |
| 10 | Final sweep | below | Verify nothing broke |

## 1 — Before you touch anything

- Read the image README twice.
- Write down: authorized **users + roles**, authorized **passwords** (if given), required **services**, required **software**, **forensics questions**.
- Open a **second root terminal** and leave it open all round. It is your way back from a bad PAM or sudoers edit.

## 2 — Backup

```sh
sudo cp -a /etc /home /root/backup-$(date +%s)
```

Thirty seconds. Do not skip it.

## 3 — Forensics

Answer every forensics question before changing anything. See `1-forensics.md`.

## 4 — Discovery

```sh
sudo bash scripts/recon.sh
sudo bash scripts/baseline-diff.sh baseline/<os>     # if you have a baseline
```

Read `SUMMARY.txt` from each, then the files it points you at.

## 5 — Hardening

```sh
sudo bash scripts/harden.sh --dry-run    # read the plan once
sudo bash scripts/harden.sh
```

Covers password policy, aging, PAM, sysctl, firewall, file permissions, system accounts, root, AppArmor, auditd, unattended-upgrades, the safe part of sshd, and the login screen.

**Then immediately, in the second terminal:**

```sh
su - <a normal user>
sudo -v
```

If either fails: `sudo bash scripts/harden.sh --rollback /root/harden-backup-<timestamp>`

Two things it leaves for you:

```sh
sudo ufw allow 22/tcp      # open only what the README requires
```

and updates, which are step 7.

## 6 — Users

```sh
cat > authorized.txt <<'EOF'
alice admin
bob   user
EOF

sudo bash scripts/users.sh authorized.txt           # read the plan
sudo bash scripts/users.sh authorized.txt --apply
```

Passwords: if the README gives per-user passwords, use `chpasswd` from a file. If it doesn't, add `--password`. See `2-users.md`.

`harden.sh` already did aging and policy — don't redo it.

## 7 — Updates

Start them in a spare terminal as early as step 5, they're the slowest thing in the round.

```sh
sudo apt update && sudo apt dist-upgrade -y
sudo reboot
systemctl --failed        # after it comes back
```

## 8 — Services

Only for what's actually running. `6-services.md`. Always `sshd -t` before restarting SSH.

## 9 — Point scrounging

Re-read the README. Re-read the recon and baseline output you skimmed. Check Timeshift or backup snapshots for files you deleted.

## 10 — Final sweep

- [ ] Every README-required service is running — `systemctl status <svc>`
- [ ] A normal user can log in; an admin has `sudo`
- [ ] `ufw status verbose` — enabled, required ports open
- [ ] Forensics answers submitted
- [ ] One last README read

## Timing

- 0:00–0:20 README, backup
- 0:20–0:45 forensics
- 0:45–1:05 recon + baseline diff
- 1:05–1:20 **harden.sh**, verify login, start updates
- 1:20–2:00 users
- 2:00–2:30 reboot, confirm services
- 2:30–4:30 services, prohibited software, whatever discovery flagged
- 4:30–5:30 point scrounging
- 5:30–6:00 final sweep

Stuck on one thing for 20 minutes? Write it down and move on.
