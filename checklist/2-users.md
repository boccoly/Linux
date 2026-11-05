# 2 — Users and groups

The highest-frequency scoring category. Everything here depends on the image README.

**Policy and aging are already done** — `harden.sh` set `login.defs`, ran `chage` on every human account, and configured PAM. Don't redo them.

## Build the authorized list

Transcribe from the README. One `name role` per line, role is `admin` or `user`:

```sh
cat > authorized.txt <<'EOF'
# admins
alice admin
bob   admin
# standard users
carol user
EOF
```

List **everyone** who should exist, including your own account. Anyone on the system and not in this file gets flagged for removal.

## Reconcile

```sh
sudo bash scripts/users.sh authorized.txt           # dry run - read the plan
sudo bash scripts/users.sh authorized.txt --apply
```

Handles: unauthorized accounts, missing accounts, admin group membership in both directions, and locking system accounts with shells.

**Read the dry-run plan before applying.** If it lists someone the README says to keep, fix `authorized.txt` — not the script.

Extra UID-0 accounts are **reported, not removed**. Handle those by hand.

`root`, `nobody`, and your own `$SUDO_USER` are never touched, so set your own password separately:

```sh
sudo passwd <your account>
```

## Passwords

**If the README gives per-user passwords** — set them individually, and only change the ones that fail policy (14+ chars, upper, lower, digit, symbol):

```sh
cat > /root/users.txt <<'EOF'
alice:TheirREADMEPassword!
bob:AnotherOne!2026
EOF
sudo chpasswd < /root/users.txt
sudo shred -u /root/users.txt

sudo passwd <the weak one>     # new strong password, don't restore the weak one
```

The quoted `'EOF'` matters — without it bash mangles `!` as history expansion.

**If the README gives no passwords** — one password for everyone is fine:

```sh
sudo bash scripts/users.sh authorized.txt --apply --password 'Str0ng!P@ss2026'
```

## Groups beyond sudo

`users.sh` only reconciles `sudo`/`admin`. These also confer power and are yours to check:

```sh
grep -E '^(sudo|adm|shadow|disk|root|docker|lpadmin):' /etc/group
id <user>
sudo deluser <user> adm
```

`shadow` means reading password hashes. `disk` means raw device access. Both are effectively root on a standard user.

A normal desktop user legitimately sits in `cdrom`, `dip`, `plugdev`, `sambashare`, `audio`, `video`. Anything past that is worth a look.

## Creating a user the README asks for

```sh
sudo useradd -m -s /bin/bash <name>
echo '<name>:TempP@ss2026!' | sudo chpasswd
sudo chage -M 90 -m 7 -W 14 <name>
sudo passwd -e <name>              # force change at next login, if required
echo '<name> user' >> authorized.txt
```

## Verify

```sh
awk -F: '$3>=1000 && $3<65534 {print $1}' /etc/passwd | sort
```

Should match `authorized.txt` exactly. Then test in your second terminal:

```sh
su - <a normal user>
sudo -v
```

## Sudoers

```sh
sudo visudo              # never edit /etc/sudoers directly
ls -la /etc/sudoers.d/
```

Remove `NOPASSWD`, `!authenticate`, and any `ALL=(ALL) ALL` on a user who shouldn't have it. `recon.sh` greps for these and puts them in `users.txt`.
