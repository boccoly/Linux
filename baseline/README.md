# baseline/

Clean-system snapshots. `scripts/baseline-diff.sh` compares a competition image against these to show what's been changed.

One directory per OS version:

```
baseline/
  mint21/      Linux Mint 21.x  (Ubuntu 22.04 base)
  mint22/      Linux Mint 22.x  (Ubuntu 24.04 base)
```

Each contains:

| File | What it is |
|---|---|
| `etc.zip` | Factory `/etc`, zipped from `/` so paths start with `etc/` |
| `var.zip` | Factory `/var`, minus cache/log/lib/backups |
| `pkgorig.txt` | Every package installed on a clean system |
| `pkgmanual.txt` | Manually-installed packages on a clean system |
| `suid.txt`, `sgid.txt`, `world-writable.txt` | Permission manifests |
| `services-enabled.txt` | Enabled systemd services |
| `passwd.txt`, `group.txt` | Accounts and groups (`name:uid:shell`) |
| `BASELINE-INFO` | Version, kernel, capture date |

## Creating one

On a **fresh Mint VM with no updates and nothing installed**:

```sh
sudo bash make-baseline.sh ./baseline
```

Then copy `baseline/<tag>/` into this repo.

The baseline must match the competition image's Mint version. A Mint 21 baseline diffed against a Mint 22 image produces thousands of false positives and is worse than useless.
