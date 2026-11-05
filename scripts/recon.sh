#!/usr/bin/env bash
#
# recon.sh - discovery for CyberPatriot Linux images
#
# Everything here needs YOUR judgment against the image README. The
# deterministic hardening is harden.sh's job and is not duplicated.
#
# READ-ONLY by default. Two optional flags act, and only on the two things
# that are safe to act on once you have read the README:
#
#   sudo bash recon.sh                   # report only  -> ./recon-<timestamp>/
#   sudo bash recon.sh --quarantine      # MOVE flagged media to /root/cp-quarantine
#   sudo bash recon.sh --purge           # apt purge flagged prohibited packages
#
set -uo pipefail

OUT="" ; QUARANTINE=false ; PURGE=false
HOLD="/root/cp-quarantine"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --quarantine) QUARANTINE=true ;;
        --purge)      PURGE=true ;;
        -h|--help)    sed -n '2,16p' "$0"; exit 0 ;;
        *)            OUT="$1" ;;
    esac
    shift
done
OUT="${OUT:-./recon-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT"

[[ $EUID -ne 0 ]] && echo "Not running as root - results will be incomplete. Re-run with sudo." >&2

say() { printf '\n[*] %s\n' "$1"; }
cap() { cat > "$OUT/$1"; printf '    -> %-26s %s\n' "$1" "$2"; }

echo "recon.sh - writing to $OUT"

# ---------------------------------------------------------------- system
say "System identity"
{
    echo "=== os-release ==="; cat /etc/os-release 2>/dev/null
    echo; echo "=== linuxmint ==="; cat /etc/linuxmint/info 2>/dev/null
    echo; echo "=== debian_version ==="; cat /etc/debian_version 2>/dev/null
    echo; echo "=== upstream base ==="; cat /etc/upstream-release/lsb-release 2>/dev/null
    echo; echo "=== kernel ==="; uname -a
    echo; echo "=== desktop / display manager ==="
    cat /etc/X11/default-display-manager 2>/dev/null
    dpkg-query -W -f='${Package}\n' 'task-*-desktop' 'mint-info-*' 2>/dev/null
    echo; echo "=== uptime ==="; uptime
} | cap system.txt "OS, kernel, desktop"

# ----------------------------------------------------------------- users
say "Users and groups"
{
    echo "=== all accounts by UID (humans sort to the bottom) ==="
    awk -F: '{printf "%-20s %-7s %s\n", $1, $3, $7}' /etc/passwd | sort -k2 -n

    echo; echo "=== UID 0  [anything but root is a finding] ==="
    awk -F: '$3 == 0 {print $1}' /etc/passwd

    echo; echo "=== privileged groups ==="
    grep -E '^(sudo|admin|wheel|adm|shadow|disk|root|docker|lpadmin):' /etc/group 2>/dev/null

    echo; echo "=== empty passwords  [findings] ==="
    awk -F: '$2 == "" {print $1}' /etc/shadow 2>/dev/null

    echo; echo "=== system accounts with a login shell  [review] ==="
    awk -F: '$3 < 1000 && $7 !~ /(nologin|false|sync|shutdown|halt)/ {print $1": "$7}' /etc/passwd

    echo; echo "=== duplicate UIDs / usernames ==="
    cut -d: -f3 /etc/passwd | sort | uniq -d
    cut -d: -f1 /etc/passwd | sort | uniq -d

    echo; echo "=== sudoers drop-ins ==="
    ls -la /etc/sudoers.d/ 2>/dev/null
    grep -rhE 'NOPASSWD|!authenticate|ALL=\(ALL' /etc/sudoers /etc/sudoers.d/ 2>/dev/null

    echo; echo "=== password aging ==="
    for u in $(awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' /etc/passwd); do
        printf '%-16s %s\n' "$u" "$(chage -l "$u" 2>/dev/null | tr '\n' ' ')"
    done
} | cap users.txt "accounts, privileged groups, sudoers"

# -------------------------------------------------------------- packages
say "Packages"
apt-mark showmanual 2>/dev/null | sort -u | cap manual-packages.txt "manually installed"

{
    if [[ -f /var/log/installer/initial-status.gz ]]; then
        echo "=== installed on top of the base image ==="
        comm -23 <(apt-mark showmanual 2>/dev/null | sort -u) \
                 <(gzip -dc /var/log/installer/initial-status.gz | sed -n 's/^Package: //p' | sort -u)
    else
        echo "No /var/log/installer/initial-status.gz (normal on Debian)."
        echo "Use baseline-diff.sh for the added-package list, or read manual-packages.txt."
    fi
} | cap added-packages.txt "added after install"

BAD_PKGS='^(ophcrack|john|johnny|hydra|hashcat|medusa|aircrack-ng|ettercap-[a-z]+|nikto|sqlmap|metasploit[a-z-]*|wireshark|tshark|netcat[a-z-]*|ncat|nmap|nmapsi4|zenmap|telnetd|telnet-server|rsh-server|tftpd[a-z-]*|hping3|kismet|crack|cewl|dirb|wfuzz|responder|bettercap|vsftpd|minetest|freeciv|aisleriot|gnome-mahjongg|gnome-sudoku|gnome-mines|transmission[a-z-]*|deluge[a-z-]*|qbittorrent|frostwire|vuze|vnc4server|tightvncserver|x11vnc)$'
mapfile -t FLAGGED < <(dpkg-query -W -f='${Package}\n' 2>/dev/null | grep -E "$BAD_PKGS" || true)
{
    echo "### Prohibited / suspicious packages ###"
    if (( ${#FLAGGED[@]} == 0 )); then
        echo "none matched"
    else
        printf '%s\n' "${FLAGGED[@]}"
        echo
        echo "CHECK THE README FIRST - nmap, wireshark and vsftpd are sometimes required."
        echo "Remove with:  sudo apt purge -y ${FLAGGED[*]}"
    fi
} | cap prohibited-packages.txt "known-bad software"

if command -v debsums >/dev/null 2>&1; then
    debsums -c 2>/dev/null | cap changed-files.txt "package files modified since install"
else
    { echo "debsums not installed. Either:"
      echo "  sudo apt install -y debsums && sudo debsums -c"
      echo "or, with no install:"
      echo "  cd / && sudo md5sum -c /var/lib/dpkg/info/*.md5sums 2>/dev/null | grep ': FAILED\$'"
    } | cap changed-files.txt "SKIPPED - see file for alternative"
fi

# -------------------------------------------------------------- network
say "Network"
{
    echo "=== listening sockets ==="; ss -tulpn 2>/dev/null
    echo; echo "=== established ==="; ss -tupn state established 2>/dev/null
} | cap listening.txt "open ports and owning processes"

{
    echo "=== ufw ==="; ufw status verbose 2>/dev/null || echo "ufw not installed"
    echo; echo "=== nftables / iptables ==="; nft list ruleset 2>/dev/null | head -40 || iptables -L -n 2>/dev/null | head -40
    echo; echo "=== hosts ==="; cat /etc/hosts
    echo; echo "=== hosts.allow ==="; cat /etc/hosts.allow 2>/dev/null
    echo; echo "=== hosts.deny ==="; cat /etc/hosts.deny 2>/dev/null
    echo; echo "=== resolv.conf ==="; cat /etc/resolv.conf 2>/dev/null
} | cap firewall.txt "firewall and host access"

# ----------------------------------------------------------- persistence
say "Persistence"
{
    echo "=== /etc/crontab ==="; grep -vE '^\s*#|^\s*$' /etc/crontab 2>/dev/null
    echo; echo "=== /etc/cron.d ==="
    for f in /etc/cron.d/*; do [[ -f $f ]] || continue; echo "--- $f"; grep -vE '^\s*#|^\s*$' "$f"; done
    for d in hourly daily weekly monthly; do
        echo; echo "=== /etc/cron.$d ==="; ls -la "/etc/cron.$d/" 2>/dev/null
    done
    echo; echo "=== user crontabs ==="
    for f in /var/spool/cron/crontabs/*; do [[ -e $f ]] || continue; echo "--- $f"; cat "$f"; done
    echo; echo "=== at jobs ==="; atq 2>/dev/null
} | cap cron.txt "scheduled tasks"

{
    echo "=== units outside the package manager ==="
    for u in /etc/systemd/system/*.service /etc/systemd/system/*.timer /home/*/.config/systemd/user/*.service; do
        [[ -f $u ]] || continue
        echo "--- $u"
        grep -E '^(Description|ExecStart|User|WantedBy)' "$u" 2>/dev/null | sed 's/^/    /'
    done
    echo; echo "=== enabled services ==="
    systemctl list-unit-files --type=service --state=enabled --no-legend --no-pager 2>/dev/null | awk '{print $1}'
    echo; echo "=== running services ==="
    systemctl list-units --type=service --state=running --no-legend --no-pager 2>/dev/null | awk '{print $1}'
    echo; echo "=== timers ==="; systemctl list-timers --all --no-pager 2>/dev/null
} | cap systemd.txt "services, timers, custom units"

{
    echo "=== /etc/rc.local ==="; cat /etc/rc.local 2>/dev/null
    echo; echo "=== /etc/ld.so.preload ==="; cat /etc/ld.so.preload 2>/dev/null
    echo; echo "=== /etc/profile.d ==="
    for f in /etc/profile.d/*; do [[ -f $f ]] || continue; echo "--- $f ($(wc -l <"$f") lines)"; done
    echo; echo "=== shell rc files (last 15 lines each) ==="
    for f in /home/*/.bashrc /home/*/.profile /root/.bashrc /root/.profile; do
        [[ -e $f ]] || continue; echo "--- $f"; tail -15 "$f"
    done
} | cap startup.txt "startup and shell persistence"

# ------------------------------------------------------------- forensics
say "Forensic artifacts"
{
    for f in /home/*/.bash_history /root/.bash_history /home/*/.zsh_history; do
        [[ -e $f ]] || continue; echo "=== $f ==="; cat "$f"; echo
    done
} | cap history.txt "shell history - READ THIS FIRST"

{
    echo "=== authorized_keys ==="
    for f in /home/*/.ssh/authorized_keys /root/.ssh/authorized_keys; do
        [[ -e $f ]] || continue; echo "--- $f"; cat "$f"
    done
    echo; echo "=== recent logins ==="; last -20 2>/dev/null
    echo; echo "=== failed logins ==="; lastb -20 2>/dev/null
    if [[ -f /var/log/auth.log ]]; then
        echo; echo "=== sudo use ==="; grep -i 'sudo:' /var/log/auth.log 2>/dev/null | tail -30
        echo; echo "=== accepted ssh ==="; grep -i 'Accepted' /var/log/auth.log 2>/dev/null | tail -20
        echo; echo "=== failed passwords ==="; grep -i 'Failed password' /var/log/auth.log 2>/dev/null | tail -20
    else
        echo; echo "=== no /var/log/auth.log - using journald ==="
        echo; echo "=== sudo ==="; journalctl _COMM=sudo --no-pager 2>/dev/null | tail -30
        echo; echo "=== su ==="; journalctl _COMM=su --no-pager 2>/dev/null | tail -20
        echo; echo "=== ssh ==="; journalctl -u ssh -u sshd --no-pager 2>/dev/null | grep -iE 'Accepted|Failed' | tail -30
    fi
} | cap auth.txt "ssh keys and login history"

# ----------------------------------------------------------- permissions
say "Permissions and files (takes a moment)"

# known-good SUID set - anything outside it is worth a look
SUID_OK='/(sudo|su|passwd|chfn|chsh|newgrp|gpasswd|mount|umount|ping|fusermount3?|pkexec|ssh-agent|ssh-keysign|unix_chkpwd|pam_extrausers_chkpwd|dbus-daemon-launch-helper|polkit-agent-helper-1|snap-confine|Xorg\.wrap|chrome-sandbox|vmware-user-suid-wrapper|mount\.cifs|mount\.ecryptfs_private|pppd|expiry|crontab|wall|write|plocate|camel-lock-helper.*)$'

find / -xdev -type f -perm -4000 2>/dev/null | sort | cap suid-all.txt "all SUID binaries"
grep -Ev "$SUID_OK" "$OUT/suid-all.txt" | cap suid-unexpected.txt "SUID outside the known-good set"
find / -xdev -type f -perm -2000 2>/dev/null | sort | cap sgid.txt "SGID binaries"
find / -xdev -type f -perm -0002 2>/dev/null | sort | cap world-writable.txt "world-writable files"
find / -xdev \( -nouser -o -nogroup \) 2>/dev/null | sort | cap unowned.txt "files with no owner"

mapfile -t MEDIA < <(find /home /root /srv /var/www \
    \( -path '*/.cache/*' -o -path '*/.local/share/Trash/*' -o -path '*/site-packages/*' \
       -o -path '*/node_modules/*' -o -path '*/.mozilla/*' -o -path '*/.config/*' \) -prune -o \
    -type f \( -iname '*.mp3' -o -iname '*.mp4' -o -iname '*.wav' -o -iname '*.avi' \
       -o -iname '*.mkv' -o -iname '*.flac' -o -iname '*.mov' -o -iname '*.m4a' \
       -o -iname '*.wmv' -o -iname '*.ogg' -o -iname '*.midi' \) -print 2>/dev/null | sort)
printf '%s\n' "${MEDIA[@]}" | cap media.txt "media files (often prohibited)"

{
    echo "=== scripts in home directories ==="
    find /home /root -maxdepth 4 -type f \( -name '*.sh' -o -name '*.py' -o -name '*.pl' \) 2>/dev/null | head -40
    echo; echo "=== possible credential files ==="
    find /home /root -maxdepth 4 -type f \( -iname '*pass*' -o -iname '*cred*' -o -iname '*.key' \) 2>/dev/null | head -20
    echo; echo "=== core file permissions ==="
    ls -la /etc/passwd /etc/shadow /etc/group /etc/gshadow /etc/sudoers 2>/dev/null
    echo; echo "=== home directories ==="; ls -la /home/
    echo; echo "=== web root ==="; ls -la /var/www/html 2>/dev/null
    echo; echo "=== possible web shells ==="
    grep -rlniE 'eval\(|base64_decode|shell_exec|passthru|system\(' /var/www 2>/dev/null | head -10
} | cap files.txt "sensitive files, scripts, web root"

# ------------------------------------------------------------- optional acting
if $QUARANTINE && (( ${#MEDIA[@]} > 0 )); then
    say "Quarantining media (moving, not deleting)"
    mkdir -p "$HOLD/media"
    for f in "${MEDIA[@]}"; do
        [[ -e $f ]] || continue
        mkdir -p "$HOLD/media/$(dirname "$f")"
        mv "$f" "$HOLD/media/$f" 2>/dev/null && echo "    moved: $f"
    done
    echo "    -> $HOLD/media  (nothing deleted)"
fi

if $PURGE && (( ${#FLAGGED[@]} > 0 )); then
    say "Purging prohibited packages"
    apt purge -y "${FLAGGED[@]}" && apt autoremove -y
fi

# -------------------------------------------------------------- summary
say "Done"
{
    echo "recon.sh summary - $(date)"
    echo
    printf 'UID 0 besides root          : %s\n' "$(awk -F: '$3==0 && $1!="root"' /etc/passwd | wc -l)"
    printf 'Empty-password accounts     : %s\n' "$(awk -F: '$2==""' /etc/shadow 2>/dev/null | wc -l)"
    printf 'Human accounts (UID>=1000)  : %s\n' "$(awk -F: '$3>=1000 && $3<65534' /etc/passwd | wc -l)"
    printf 'Prohibited packages flagged : %s\n' "${#FLAGGED[@]}"
    printf 'Manually installed packages : %s\n' "$(apt-mark showmanual 2>/dev/null | wc -l)"
    printf 'Listening TCP/UDP sockets   : %s\n' "$(ss -tuln 2>/dev/null | tail -n +2 | wc -l)"
    printf 'Unexpected SUID binaries    : %s\n' "$(grep -c . "$OUT/suid-unexpected.txt")"
    printf 'World-writable files        : %s\n' "$(grep -c . "$OUT/world-writable.txt")"
    printf 'Unowned files               : %s\n' "$(grep -c . "$OUT/unowned.txt")"
    printf 'Media files in home/web     : %s\n' "${#MEDIA[@]}"
    printf 'UFW                         : %s\n' "$(ufw status 2>/dev/null | head -1 || echo 'not installed')"
    echo
    echo "Read in this order:"
    echo "  history.txt            what was done on this box"
    echo "  auth.txt               who logged in, and any planted ssh keys"
    echo "  users.txt              accounts, privileged groups, sudoers"
    echo "  prohibited-packages.txt"
    echo "  changed-files.txt      tampered package files"
    echo "  listening.txt          services you did not expect"
    echo "  cron.txt / systemd.txt / startup.txt   persistence"
    echo "  suid-unexpected.txt    privilege escalation"
    echo "  media.txt / files.txt"
    echo
    echo "Everything here needs the README to interpret. Deterministic hardening is harden.sh."
} | tee "$OUT/SUMMARY.txt"

echo
echo "Output in: $OUT"
$QUARANTINE || $PURGE || echo "Report only. --quarantine moves media, --purge removes flagged packages."
