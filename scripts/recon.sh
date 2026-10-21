#!/usr/bin/env bash
#
# recon.sh - read-only enumeration for CyberPatriot Linux images
#
# Changes NOTHING. Collects system state into a timestamped directory
# so you can read it and decide what to fix.
#
# Usage:  sudo bash recon.sh [output-dir]
#
set -uo pipefail

OUT="${1:-./recon-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT"

if [[ $EUID -ne 0 ]]; then
    echo "Not running as root - results will be incomplete. Re-run with sudo." >&2
fi

say() { printf '\n[*] %s\n' "$1"; }
cap() { # cap <file> <description>; command output on stdin
    cat > "$OUT/$1"
    printf '    -> %-24s %s\n' "$1" "$2"
}

echo "recon.sh - writing to $OUT"

# ---------------------------------------------------------------- system
say "System identity"
{
    echo "=== /etc/linuxmint/info ==="; cat /etc/linuxmint/info 2>/dev/null
    echo; echo "=== lsb_release ==="; lsb_release -a 2>/dev/null
    echo; echo "=== upstream base ==="; cat /etc/upstream-release/lsb-release 2>/dev/null
    echo; echo "=== kernel ==="; uname -a
    echo; echo "=== uptime ==="; uptime
} | cap system.txt "OS version and kernel"

# ----------------------------------------------------------------- users
say "Users and groups"
{
    echo "=== human accounts (UID >= 1000) ==="
    awk -F: '$3 >= 1000 && $1 != "nobody" {print $1" (uid "$3", shell "$7")"}' /etc/passwd

    echo; echo "=== UID 0 accounts  [any entry other than root is a finding] ==="
    awk -F: '$3 == 0 {print $1}' /etc/passwd

    echo; echo "=== sudo / admin / wheel membership ==="
    grep -E '^(sudo|admin|wheel):' /etc/group 2>/dev/null

    echo; echo "=== empty passwords  [findings] ==="
    awk -F: '$2 == "" {print $1}' /etc/shadow 2>/dev/null

    echo; echo "=== system accounts with a login shell  [review] ==="
    awk -F: '$3 < 1000 && $7 !~ /(nologin|false|sync|shutdown|halt)/ {print $1": "$7}' /etc/passwd

    echo; echo "=== duplicate UIDs ==="
    cut -d: -f3 /etc/passwd | sort | uniq -d

    echo; echo "=== password aging ==="
    for u in $(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd); do
        printf '%-16s %s\n' "$u" "$(chage -l "$u" 2>/dev/null | tr '\n' ' ')"
    done
} | cap users.txt "accounts, sudo, password policy"

# -------------------------------------------------------------- packages
say "Packages"
apt-mark showmanual 2>/dev/null | sort -u | cap manual-packages.txt "manually installed packages"

{
    if [[ -f /var/log/installer/initial-status.gz ]]; then
        echo "=== installed on top of the base image ==="
        comm -23 <(apt-mark showmanual 2>/dev/null | sort -u) \
                 <(gzip -dc /var/log/installer/initial-status.gz | sed -n 's/^Package: //p' | sort -u)
    else
        echo "No /var/log/installer/initial-status.gz on this image."
        echo "Read manual-packages.txt directly instead."
    fi
} | cap added-packages.txt "packages added after install"

{
    echo "=== suspicious package name matches ==="
    apt list --installed 2>/dev/null | grep -iE \
      'ophcrack|john|hydra|hashcat|aircrack|nmap|wireshark|netcat|ncat|telnetd|medusa|ettercap|nikto|sqlmap|metasploit|torrent|aisleriot|mahjongg|gnome-sudoku|minetest|freeciv' \
      || echo "(none matched - still read manual-packages.txt by hand)"
} | cap suspicious-packages.txt "known prohibited software"

if command -v debsums >/dev/null 2>&1; then
    debsums -c 2>/dev/null | cap changed-files.txt "package files modified since install"
else
    echo "debsums not installed. Run: sudo apt install -y debsums" \
        | cap changed-files.txt "SKIPPED - install debsums"
fi

# -------------------------------------------------------------- network
say "Network"
{
    echo "=== listening sockets ==="; ss -tulpn 2>/dev/null
    echo; echo "=== established ==="; ss -tupn state established 2>/dev/null
} | cap listening.txt "open ports and owning processes"

{
    echo "=== ufw ==="; ufw status verbose 2>/dev/null || echo "ufw not available"
    echo; echo "=== iptables ==="; iptables -L -n 2>/dev/null | head -50
    echo; echo "=== hosts ==="; cat /etc/hosts
    echo; echo "=== hosts.allow ==="; cat /etc/hosts.allow 2>/dev/null
    echo; echo "=== hosts.deny ==="; cat /etc/hosts.deny 2>/dev/null
} | cap firewall.txt "firewall and host access rules"

# ----------------------------------------------------------- persistence
say "Persistence"
{
    echo "=== /etc/crontab ==="; cat /etc/crontab 2>/dev/null
    echo; echo "=== /etc/cron.d ==="; ls -la /etc/cron.d/ 2>/dev/null
    for d in hourly daily weekly monthly; do
        echo; echo "=== /etc/cron.$d ==="; ls -la "/etc/cron.$d/" 2>/dev/null
    done
    echo; echo "=== user crontabs ==="
    for f in /var/spool/cron/crontabs/*; do
        [[ -e $f ]] || continue
        echo "--- $f ---"; cat "$f"
    done
    echo; echo "=== at jobs ==="; atq 2>/dev/null
} | cap cron.txt "scheduled tasks"

{
    echo "=== enabled services ==="
    systemctl list-unit-files --type=service --state=enabled 2>/dev/null
    echo; echo "=== running services ==="
    systemctl list-units --type=service --state=running 2>/dev/null
    echo; echo "=== timers ==="; systemctl list-timers --all 2>/dev/null
    echo; echo "=== units outside the package manager ==="
    ls -la /etc/systemd/system/ 2>/dev/null
    echo; echo "=== user units ==="
    ls -la /home/*/.config/systemd/user/ 2>/dev/null
} | cap systemd.txt "services, timers, custom units"

{
    echo "=== /etc/rc.local ==="; cat /etc/rc.local 2>/dev/null
    echo; echo "=== /etc/profile.d ==="; ls -la /etc/profile.d/ 2>/dev/null
    echo; echo "=== /etc/ld.so.preload ==="; cat /etc/ld.so.preload 2>/dev/null
    echo; echo "=== shell rc files ==="
    for f in /home/*/.bashrc /home/*/.profile /root/.bashrc /root/.profile; do
        [[ -e $f ]] || continue
        echo "--- $f (last 15 lines) ---"; tail -15 "$f"
    done
} | cap startup.txt "startup and shell persistence"

# ------------------------------------------------------------- forensics
say "Forensic artifacts"
{
    for f in /home/*/.bash_history /root/.bash_history /home/*/.zsh_history; do
        [[ -e $f ]] || continue
        echo "=== $f ==="; cat "$f"; echo
    done
} | cap history.txt "shell history - READ THIS FIRST"

{
    echo "=== authorized_keys ==="
    for f in /home/*/.ssh/authorized_keys /root/.ssh/authorized_keys; do
        [[ -e $f ]] || continue
        echo "--- $f ---"; cat "$f"
    done
    echo; echo "=== recent logins ==="; last -20 2>/dev/null
    echo; echo "=== failed logins ==="; lastb -20 2>/dev/null
    echo; echo "=== sudo use ==="; grep -i 'sudo:' /var/log/auth.log 2>/dev/null | tail -30
    echo; echo "=== accepted ssh ==="; grep -i 'Accepted' /var/log/auth.log 2>/dev/null | tail -20
} | cap auth.txt "ssh keys and login history"

# ----------------------------------------------------------- permissions
say "Permissions and files (this takes a moment)"
find / -xdev -type f -perm -4000 2>/dev/null | sort | cap suid.txt "SUID binaries"
find / -xdev -type f -perm -2000 2>/dev/null | sort | cap sgid.txt "SGID binaries"
find / -xdev -type f -perm -0002 2>/dev/null | sort | cap world-writable.txt "world-writable files"
find / -xdev \( -nouser -o -nogroup \) 2>/dev/null | sort | cap unowned.txt "files with no owner"

find /home /root /srv /var/www -type f \
    \( -iname '*.mp3' -o -iname '*.mp4' -o -iname '*.wav' -o -iname '*.avi' \
       -o -iname '*.mkv' -o -iname '*.flac' -o -iname '*.mov' -o -iname '*.m4a' \) \
    2>/dev/null | sort | cap media.txt "media files (often prohibited)"

{
    echo "=== possible password files ==="
    find /home /root -type f \( -iname '*pass*' -o -iname '*pw*' -o -iname '*cred*' \) 2>/dev/null
    echo; echo "=== scripts in home dirs ==="
    find /home /root -type f -name '*.sh' 2>/dev/null
    echo; echo "=== core file permissions ==="
    ls -la /etc/passwd /etc/shadow /etc/group /etc/gshadow /etc/sudoers 2>/dev/null
    echo; echo "=== /etc/sudoers.d ==="; ls -la /etc/sudoers.d/ 2>/dev/null
    echo; echo "=== home directory perms ==="; ls -la /home/
} | cap files.txt "sensitive files and permissions"

# -------------------------------------------------------------- summary
say "Done"
{
    echo "recon.sh summary - $(date)"
    echo
    printf 'UID 0 accounts besides root : %s\n' "$(awk -F: '$3==0 && $1!="root"' /etc/passwd | wc -l)"
    printf 'Empty-password accounts     : %s\n' "$(awk -F: '$2==""' /etc/shadow 2>/dev/null | wc -l)"
    printf 'Manually installed packages : %s\n' "$(apt-mark showmanual 2>/dev/null | wc -l)"
    printf 'Listening TCP/UDP sockets   : %s\n' "$(ss -tuln 2>/dev/null | tail -n +2 | wc -l)"
    printf 'SUID binaries               : %s\n' "$(wc -l < "$OUT/suid.txt")"
    printf 'World-writable files        : %s\n' "$(wc -l < "$OUT/world-writable.txt")"
    printf 'Unowned files               : %s\n' "$(wc -l < "$OUT/unowned.txt")"
    printf 'Media files in home/web     : %s\n' "$(wc -l < "$OUT/media.txt")"
    printf 'UFW active                  : %s\n' "$(ufw status 2>/dev/null | head -1)"
    echo
    echo "Read in this order: history.txt, auth.txt, users.txt,"
    echo "added-packages.txt, changed-files.txt, listening.txt, cron.txt"
} | tee "$OUT/SUMMARY.txt"

echo
echo "Output in: $OUT"
