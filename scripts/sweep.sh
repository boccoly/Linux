#!/usr/bin/env bash
#
# sweep.sh - find prohibited software, media, and persistence
#
# REPORTS ONLY by default. With --quarantine it MOVES files to a holding
# directory (never deletes - you may still need them for forensics).
# With --purge it removes flagged packages.
#
# Usage:
#   sudo bash sweep.sh                      # report
#   sudo bash sweep.sh --quarantine         # move flagged files aside
#   sudo bash sweep.sh --purge              # apt purge flagged packages
#
set -uo pipefail

QUARANTINE=false ; PURGE=false
HOLD="/root/cp-quarantine"
for a in "$@"; do
    case "$a" in
        --quarantine) QUARANTINE=true ;;
        --purge)      PURGE=true ;;
        -h|--help)    sed -n '2,14p' "$0"; exit 0 ;;
    esac
done
[[ $EUID -ne 0 ]] && echo "Run with sudo for complete results." >&2

hdr() { printf '\n=== %s ===\n' "$1"; }

# ------------------------------------------------------- prohibited pkgs
BAD_PKGS='^(ophcrack|john|johnny|hydra|hashcat|medusa|aircrack-ng|ettercap-[a-z]+|nikto|sqlmap|metasploit[a-z-]*|wireshark|tshark|netcat[a-z-]*|ncat|telnetd|telnet-server|rsh-server|tftpd[a-z-]*|vsftpd|nmap|zenmap|hping3|kismet|crack|cewl|dirb|wfuzz|responder|bettercap|minetest|freeciv|aisleriot|gnome-mahjongg|gnome-sudoku|gnome-mines|transmission[a-z-]*|deluge[a-z-]*|qbittorrent|frostwire|vuze)$'

hdr "Prohibited / suspicious packages"
mapfile -t FLAGGED < <(dpkg-query -W -f='${Package}\n' 2>/dev/null | grep -E "$BAD_PKGS" || true)
if (( ${#FLAGGED[@]} == 0 )); then
    echo "none matched"
else
    printf '  %s\n' "${FLAGGED[@]}"
    echo
    echo "  NOTE: check the image README first. vsftpd, nmap and wireshark are"
    echo "        sometimes REQUIRED by the scenario."
    if $PURGE; then
        echo "  purging..."
        apt purge -y "${FLAGGED[@]}" && apt autoremove -y
    else
        echo "  to remove:  sudo apt purge -y ${FLAGGED[*]}"
    fi
fi

# ---------------------------------------------------------- manual pkgs
hdr "Manually installed packages (review by eye)"
apt-mark showmanual 2>/dev/null | sort -u | head -60
echo "  ... $(apt-mark showmanual 2>/dev/null | wc -l) total"

# --------------------------------------------------------------- media
hdr "Media files in user and web directories"
mapfile -t MEDIA < <(find /home /root /srv /var/www \
    \( -path '*/.cache/*' -o -path '*/.local/share/Trash/*' -o -path '*/site-packages/*' \
       -o -path '*/node_modules/*' -o -path '*/.mozilla/*' \) -prune -o \
    -type f \
    \( -iname '*.mp3' -o -iname '*.mp4' -o -iname '*.wav' -o -iname '*.avi' \
       -o -iname '*.mkv' -o -iname '*.flac' -o -iname '*.mov' -o -iname '*.m4a' \
       -o -iname '*.wmv' -o -iname '*.ogg' -o -iname '*.midi' \) -print 2>/dev/null | sort)
if (( ${#MEDIA[@]} == 0 )); then
    echo "none"
else
    printf '  %s\n' "${MEDIA[@]}"
    if $QUARANTINE; then
        mkdir -p "$HOLD/media"
        for f in "${MEDIA[@]}"; do
            mkdir -p "$HOLD/media/$(dirname "$f")"
            mv "$f" "$HOLD/media/$f" 2>/dev/null && echo "  moved: $f"
        done
        echo "  -> $HOLD/media"
    else
        echo "  re-run with --quarantine to move these to $HOLD"
    fi
fi

# ------------------------------------------------------ hacking scripts
hdr "Scripts and credential files in home directories"
find /home /root -type f \( -name '*.sh' -o -name '*.py' -o -name '*.pl' \) 2>/dev/null | head -40
find /home /root -type f \( -iname '*pass*' -o -iname '*cred*' -o -iname '*.key' \) 2>/dev/null | head -20
echo "  (read these before deleting - they may answer a forensics question)"

# --------------------------------------------------------- persistence
hdr "Listening services"
ss -tulpn 2>/dev/null | tail -n +2

hdr "Cron"
for f in /etc/crontab /etc/cron.d/* /var/spool/cron/crontabs/*; do
    [[ -f $f ]] || continue
    echo "--- $f"
    grep -vE '^\s*#|^\s*$' "$f" 2>/dev/null | sed 's/^/    /'
done

hdr "systemd units outside the package manager"
for u in /etc/systemd/system/*.service /home/*/.config/systemd/user/*.service; do
    [[ -f $u ]] || continue
    echo "--- $u"
    grep -E '^(ExecStart|User|Description)' "$u" 2>/dev/null | sed 's/^/    /'
done

hdr "Startup persistence"
for f in /etc/rc.local /etc/ld.so.preload /etc/profile.d/*; do
    [[ -f $f ]] || continue
    echo "--- $f"; sed 's/^/    /' "$f" 2>/dev/null | head -10
done

hdr "Unexpected SUID binaries"
find / -xdev -type f -perm -4000 2>/dev/null | grep -vE '/(sudo|su|passwd|chsh|chfn|newgrp|gpasswd|mount|umount|ping|fusermount3?|pkexec|ssh-agent|unix_chkpwd|dbus-daemon-launch-helper|polkit-agent-helper-1|snap-confine)$' | sed 's/^/  /'

hdr "Done"
$QUARANTINE && echo "Quarantined files are in $HOLD - nothing was deleted."
$PURGE || $QUARANTINE || echo "Report only. Use --quarantine and/or --purge to act."
