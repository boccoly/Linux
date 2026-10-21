# 0 — Round flow

The order matters. Forensics before changes, enumeration before fixes, kernel reboot before sysctl.

## Order

| # | Step | File | Why here |
|---|---|---|---|
| 0 | README + scenario notes | this file | Everything downstream depends on knowing the authorized users and required services |
| 1 | Forensics questions | `1-forensics.md` | Hardening erases the evidence |
| 2 | Recon / baseline | `3-audit.md` | Find what's actually wrong before applying generic fixes |
| 3 | Users and groups | `2-users.md` | Highest-frequency points, and fast |
| 4 | Updates | `4-updates.md` | Slow — start it early, let it run in the background |
| 5 | **Reboot** for kernel | `4-updates.md` | sysctl and some services behave differently pre-reboot |
| 6 | System hardening | `5-hardening.md` | PAM, sysctl, firewall, permissions |
| 7 | Services | `6-services.md` | Per-service config for whatever the image runs |
| 8 | Final sweep | this file | Verify nothing broke |

## Step 0 — before you touch anything

- [ ] Read the image README fully. Twice.
- [ ] Write down: authorized **users**, authorized **admins**, required **services**, required **software**.
- [ ] Note anything the README says to install or keep — those are points too.
- [ ] Open a second terminal and keep it logged in as root/sudo. Do not close it. If you lock yourself out with a PAM or sudoers edit, this is your way back.

## Step 4 — updates in the background

Start the update early, keep working in another terminal. Don't sit and watch it.

```sh
sudo apt update && sudo apt upgrade -y
```

## Step 8 — final sweep

- [ ] Every service the README requires is still running (`systemctl status <svc>`)
- [ ] You can still log in as a normal user — test it in the second terminal
- [ ] `sudo` still works for an authorized admin
- [ ] Firewall is on and the required ports are open
- [ ] Re-read the README one more time for anything you skipped
- [ ] Forensics answers submitted

## Timing

A round is six hours. Rough target split:

- 0:00–0:30 — README, forensics, recon
- 0:30–1:15 — users, start updates
- 1:15–2:00 — reboot, system hardening
- 2:00–4:00 — services, prohibited files, whatever recon flagged
- 4:00–5:30 — point scrounging, re-check recon output for things you skipped
- 5:30–6:00 — final sweep, verify nothing is broken

If you're stuck on one thing for more than 20 minutes, write it down and move on. Come back if there's time.
