# 3 — Discovery

Run both, read both summaries, then start fixing. Both are read-only.

```sh
sudo bash scripts/recon.sh
sudo bash scripts/baseline-diff.sh baseline/<os>
```

A checklist only contains what someone already knew to look for. Diffing against a clean system finds the rest.

## recon.sh output

Start with `SUMMARY.txt`, then in this order:

| File | What it catches |
|---|---|
| `history.txt` | What was actually done on this box. Often the richest single artifact |
| `auth.txt` | Login history, planted `authorized_keys` |
| `users.txt` | Accounts by UID, extra UID 0, privileged groups, `NOPASSWD` in sudoers, aging |
| `prohibited-packages.txt` | ~50 known-bad packages matched against what's installed |
| `changed-files.txt` | Package files modified since install (needs `debsums`) |
| `listening.txt` | Ports open that the README doesn't justify |
| `cron.txt`, `systemd.txt`, `startup.txt` | Persistence |
| `suid-unexpected.txt` | SUID binaries outside the known-good set |
| `media.txt`, `files.txt` | Prohibited media, scripts and credentials in home dirs, web shells |

`suid-all.txt` has the unfiltered list if you want to check the allowlist's work.

### Acting on it

Read the README first, then:

```sh
sudo bash scripts/recon.sh --quarantine    # MOVES media to /root/cp-quarantine
sudo bash scripts/recon.sh --purge         # apt purge the flagged packages
```

Quarantine moves, never deletes — a file can be a forensics answer. And `nmap`, `wireshark`, and `vsftpd` are sometimes required by a scenario, so check before purging.

## baseline-diff.sh output

| File | Reliability |
|---|---|
| `users-diff.txt` | **High.** A hidden UID-0 account shows regardless of baseline drift |
| `pkg-added.txt` | **High.** Package names don't drift |
| `suid-diff.txt` | **High** |
| `services-diff.txt` | Good |
| `etc-changed.txt`, `etc-added.txt` | **Noisy.** Most affected by version drift — skim, don't trust |

Expect a few hundred `/etc` entries even with a correct baseline. The scenario's own setup (installing Apache, creating users) shows up as differences too. That's useful, not noise — just not a short list.

`passwd`, `group`, and `shadow` always differ. That's the point. Read them.

## Package verification — baseline-independent

Compares installed files against the checksums the package itself shipped, so it doesn't care which ISO you used or whether updates were applied:

```sh
sudo apt install -y debsums && sudo debsums -c

# or with no install:
cd / && sudo md5sum -c /var/lib/dpkg/info/*.md5sums 2>/dev/null | grep ': FAILED$'
```

A changed **binary** under `/usr/bin` or `/usr/sbin` is almost never legitimate. Changed files in `/etc` include configs an admin edited, so use judgment there.

## Permissions

`recon.sh` reports world-writable, unowned, and unexpected SUID files. **Review and fix individually.**

Do not pipe any of those lists into `rm` or a blanket `chmod` — removing an unowned system file or stripping a legitimate SUID bit breaks the image and costs more than it gains.

```sh
sudo chmod o-w <specific file>
sudo chmod -s <specific file>
```

Core file permissions are already handled by `harden.sh`.

## Building the baseline

Before the season, on a **clean VM of the matching OS, version and desktop edition**, with no updates and nothing installed:

```sh
sudo bash scripts/make-baseline.sh ./baseline
```

Copy the resulting directory into `baseline/`. It refuses to run from a live ISO session, since a baseline captured from the installer's "Try" desktop is worthless.

Match the major version and the desktop edition. A MATE baseline against a Cinnamon image, or Mint 21 against Mint 22, produces enough false positives to bury the real findings.
