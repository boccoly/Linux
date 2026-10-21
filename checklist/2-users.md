# 2 — Users and groups

The highest-frequency scoring category. Do it carefully and completely — it's worth more than anything exotic.

Source of truth is the **image README**, not your assumptions.

## Audit what's there

```sh
# Human accounts (UID >= 1000)
awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd

# Anyone with UID 0 other than root  -> hidden admin, remove or fix
awk -F: '$3 == 0 {print $1}' /etc/passwd

# Who is in sudo/admin
grep -E '^(sudo|admin|wheel):' /etc/group

# Accounts with no password set
sudo awk -F: '$2 == "" {print $1}' /etc/shadow

# Accounts with a login shell that shouldn't have one
awk -F: '$3 < 1000 && $7 !~ /(nologin|false)/ {print $1": "$7}' /etc/passwd
```

## Fix

**Unauthorized users** — not in the README's list:
```sh
sudo deluser --remove-home <user>
```
Read the README first. Some images want the home directory kept; if so drop `--remove-home`.

**Unauthorized admins** — in the README as a standard user but sitting in `sudo`:
```sh
sudo deluser <user> sudo
```

**Missing users** the README says should exist:
```sh
sudo useradd -m -s /bin/bash <user>
```

**Set passwords.** On Mint/Ubuntu/Debian use `chpasswd` — `passwd --stdin` is Red Hat only and silently fails here.
```sh
echo '<user>:<NewP@ssw0rd!>' | sudo chpasswd
```
All at once:
```sh
# users.txt: one "name:password" per line
sudo chpasswd < users.txt
```

**Hidden UID-0 account** — if it's not root, it's either removed or demoted to a normal UID.

**Lock root's direct login:**
```sh
sudo passwd -l root
```

**Lock system accounts** so they can't be logged into:
```sh
for u in $(awk -F: '$3 < 1000 && $1 != "root" {print $1}' /etc/passwd); do
  sudo usermod -L "$u"
  sudo usermod -s /usr/sbin/nologin "$u" 2>/dev/null
done
```
Leave `sync`, `shutdown`, and `halt` shells alone if present.

## Password and account policy

`/etc/login.defs`:
```
PASS_MAX_DAYS   90
PASS_MIN_DAYS   7
PASS_WARN_AGE   14
```

Apply the aging policy to existing users too — setting `login.defs` alone only affects new accounts:
```sh
for u in $(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd); do
  sudo chage -M 90 -m 7 -W 14 "$u"
done
```

Complexity and history, `/etc/pam.d/common-password`:
```
password requisite pam_pwquality.so retry=3 minlen=12 difok=3 ucredit=-1 lcredit=-1 dcredit=-1 ocredit=-1
password [success=1 default=ignore] pam_unix.so obscure use_authtok try_first_pass yescrypt remember=5
```
Needs `libpam-pwquality` installed.

Lockout on failed attempts, `/etc/pam.d/common-auth`:
```
auth required pam_faillock.so preauth silent deny=5 unlock_time=1800
auth [success=1 default=ignore] pam_unix.so nullok
auth [default=die] pam_faillock.so authfail deny=5 unlock_time=1800
auth sufficient pam_faillock.so authsucc
```

> **PAM will lock you out if you get it wrong.** Keep your second root terminal open, change one file at a time, and test a login in that terminal before moving on.

## Sudo

```sh
sudo visudo              # never edit /etc/sudoers directly
ls -la /etc/sudoers.d/   # check for dropped-in NOPASSWD rules
```

Look for and remove:
- `NOPASSWD` entries
- `ALL=(ALL) ALL` on a user who shouldn't have it
- `!authenticate`

Make sure this is present:
```
Defaults    use_pty
Defaults    logfile="/var/log/sudo.log"
```
