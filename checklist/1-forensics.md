# 1 — Forensics

Do these **first**. Every forensics question is guaranteed points, they're fast, and hardening destroys the answers (you delete the backdoor, then can't say what port it listened on).

Read all the forensics questions before answering any of them — they often chain.

## Where answers live

**Shell and command history**
```sh
cat /home/*/.bash_history /root/.bash_history
cat /home/*/.zsh_history
```
History is often the single richest artifact. Read it before anything else.

**Authentication and login**
```sh
/var/log/auth.log          # ssh logins, sudo use, failed attempts
last                       # successful logins   (/var/log/wtmp)
lastb                      # failed logins       (/var/log/btmp)
sudo grep -i 'sudo:' /var/log/auth.log
sudo grep -i 'Failed password' /var/log/auth.log
sudo grep -i 'Accepted' /var/log/auth.log
```

**SSH**
```sh
cat /home/*/.ssh/authorized_keys /root/.ssh/authorized_keys
cat /etc/ssh/sshd_config
```
An unexpected key in `authorized_keys` is a classic answer *and* a vulnerability.

**Scheduled tasks**
```sh
cat /etc/crontab
ls -la /etc/cron.*
sudo ls -la /var/spool/cron/crontabs/
sudo crontab -l -u <user>
systemctl list-timers --all
```

**Persistence locations**
```sh
/etc/rc.local
/etc/profile.d/
/home/*/.bashrc  /home/*/.profile
/etc/systemd/system/   /home/*/.config/systemd/user/
/etc/ld.so.preload
```

**Network / listening processes**
```sh
sudo ss -tulpn          # what is listening, and which process
sudo lsof -i -n -P
```

**File timestamps** — useful for "when did this happen" questions
```sh
sudo find / -newermt "2026-01-01" -type f 2>/dev/null | grep -v '^/proc\|^/sys'
stat <file>
```

**Hashes** — questions sometimes ask for a file hash, or to identify a hash type
```sh
md5sum <file>
sha1sum <file>
sha256sum <file>
```
Length tells you the type: MD5 = 32 hex chars, SHA1 = 40, SHA256 = 64.

## Answer format

- Answer exactly what's asked. If it wants a username, give the username only — not a sentence.
- If it asks for a path, give the absolute path.
- Don't guess wildly, but don't leave it blank either. A reasoned guess costs nothing.
