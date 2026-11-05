# scripts/

Built for Linux Mint 21 and Debian 12. Plain bash, no dependencies beyond what the distro ships except where noted. Run everything with `sudo`.

| Script | When | Acts? |
|---|---|---|
| `recon.sh` | Start of round, after forensics | Report only, unless you pass a flag |
| `baseline-diff.sh` | Right after recon | Never |
| `harden.sh` | After discovery | **Yes** — backed up and reversible |
| `users.sh` | After hardening | Only on `--apply` |
| `make-baseline.sh` | **Before the season**, on a clean VM | Never |

---

## harden.sh

```sh
sudo bash harden.sh --dry-run                  # print the plan
sudo bash harden.sh                            # apply everything
sudo bash harden.sh --only sysctl,ufw          # just these modules
sudo bash harden.sh --skip pam,sshd            # everything except these
sudo bash harden.sh --rollback /root/harden-backup-20261112-143022
```

Thirteen modules: `logindefs aging pam sysctl ufw perms sysaccounts root apparmor auditd unattended sshd displaymanager`. See `../checklist/5-hardening.md` for what each one sets.

Every file it touches is copied to `/root/harden-backup-<timestamp>/files/` with its path preserved, so rollback restores exactly.

**PAM and sshd are validated after writing.** PAM is edited surgically — existing `pam_pwquality`/`pam_faillock` lines are dropped and reinserted in the correct position around `pam_unix`, `nullok` is stripped, and additional modules like `pam_cap` survive. Afterwards it counts `pam_unix` occurrences and confirms both modules exist on disk; if the check fails it restores the backup automatically. `sshd -t` runs before any restart, and a failure reverts the config without touching the service.

**Test authentication immediately after running it:**

```sh
su - <a normal user>
sudo -v
```

It leaves firewall ports, users, prohibited software, per-service configs, and updates to you, and prints that list when it finishes.

---

## recon.sh

```sh
sudo bash recon.sh [output-dir]      # report only
sudo bash recon.sh --quarantine      # MOVE flagged media to /root/cp-quarantine
sudo bash recon.sh --purge           # apt purge flagged prohibited packages
```

Writes to `./recon-<timestamp>/`. Start with `SUMMARY.txt`, then `history.txt` and `auth.txt`.

Covers accounts and privileged groups, sudoers drop-ins, package inventory, ~50 known-prohibited packages, `debsums` verification, listening ports, firewall state, cron, systemd units outside the package manager, startup persistence, shell history, login history and planted SSH keys, SUID filtered against a known-good allowlist, world-writable and unowned files, media, scripts and credentials in home directories, and web shells.

Quarantine **moves**, never deletes — a file can be a forensics answer. Check the README before `--purge`: `nmap`, `wireshark`, and `vsftpd` are sometimes required.

Install `debsums` first if you can; it's the strongest single signal for tampered files. The file tells you the no-install alternative if you'd rather not.

---

## baseline-diff.sh

```sh
sudo bash baseline-diff.sh ../baseline/mint21 [output-dir]
```

Compares the image against a clean-system snapshot. Output in `./basediff-<timestamp>/`.

`users-diff.txt`, `pkg-added.txt`, and `suid-diff.txt` are the reliable ones. The `/etc` content diff is noisy — version drift and the scenario's own setup both show up there. Skim it last.

`passwd`, `group`, and `shadow` always differ. That's the point.

---

## make-baseline.sh

```sh
sudo bash make-baseline.sh ./baseline
```

Run **on a fresh VM with no updates and nothing installed**. It refuses to run from a live ISO session — a snapshot taken from the installer's "Try" desktop carries casper and ubiquity packages that never exist on an installed system.

Captures `/etc` and `/var` as zips plus package, permission, service, and account manifests. Excludes `shadow`, `gshadow`, SSH host keys, NetworkManager connections, `brlapi.key`, and `machine-id`, so the result is safe to commit publicly.

Needs `zip`. The baseline must match the image's OS **version and desktop edition** — check with `dpkg -l | grep mint-info` or `dpkg -l | grep task-.*-desktop`.

---

## users.sh

```sh
sudo bash users.sh authorized.txt                                  # dry run
sudo bash users.sh authorized.txt --apply                          # accounts only
sudo bash users.sh authorized.txt --apply --password 'P@ssw0rd!'   # + one shared password
sudo bash users.sh authorized.txt --apply --remove-home
```

`authorized.txt` is one `name role` per line, role `admin` or `user`, `#` comments ignored:

```
# admins
alice admin
# standard users
bob   user
```

Handles unauthorized accounts, missing accounts, admin group membership in both directions, passwords, and locking system accounts with login shells. Aging and policy are `harden.sh`'s job.

Extra UID-0 accounts are **reported, not removed**. Never touches `root`, `nobody`, or your own `$SUDO_USER` — set your own password separately.

**Use `--password` only when the README gives no per-user passwords.** If it does, use `chpasswd` from a file instead and change only the ones failing policy. See `../checklist/2-users.md`.

Read the dry-run plan before applying. If it lists an account you meant to keep, `authorized.txt` is wrong.
