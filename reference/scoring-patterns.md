# What actually scores

Compiled from past Linux scoring reports. Use it to decide what to do first when you're short on time — not as a substitute for reading the image README.

## Near-certain, every round

These appear so consistently that missing one is a self-inflicted loss.

- Forensics questions answered
- Unauthorized user removed
- Hidden user (extra UID 0, or an account not in the README) removed
- User who shouldn't be an admin removed from `sudo`
- Insecure password changed on a named user
- Minimum password length enforced
- Minimum/maximum password age set
- Firewall (UFW) enabled
- Important security updates installed
- Kernel updated
- Prohibited media files (mp3 etc.) removed
- Prohibited software removed (`ophcrack` and friends)
- Backdoor removed

## Common

- User added to a group the README requires
- `sudo` requires authentication (no `NOPASSWD`)
- ASLR enabled (`kernel.randomize_va_space = 2`)
- TIME-WAIT assassination protection (`net.ipv4.tcp_rfc1337 = 1`)
- A named service disabled or removed (NFS, nginx, Samba, telnet — whichever the scenario doesn't need)
- Specific application updated by name (Firefox, Thunderbird, Perl, the browser)
- Software the README told you to install, installed
- A deleted file restored (check backups and the FTP directory)
- Root login disabled over SSH
- Guest account / user list disabled at the login screen

## Service-specific, when that service is present

- FTP write commands disabled
- A named user explicitly allowed or denied FTP login (`/etc/ftpusers`)
- FTP users able to log in via SSH, or explicitly not
- Anonymous FTP disabled
- MySQL `skip-grant-tables` removed
- Web root permissions corrected
- Web shell removed from the web root

## Reading the pattern

Three things stand out:

1. **Users and passwords dominate.** Roughly a third of scored items on a typical Linux image. It's also the fastest category. Do it completely before anything clever.

2. **The README is a scoring sheet.** "Install software from readme", "add user X to group Y", "restore the deleted file" — these are only findable by reading the scenario. Teams that skim it lose points they could have had for free.

3. **A few sysctl values are scored by name.** `randomize_va_space` and `tcp_rfc1337` show up repeatedly. Applying the full sysctl block in `checklist/5-hardening.md` covers them.

## Point scrounging, last hour

When the obvious work is done and you still have time:

- Re-read the README for anything you skipped
- Re-read `recon.sh` output you skimmed — especially `added-packages.txt` and `changed-files.txt`
- Check every `/etc` config of every running service for an override directory you missed
- Look at `/etc/skel`, `/etc/fstab`, `/etc/hosts`
- Check Timeshift snapshots for copies of files you deleted
