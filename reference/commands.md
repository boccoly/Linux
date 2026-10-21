# Command reference

For when you know what you want and need the syntax.

## Users

```sh
awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd   # human users
awk -F: '$3 == 0 {print $1}' /etc/passwd                         # UID 0 accounts
grep -E '^(sudo|admin|wheel):' /etc/group                        # admins
sudo awk -F: '$2 == "" {print $1}' /etc/shadow                   # empty passwords

sudo useradd -m -s /bin/bash <user>
sudo deluser --remove-home <user>
sudo deluser <user> sudo                     # remove from sudo group
sudo usermod -aG sudo <user>                 # add to sudo group
sudo usermod -L <user>                       # lock
sudo usermod -s /usr/sbin/nologin <user>     # no shell

echo '<user>:<password>' | sudo chpasswd     # set password (NOT passwd --stdin)
sudo chage -M 90 -m 7 -W 14 <user>           # aging
chage -l <user>                              # view aging
sudo passwd -l root                          # lock root

sudo vipw        # safely edit /etc/passwd
sudo vigr        # safely edit /etc/group
sudo visudo      # safely edit sudoers
```

## Packages

```sh
apt-mark showmanual | sort -u          # manually installed
apt list --installed
sudo apt update && sudo apt upgrade -y
sudo apt dist-upgrade -y               # includes kernel
sudo apt purge -y <package>
sudo apt autoremove -y
apt-cache policy <package>
dpkg -S <file>                         # which package owns a file
dpkg -L <package>                      # what a package installed
sudo debsums -c                        # changed package files
```

## Services

```sh
systemctl list-units --type=service --state=running
systemctl list-unit-files --type=service --state=enabled
sudo systemctl enable --now <svc>
sudo systemctl disable --now <svc>
sudo systemctl restart <svc>
systemctl status <svc>
systemctl --failed
sudo systemctl list-timers --all
```

## Network

```sh
sudo ss -tulpn                  # listening + process
sudo lsof -i -n -P
sudo ufw status verbose
sudo ufw allow <port>/tcp
sudo ufw deny <port>/tcp
sudo ufw --force enable
sudo ufw delete allow <port>
```

## Finding things

```sh
sudo find / -xdev -type f -perm -4000           # SUID
sudo find / -xdev -type f -perm -2000           # SGID
sudo find / -xdev -type f -perm -0002           # world-writable
sudo find / -xdev \( -nouser -o -nogroup \)     # unowned
sudo find /etc ! -user root                     # /etc files not owned by root
sudo find / -newermt "2026-01-01" -type f 2>/dev/null
sudo find /home -iname '*pass*'

grep -rniE 'eval\(|base64_decode|shell_exec|passthru' /var/www    # web shells
sudo lsattr -R /etc 2>/dev/null | grep -v -- '--e--'              # immutable files
sudo chattr -i <file>                                              # remove immutable
```

## Permissions

```sh
sudo chown root:root /etc/passwd && sudo chmod 644 /etc/passwd
sudo chown root:shadow /etc/shadow && sudo chmod 640 /etc/shadow
sudo chmod 750 /home/*
getfacl <file>          # check ACLs
setfacl -b <file>       # strip ACLs
```

## Logs

```sh
sudo tail -100 /var/log/auth.log
sudo grep -i 'Failed password' /var/log/auth.log
sudo grep -i 'Accepted' /var/log/auth.log
last ; lastb
journalctl -xe
journalctl -u <svc> --since today
```

## Config testing — always before restarting

```sh
sudo sshd -t                 # sshd_config
sudo apachectl configtest    # apache
sudo nginx -t                # nginx
sudo testparm                # samba
sudo visudo -c               # sudoers
sudo sysctl -p               # apply + validate sysctl
```

## Safety

```sh
sudo cp <file> <file>.bak        # before editing anything important
sudo systemctl list-units --failed    # after any big change
```

Keep a second root terminal open the whole round. Before editing PAM, sudoers, or sshd, confirm you can still log in from it afterward.
