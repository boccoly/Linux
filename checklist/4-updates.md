# 4 — Updates

Start this early and let it run in another terminal. It's slow and it reliably scores.

## Check the sources first

A tampered repo list makes everything below fail or install the wrong thing.

```sh
cat /etc/apt/sources.list
ls -la /etc/apt/sources.list.d/
```

On Mint the real file is `/etc/apt/sources.list.d/official-package-repositories.list`. Look for:
- Repos pointing at a non-official host
- Commented-out security repos
- A PPA that doesn't belong

Check for pinning that blocks updates:
```sh
ls -la /etc/apt/preferences.d/ 2>/dev/null
cat /etc/apt/preferences 2>/dev/null
```

## Update

```sh
sudo apt update
sudo apt upgrade -y
sudo apt dist-upgrade -y
sudo apt autoremove -y
```

Specific packages are often scored individually (kernel, Firefox, Thunderbird, the package manager itself). `dist-upgrade` covers the kernel; plain `upgrade` may not.

## Reboot

After a kernel update, reboot. Do it before sysctl work.

```sh
sudo reboot
```

After rebooting, confirm required services came back:
```sh
systemctl --failed
```

## Automatic updates

```sh
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
```

`/etc/apt/apt.conf.d/20auto-upgrades`:
```
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
```

On Mint, also check the Update Manager GUI — its policy settings are sometimes what's scored rather than the apt config. See `mint.md`.

## Software the README asks for

If the scenario says to install something, install it. Those are free points and easy to forget.
```sh
sudo apt install -y <package>
```
