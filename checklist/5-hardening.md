# 5 — System hardening

Do this **after** the kernel reboot.

## Firewall

Mint ships UFW installed but inactive. Enabling it scores almost every round.

```sh
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp          # only if SSH is required by the README
sudo ufw --force enable
sudo ufw status verbose
```

Open only the ports the scenario requires. If the README doesn't mention SSH, don't open 22.

## sysctl

Write to `/etc/sysctl.conf` or a file in `/etc/sysctl.d/`, then apply.

```
# IP spoofing / source routing
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0

# ICMP
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# SYN flood + TIME-WAIT assassination
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_rfc1337 = 1

# Logging
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# IP forwarding (off unless the box is a router)
net.ipv4.ip_forward = 0

# ASLR
kernel.randomize_va_space = 2
```

```sh
sudo sysctl -p
```

`tcp_rfc1337` and `randomize_va_space` show up on scoring reports by name. Don't skip them.

## AppArmor

Mint ships AppArmor. Make sure it's on and enforcing.

```sh
sudo systemctl enable --now apparmor
sudo aa-status
sudo aa-enforce /etc/apparmor.d/*        # move complain-mode profiles to enforce
```

## Disable unneeded services

```sh
systemctl list-units --type=service --state=running
```

Common ones to disable **if the README doesn't require them**:
```sh
for s in avahi-daemon cups bluetooth rpcbind nfs-server telnet vsftpd; do
  sudo systemctl disable --now "$s" 2>/dev/null
done
```

Check the README first, every time. Disabling a required service is a net loss.

## Logging and auditing

```sh
sudo systemctl enable --now rsyslog
sudo apt install -y auditd
sudo systemctl enable --now auditd
```

## GRUB

```sh
sudo grub-mkpasswd-pbkdf2        # copy the hash it prints
```

Add to `/etc/grub.d/40_custom`:
```
set superusers="root"
password_pbkdf2 root <hash>
```
```sh
sudo chmod 600 /boot/grub/grub.cfg
sudo update-grub
```

## Login screen

Mint uses LightDM. Hide the user list and disable guest:

`/etc/lightdm/lightdm.conf` (or a file in `/etc/lightdm/lightdm.conf.d/`):
```
[Seat:*]
greeter-hide-users=true
greeter-show-manual-login=true
allow-guest=false
autologin-user=
```

Also check `/etc/lightdm/lightdm.conf.d/` for an override that re-enables autologin.

## USB and filesystem

```sh
# Disable USB storage if the scenario calls for it
echo 'install usb-storage /bin/true' | sudo tee /etc/modprobe.d/usb-storage.conf
```

Check `/etc/fstab` for mounts without `nodev,nosuid,noexec` where they belong, and for anything odd mounted from an unexpected place.

## Firefox

Mint ships Firefox. Check for malicious extensions and insecure settings:
```sh
ls /home/*/.mozilla/firefox/*/extensions/ 2>/dev/null
```
In the GUI: enable "Block dangerous and deceptive content", turn off saved passwords, set updates to automatic.
