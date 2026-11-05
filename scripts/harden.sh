#!/usr/bin/env bash
#
# harden.sh - deterministic hardening for Debian / Ubuntu / Mint CyberPatriot images
#
# Only does work that is the SAME on every image. Anything that depends on the
# README (which users are authorized, which services are required, which files
# are prohibited) is deliberately NOT here - that is users.sh and recon.sh.
#
# Every file it touches is backed up first. Risky changes are validated and
# rolled back automatically if validation fails.
#
# Usage:
#   sudo bash harden.sh                      # apply everything
#   sudo bash harden.sh --dry-run            # print what would change
#   sudo bash harden.sh --only sysctl,ufw    # run just these
#   sudo bash harden.sh --skip pam,sshd      # run everything except these
#   sudo bash harden.sh --rollback /root/harden-backup-XXXX
#
# Modules: logindefs aging pam sysctl ufw perms sysaccounts root apparmor
#          auditd unattended sshd displaymanager
#
set -uo pipefail

ALL_MODULES="logindefs aging pam sysctl ufw perms sysaccounts root apparmor auditd unattended sshd displaymanager"
DRY=false ; ONLY="" ; SKIP="" ; ROLLBACK=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)  DRY=true ;;
        --only)     ONLY="${2:-}"; shift ;;
        --skip)     SKIP="${2:-}"; shift ;;
        --rollback) ROLLBACK="${2:-}"; shift ;;
        -h|--help)  sed -n '2,22p' "$0"; exit 0 ;;
        *)          echo "Unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done

[[ $EUID -ne 0 ]] && { echo "Run with sudo." >&2; exit 1; }

# ------------------------------------------------------------------ rollback
if [[ -n $ROLLBACK ]]; then
    [[ -d $ROLLBACK ]] || { echo "No such backup dir: $ROLLBACK" >&2; exit 1; }
    echo "Restoring from $ROLLBACK ..."
    ( cd "$ROLLBACK/files" 2>/dev/null && find . -type f -print0 \
        | while IFS= read -r -d '' f; do
              cp -a "$f" "/${f#./}" && echo "  restored /${f#./}"
          done )
    echo "Done. Restart affected services (ssh, auditd) or reboot."
    exit 0
fi

# ------------------------------------------------------------------- setup
BACKUP="/root/harden-backup-$(date +%Y%m%d-%H%M%S)"
$DRY || mkdir -p "$BACKUP/files"
LOG="${BACKUP}/harden.log"
$DRY || : > "$LOG"

c_ok=$'\e[32m'; c_inf=$'\e[36m'; c_warn=$'\e[33m'; c_err=$'\e[31m'; c_off=$'\e[0m'
ok()   { printf '  %s[ok]%s   %s\n'   "$c_ok"   "$c_off" "$1"; $DRY || echo "OK   $1" >>"$LOG"; }
info() { printf '%s==>%s %s\n'        "$c_inf"  "$c_off" "$1"; $DRY || echo "---  $1" >>"$LOG"; }
warn() { printf '  %s[warn]%s %s\n'   "$c_warn" "$c_off" "$1"; $DRY || echo "WARN $1" >>"$LOG"; }
err()  { printf '  %s[FAIL]%s %s\n'   "$c_err"  "$c_off" "$1"; $DRY || echo "FAIL $1" >>"$LOG"; }
plan() { printf '  [plan] %s\n' "$1"; }

# back up a file before touching it, preserving its path under $BACKUP/files
save() {
    local f="$1"
    [[ -e $f ]] || return 0
    $DRY && return 0
    local d="$BACKUP/files$(dirname "$f")"
    mkdir -p "$d"
    [[ -e "$BACKUP/files$f" ]] || cp -a "$f" "$d/"
}

want() {   # want <module>  -> should this module run?
    local m="$1"
    [[ -n $ONLY ]] && { [[ ",$ONLY," == *",$m,"* ]] && return 0 || return 1; }
    [[ -n $SKIP && ",$SKIP," == *",$m,"* ]] && return 1
    return 0
}

# set key=value in a simple "KEY value" config file, idempotently
setconf() {  # setconf <file> <key> <value>
    local f="$1" k="$2" v="$3"
    if $DRY; then plan "$f: $k $v"; return 0; fi
    save "$f"
    if grep -qE "^[[:space:]]*#?[[:space:]]*${k}[[:space:]]" "$f" 2>/dev/null; then
        sed -i -E "s|^[[:space:]]*#?[[:space:]]*${k}[[:space:]].*|${k}\t${v}|" "$f"
    else
        printf '%s\t%s\n' "$k" "$v" >> "$f"
    fi
}

echo
echo "harden.sh   $( $DRY && echo 'DRY RUN - nothing will change' || echo "applying; backups in $BACKUP" )"
echo

# ============================================================ 1. login.defs
if want logindefs; then
    info "Password aging defaults (/etc/login.defs)"
    setconf /etc/login.defs PASS_MAX_DAYS 90
    setconf /etc/login.defs PASS_MIN_DAYS 7
    setconf /etc/login.defs PASS_WARN_AGE 14
    setconf /etc/login.defs LOGIN_RETRIES 5
    setconf /etc/login.defs UMASK 027
    $DRY || ok "PASS_MAX_DAYS 90 / PASS_MIN_DAYS 7 / PASS_WARN_AGE 14 / UMASK 027"
fi

# ================================================================= 2. aging
if want aging; then
    info "Applying aging to existing human accounts"
    n=0
    while IFS= read -r u; do
        if $DRY; then n=$((n+1)); continue; fi
        chage -M 90 -m 7 -W 14 "$u" 2>/dev/null && n=$((n+1))
    done < <(awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' /etc/passwd)
    $DRY && plan "chage -M 90 -m 7 -W 14 on $n accounts" || ok "chage applied to $n accounts"
fi

# =================================================================== 3. PAM
if want pam; then
    info "PAM password quality and lockout"

    if ! dpkg-query -W libpam-pwquality >/dev/null 2>&1; then
        if $DRY; then plan "apt install libpam-pwquality"
        else
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq libpam-pwquality >/dev/null 2>&1 \
                && ok "installed libpam-pwquality" || warn "could not install libpam-pwquality"
        fi
    fi

    PWQ='password	requisite			pam_pwquality.so retry=3 minlen=14 difok=3 ucredit=-1 lcredit=-1 dcredit=-1 ocredit=-1'
    CP=/etc/pam.d/common-password
    if [[ -f $CP ]]; then
        if $DRY; then
            plan "$CP: add pam_pwquality before pam_unix; add use_authtok/remember=5; drop nullok"
        else
            save "$CP"
            awk -v pwq="$PWQ" '
                /pam_pwquality\.so/ { next }                       # drop old copies, idempotent
                /^password/ && /pam_unix\.so/ && !done {
                    print pwq
                    line = $0
                    gsub(/ nullok/, "", line)
                    if (line !~ /use_authtok/)    line = line " use_authtok"
                    if (line !~ /try_first_pass/) line = line " try_first_pass"
                    if (line !~ /remember=/)      line = line " remember=5"
                    print line
                    done = 1
                    next
                }
                { print }
            ' "$CP" > "$CP.new" && mv "$CP.new" "$CP"
            grep -q pam_pwquality "$CP" && ok "common-password: pwquality + remember=5, nullok removed" \
                                        || { err "common-password edit failed - restoring"; cp -a "$BACKUP/files$CP" "$CP"; }
        fi
    fi

    CA=/etc/pam.d/common-auth
    if [[ -f $CA ]]; then
        if $DRY; then
            plan "$CA: wrap pam_unix with pam_faillock (deny=5 unlock_time=1800); drop nullok"
        else
            save "$CA"
            awk '
                /pam_faillock\.so/ { next }                        # drop old copies, idempotent
                /^auth/ && /pam_unix\.so/ && !done {
                    print "auth\trequired\t\t\tpam_faillock.so preauth silent deny=5 unlock_time=1800"
                    line = $0
                    gsub(/ nullok/, "", line)
                    print line
                    print "auth\t[default=die]\t\t\tpam_faillock.so authfail deny=5 unlock_time=1800"
                    print "auth\tsufficient\t\t\tpam_faillock.so authsucc"
                    done = 1
                    next
                }
                { print }
            ' "$CA" > "$CA.new" && mv "$CA.new" "$CA"

            # structural check: exactly one pam_unix, faillock present, modules exist on disk
            nunix=$(grep -c 'pam_unix\.so' "$CA")
            modok=true
            for m in pam_faillock.so pam_unix.so; do
                find /lib /usr/lib -name "$m" 2>/dev/null | grep -q . || modok=false
            done
            if [[ $nunix -eq 1 ]] && grep -q pam_faillock "$CA" && $modok; then
                ok "common-auth: faillock deny=5 unlock_time=1800, nullok removed"
            else
                err "common-auth looks wrong (pam_unix x$nunix) - restoring backup"
                cp -a "$BACKUP/files$CA" "$CA"
            fi
        fi
    fi
    $DRY || warn "TEST NOW in another terminal:  su - <a normal user>"
fi

# ================================================================ 4. sysctl
if want sysctl; then
    info "Kernel / network hardening (/etc/sysctl.d/99-cyberpatriot.conf)"
    SYSF=/etc/sysctl.d/99-cyberpatriot.conf
    if $DRY; then
        plan "write $SYSF and sysctl --system"
    else
        save "$SYSF"
        cat > "$SYSF" <<'EOF'
# CyberPatriot hardening
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_rfc1337 = 1
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0
kernel.randomize_va_space = 2
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
fs.suid_dumpable = 0
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
EOF
        if sysctl --system >/dev/null 2>&1; then
            ok "applied ($(grep -c '^[a-z]' "$SYSF") parameters incl. tcp_rfc1337, randomize_va_space)"
        else
            warn "sysctl --system reported errors - check 'sysctl --system' output"
        fi
    fi
fi

# =================================================================== 5. UFW
if want ufw; then
    info "Firewall"
    if ! command -v ufw >/dev/null 2>&1; then
        if $DRY; then plan "apt install ufw"
        else
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ufw >/dev/null 2>&1 \
                && ok "installed ufw" || warn "could not install ufw"
        fi
    fi
    if command -v ufw >/dev/null 2>&1; then
        if $DRY; then
            plan "ufw default deny incoming / allow outgoing / enable"
            ss -tlnp 2>/dev/null | awk 'NR>1{split($4,a,":"); print "  [note] listening on port " a[length(a)]}' | sort -u
        else
            ufw --force default deny incoming >/dev/null 2>&1
            ufw --force default allow outgoing >/dev/null 2>&1
            ufw --force enable >/dev/null 2>&1
            ufw logging on >/dev/null 2>&1
            ok "enabled, default deny in / allow out"
            warn "OPEN THE PORTS THE README REQUIRES:  sudo ufw allow 22/tcp"
        fi
    fi
fi

# ================================================================= 6. perms
if want perms; then
    info "Core file permissions"
    if $DRY; then
        plan "chown/chmod passwd 644, shadow 640, group 644, gshadow 640, sudoers 440, /home/* 750"
    else
        chown root:root /etc/passwd /etc/group 2>/dev/null
        chmod 644 /etc/passwd /etc/group 2>/dev/null
        chown root:shadow /etc/shadow /etc/gshadow 2>/dev/null
        chmod 640 /etc/shadow /etc/gshadow 2>/dev/null
        chown root:root /etc/sudoers 2>/dev/null; chmod 440 /etc/sudoers 2>/dev/null
        chmod 600 /boot/grub/grub.cfg 2>/dev/null
        chmod 644 /etc/ssh/sshd_config 2>/dev/null
        for d in /home/*; do [[ -d $d ]] && chmod 750 "$d"; done
        ok "passwd/group 644, shadow/gshadow 640, sudoers 440, home dirs 750"
    fi
fi

# =========================================================== 7. sysaccounts
if want sysaccounts; then
    info "Locking system accounts that have login shells"
    n=0
    while read -r u sh; do
        [[ $u == root ]] && continue
        [[ $u =~ ^(sync|shutdown|halt)$ ]] && continue
        if $DRY; then plan "lock $u (shell was $sh)"; n=$((n+1)); continue; fi
        save /etc/passwd; save /etc/shadow
        usermod -L "$u" 2>/dev/null
        usermod -s /usr/sbin/nologin "$u" 2>/dev/null
        n=$((n+1))
    done < <(awk -F: '$3 < 1000 && $7 !~ /(nologin|false)/ {print $1" "$7}' /etc/passwd)
    $DRY || ok "locked $n system accounts"
fi

# ==================================================================== 8. root
if want root; then
    info "Root account"
    if $DRY; then
        plan "passwd -l root  (disable direct root login; sudo still works)"
    else
        save /etc/shadow
        passwd -l root >/dev/null 2>&1 && ok "root password locked" || warn "could not lock root"
    fi
fi

# =============================================================== 9. AppArmor
if want apparmor; then
    info "AppArmor"
    if command -v aa-status >/dev/null 2>&1; then
        if $DRY; then plan "enable apparmor, set all profiles to enforce"
        else
            systemctl enable --now apparmor >/dev/null 2>&1
            command -v aa-enforce >/dev/null 2>&1 && aa-enforce /etc/apparmor.d/* >/dev/null 2>&1
            ok "enabled; $(aa-status --enforced 2>/dev/null || echo '?') profiles enforcing"
        fi
    else
        warn "apparmor not installed - skipping"
    fi
fi

# ================================================================ 10. auditd
if want auditd; then
    info "Audit daemon"
    if $DRY; then plan "install auditd + identity/scope/module watch rules"
    else
        if ! command -v auditctl >/dev/null 2>&1; then
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq auditd >/dev/null 2>&1 \
                || warn "could not install auditd"
        fi
        if command -v auditctl >/dev/null 2>&1; then
            save /etc/audit/rules.d/cyberpatriot.rules
            cat > /etc/audit/rules.d/cyberpatriot.rules <<'EOF'
-w /etc/passwd -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/sudoers -p wa -k scope
-w /etc/sudoers.d/ -p wa -k scope
-w /var/log/sudo.log -p wa -k actions
-w /var/log/wtmp -p wa -k session
-w /var/log/btmp -p wa -k session
-w /sbin/insmod -p x -k modules
-w /sbin/rmmod -p x -k modules
-w /sbin/modprobe -p x -k modules
EOF
            # never halt the box on a full disk - that costs the whole round
            [[ -f /etc/audit/auditd.conf ]] && {
                save /etc/audit/auditd.conf
                sed -i 's/^admin_space_left_action.*/admin_space_left_action = syslog/;s/^disk_full_action.*/disk_full_action = syslog/;s/^disk_error_action.*/disk_error_action = syslog/' /etc/audit/auditd.conf
            }
            augenrules --load >/dev/null 2>&1
            systemctl enable --now auditd >/dev/null 2>&1
            ok "auditd enabled with identity/scope/module rules (no halt actions)"
        fi
    fi
fi

# =========================================================== 11. unattended
if want unattended; then
    info "Automatic security updates"
    if $DRY; then plan "install unattended-upgrades, enable daily lists + upgrades"
    else
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq unattended-upgrades >/dev/null 2>&1
        save /etc/apt/apt.conf.d/20auto-upgrades
        cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
EOF
        systemctl enable --now unattended-upgrades >/dev/null 2>&1
        ok "unattended-upgrades enabled"
    fi
fi

# ================================================================= 12. sshd
if want sshd; then
    if [[ -f /etc/ssh/sshd_config ]]; then
        info "SSH daemon (safe subset only)"
        # NOTE: PasswordAuthentication, Port and AllowUsers are deliberately NOT
        # touched - those are scenario-dependent and breaking them loses points.
        set_sshd() {
            local k="$1" v="$2" f=/etc/ssh/sshd_config
            if $DRY; then plan "sshd_config: $k $v"; return; fi
            if grep -qE "^[[:space:]]*#?[[:space:]]*${k}[[:space:]]" "$f"; then
                sed -i -E "s|^[[:space:]]*#?[[:space:]]*${k}[[:space:]].*|${k} ${v}|" "$f"
            else
                printf '%s %s\n' "$k" "$v" >> "$f"
            fi
        }
        $DRY || save /etc/ssh/sshd_config
        set_sshd PermitRootLogin no
        set_sshd PermitEmptyPasswords no
        set_sshd X11Forwarding no
        set_sshd MaxAuthTries 4
        set_sshd IgnoreRhosts yes
        set_sshd HostbasedAuthentication no
        set_sshd PermitUserEnvironment no
        set_sshd LoginGraceTime 60
        set_sshd ClientAliveInterval 300
        set_sshd ClientAliveCountMax 0
        set_sshd LogLevel VERBOSE
        set_sshd UsePAM yes
        if ! $DRY; then
            if sshd -t 2>/dev/null; then
                systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
                ok "hardened and restarted (config validated)"
            else
                err "sshd -t FAILED - restoring original, service untouched"
                cp -a "$BACKUP/files/etc/ssh/sshd_config" /etc/ssh/sshd_config
            fi
        fi
    fi
fi

# ======================================================= 13. display manager
if want displaymanager; then
    info "Login screen"
    if [[ -d /etc/lightdm ]]; then
        if $DRY; then plan "lightdm: hide user list, disable guest, no autologin"
        else
            save /etc/lightdm/lightdm.conf
            mkdir -p /etc/lightdm/lightdm.conf.d
            cat > /etc/lightdm/lightdm.conf.d/99-cyberpatriot.conf <<'EOF'
[Seat:*]
greeter-hide-users=true
greeter-show-manual-login=true
allow-guest=false
autologin-user=
EOF
            ok "lightdm: user list hidden, guest disabled"
        fi
    elif [[ -f /etc/gdm3/daemon.conf || -f /etc/gdm3/custom.conf ]]; then
        GDM=$( [[ -f /etc/gdm3/daemon.conf ]] && echo /etc/gdm3/daemon.conf || echo /etc/gdm3/custom.conf )
        if $DRY; then plan "$GDM: disable guest/autologin, hide user list"
        else
            save "$GDM"
            sed -i 's/^[[:space:]]*AutomaticLoginEnable.*/AutomaticLoginEnable=false/' "$GDM"
            grep -q '^disable-user-list' "$GDM" || sed -i '/^\[daemon\]/a disable-user-list=true' "$GDM"
            ok "gdm3: autologin off, user list hidden"
        fi
    else
        warn "no lightdm or gdm3 found - skipping"
    fi
fi

# =============================================================== wrap up
echo
if $DRY; then
    echo "Dry run complete. Re-run without --dry-run to apply."
else
    echo "Done. Backups: $BACKUP"
    echo "Roll back with:  sudo bash $0 --rollback $BACKUP"
    echo
    echo "STILL YOURS TO DO (README-dependent, not automatable):"
    echo "  - open the firewall ports the scenario needs:  sudo ufw allow <port>/tcp"
    echo "  - users and passwords:                          scripts/users.sh"
    echo "  - prohibited software and media:                scripts/recon.sh"
    echo "  - per-service configs for what the image runs"
    echo "  - updates:  apt update && apt dist-upgrade"
    echo
    echo "TEST BEFORE YOU MOVE ON:  su - <normal user>   and   sudo -v"
fi
