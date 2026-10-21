# Linux Mint specifics

Mint is Ubuntu underneath, so most Ubuntu guidance applies. These are the places it differs — the ones that cost you time if you don't know them in advance.

## Identify the image first

```sh
cat /etc/linuxmint/info          # Mint release and codename
lsb_release -a
cat /etc/upstream-release/lsb-release    # the Ubuntu base underneath
uname -r                                  # kernel
```

| Mint | Ubuntu base |
|---|---|
| 21.x (Vanessa/Vera/Victoria/Virginia) | 22.04 LTS |
| 22.x (Wilma and later) | 24.04 LTS |

The Ubuntu base is what you want when looking up a STIG or benchmark.

## Repositories

Mint does **not** use `/etc/apt/sources.list` the way Ubuntu does. The real file is:

```
/etc/apt/sources.list.d/official-package-repositories.list
```

It contains both the Mint repos and the Ubuntu base repos. If updates fail or a repo looks tampered with, look here first.

## Update Manager

Mint has its own GUI update tool (`mintupdate`) layered on apt. Settings that get scored sometimes live in the GUI rather than in apt config.

Open **Update Manager → Edit → Preferences** and check:
- Automatic updates are enabled
- Security updates are not being held back
- The update policy isn't set to hide kernel updates

Command line still works normally (`apt update && apt upgrade`), and that's faster — but check the GUI setting too.

## Display manager: LightDM, not GDM

Mint uses **LightDM**. Ubuntu guides that tell you to edit `/etc/gdm3/custom.conf` do not apply.

```
/etc/lightdm/lightdm.conf
/etc/lightdm/lightdm.conf.d/
/usr/share/lightdm/lightdm.conf.d/
```

Confirm which one is actually running:
```sh
cat /etc/X11/default-display-manager
systemctl status display-manager
```

Check all three directories — an override in `lightdm.conf.d/` silently beats the main file.

## Timeshift

Mint ships Timeshift (system snapshots) by default. Two things matter:

- Snapshots can contain copies of files you just deleted. Check `/timeshift/` or the configured snapshot location when hunting prohibited files.
- Its config is `/etc/timeshift/timeshift.json`. A scheduled snapshot to an unexpected location is worth a look.

## Mint-only tools you'll see

| Tool | What it is |
|---|---|
| `mintupdate` | Update Manager |
| `mintsources` | Software Sources (repo editor) |
| `mintinstall` | Software Manager |
| `mintdrivers` | Driver Manager |
| `mintreport` | System Reports — sometimes flags real issues, worth opening once |

Don't remove these as "unrecognized packages." They're part of the base system.

## Firewall

UFW is installed but **inactive** by default on Mint. There's also a GUI (`gufw`, "Firewall Configuration"). Enabling the firewall scores nearly every round.

## Base install manifest

`/var/log/installer/initial-status.gz` exists on some Mint images and not others, depending on how the image was built. If it's there, use it to diff manually-installed packages (see `checklist/3-audit.md`). If not, fall back to reading `apt-mark showmanual` directly.

## Cinnamon

The default edition is Cinnamon. Screensaver lock settings live under **System Settings → Screensaver**, and the matching dconf keys are `org.cinnamon.desktop.screensaver` — not the GNOME ones.

```sh
gsettings set org.cinnamon.desktop.screensaver lock-enabled true
gsettings set org.cinnamon.desktop.session idle-delay 300
```
