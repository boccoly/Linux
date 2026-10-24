# scripts/

Built for Linux Mint 21 "Vanessa" (Ubuntu 22.04 jammy base). All are plain bash, no dependencies beyond what Mint ships, except where noted.

Run everything with `sudo`.

| Script | When | Safe? |
|---|---|---|
| `recon.sh` | Start of round, after forensics | Read-only |
| `baseline-diff.sh` | Start of round, right after recon | Read-only |
| `users.sh` | Step 3, users and groups | Dry-run by default |
| `sweep.sh` | Step 3–4, prohibited content | Reports by default |
| `make-baseline.sh` | **Before the season**, on a clean VM | Read-only |

## recon.sh

```sh
sudo bash recon.sh [output-dir]
```

Enumerates the image into `./recon-<timestamp>/`. Changes nothing. Start with `SUMMARY.txt`, then `history.txt` and `auth.txt`.

Install `debsums` first if you can — it adds a changed-package-files check, which is one of the stronger signals available.

## baseline-diff.sh

```sh
sudo bash baseline-diff.sh ../baseline/mint21 [output-dir]
```

Compares this image against a clean-system snapshot and reports what's different. Needs a baseline built by `make-baseline.sh`. Output in `./basediff-<timestamp>/`, read `SUMMARY.txt` first.

`passwd`, `group`, and `shadow` always show as changed — that's the point, read them.

## make-baseline.sh

```sh
sudo bash make-baseline.sh ./baseline
```

Run **on a fresh Mint VM with no updates and nothing installed**. Captures `/etc`, `/var`, package manifests, and permission/service/account manifests into `baseline/mint21/`. Copy that directory into the repo.

Needs `zip` — if missing, `sudo apt install -y zip` first. It writes nothing to `/etc`, so it won't pollute the snapshot.

The baseline must match the image's Mint version **and edition**. Check with `dpkg -l | grep mint-info`.

## users.sh

```sh
sudo bash users.sh authorized.txt                                  # dry run
sudo bash users.sh authorized.txt --apply --password 'P@ssw0rd!'   # execute
sudo bash users.sh authorized.txt --apply --remove-home            # also delete homes
```

`authorized.txt`, transcribed from the image README — one `name role` per line:

```
# admins
alice admin
bob   admin
# standard users
carol user
```

Handles: unauthorized accounts, missing accounts, sudo membership in both directions, passwords via `chpasswd`, `chage` aging, and locking system accounts that have login shells. Extra UID-0 accounts are **reported, not removed** — review those by hand.

Never touches `root`, `nobody`, or your own `$SUDO_USER`. Prints a full plan and changes nothing until `--apply`. Keeps home directories unless you pass `--remove-home`.

**Read the dry-run output before applying.** If the plan lists accounts you expected to keep, your `authorized.txt` is wrong.

## sweep.sh

```sh
sudo bash sweep.sh                 # report only
sudo bash sweep.sh --quarantine    # move flagged files to /root/cp-quarantine
sudo bash sweep.sh --purge         # apt purge flagged packages
```

Checks prohibited packages, media files, scripts and credential files in home directories, listening ports, cron, non-package systemd units, startup persistence, and SUID binaries filtered against a known-good allowlist.

Quarantine **moves**, never deletes — a file may still answer a forensics question.

Check the image README before purging. `vsftpd`, `nmap`, and `wireshark` are sometimes required by the scenario.
