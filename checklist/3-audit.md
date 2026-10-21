# 3 — Recon and baseline audit

Run `scripts/recon.sh` and read the output. This is how you find vulnerabilities that aren't on anyone's checklist.

A checklist only contains what someone already knew to look for. Diffing against a clean system finds the rest.

## Run it

```sh
sudo bash scripts/recon.sh
```

Writes everything to `./recon-<timestamp>/`. Read-only — it changes nothing.

## What to read, in order

| File | What you're looking for |
|---|---|
| `users.txt` | UID 0 duplicates, empty passwords, unexpected sudo members |
| `manual-packages.txt` | Software installed after the image was built — games, hacking tools, servers nobody asked for |
| `changed-files.txt` | Package files whose contents were modified — a very strong signal |
| `listening.txt` | Ports open that the README doesn't justify |
| `cron.txt` + `systemd.txt` | Persistence |
| `suid.txt` | SUID binaries that aren't standard |
| `world-writable.txt` | Loose permissions |
| `media.txt` | Prohibited mp3/mp4/images |

## Package verification — the highest-value check

On Debian/Ubuntu/Mint, `debsums` compares installed files against the package's recorded checksums. Anything it reports as changed was edited after install.

```sh
sudo apt install -y debsums
sudo debsums -c 2>/dev/null        # list changed files only
```

Config files legitimately change, so expect noise in `/etc`. A changed **binary** in `/usr/bin` or `/usr/sbin` is almost never legitimate.

## Manually installed packages

Everything installed on top of the base system:
```sh
apt-mark showmanual | sort -u
```

On Mint the installer's base manifest may be at `/var/log/installer/initial-status.gz`. If it exists, diffing gives you a much shorter list:
```sh
comm -23 <(apt-mark showmanual | sort -u) \
         <(gzip -dc /var/log/installer/initial-status.gz | sed -n 's/^Package: //p' | sort -u)
```
If that file doesn't exist, just read `apt-mark showmanual` and look for things that don't belong.

Common prohibited software: `ophcrack`, `john`, `hydra`, `nmap`, `wireshark`, `aircrack-ng`, `netcat`/`nc`, `telnetd`, `hashcat`, games (`aisleriot`, `gnome-mahjongg`), torrent clients, `samba` when not required.

```sh
sudo apt purge -y <package>
sudo apt autoremove -y
```

## Prohibited files

```sh
sudo find /home /root /srv /var/www -type f \
  \( -iname '*.mp3' -o -iname '*.mp4' -o -iname '*.wav' -o -iname '*.avi' \
     -o -iname '*.mkv' -o -iname '*.flac' -o -iname '*.mov' \) 2>/dev/null
```

Also look for password files and scripts left lying around:
```sh
sudo find /home -iname '*pass*' -o -iname '*pw*' 2>/dev/null
sudo find /home -name '*.sh' 2>/dev/null
```

Read a file before you delete it — it may be the answer to a forensics question.

## Permissions

```sh
# World-writable files (review, then fix individually)
sudo find / -xdev -type f -perm -0002 2>/dev/null

# SUID / SGID
sudo find / -xdev -type f \( -perm -4000 -o -perm -2000 \) 2>/dev/null

# Files owned by nobody
sudo find / -xdev \( -nouser -o -nogroup \) 2>/dev/null
```

> Review the output, then fix what's wrong. Do **not** pipe any of these into `rm` or a blanket `chmod` — removing an unowned system file or stripping a legit SUID bit (`sudo`, `passwd`, `su`, `ping`, `mount`) will break the image and cost you far more than it gains.

Core file permissions should be:
```sh
sudo chown root:root /etc/passwd  && sudo chmod 644 /etc/passwd
sudo chown root:shadow /etc/shadow && sudo chmod 640 /etc/shadow
sudo chown root:root /etc/group   && sudo chmod 644 /etc/group
sudo chown root:shadow /etc/gshadow && sudo chmod 640 /etc/gshadow
sudo chmod 750 /home/*
```
