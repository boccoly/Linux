#!/usr/bin/env bash
#
# users.sh - reconcile accounts against the image README's authorized list
#
# DRY RUN BY DEFAULT. Prints what it would do and changes nothing.
# Re-run with --apply once the plan looks right.
#
# Usage:
#   sudo bash users.sh authorized.txt                      # dry run
#   sudo bash users.sh authorized.txt --apply              # do it
#   sudo bash users.sh authorized.txt --apply --password 'P@ssw0rd!2026'
#   sudo bash users.sh authorized.txt --apply --remove-home
#
# authorized.txt format - one per line, "name role", role is admin or user:
#   alice admin
#   bob   user
#   # comments and blank lines ignored
#
set -uo pipefail

LIST="" ; APPLY=false ; REMOVE_HOME=false ; PASSWORD=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply)       APPLY=true ;;
        --remove-home) REMOVE_HOME=true ;;
        --password)    PASSWORD="${2:-}"; shift ;;
        -h|--help)     sed -n '2,20p' "$0"; exit 0 ;;
        *)             LIST="$1" ;;
    esac
    shift
done

[[ -z $LIST || ! -f $LIST ]] && { echo "Need an authorized-users file. See --help." >&2; exit 1; }
[[ $EUID -ne 0 ]] && { echo "Run with sudo." >&2; exit 1; }

# Never touch these, whatever the list says.
ME="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"
PROTECTED=("root" "nobody" "$ME")

is_protected() { local u=$1; for p in "${PROTECTED[@]}"; do [[ $u == "$p" ]] && return 0; done; return 1; }

# ------------------------------------------------------------ parse list
declare -A ROLE
while read -r name role _; do
    [[ -z ${name:-} || ${name:0:1} == "#" ]] && continue
    role="${role:-user}"
    ROLE["$name"]="$role"
done < "$LIST"

(( ${#ROLE[@]} == 0 )) && { echo "No users parsed from $LIST." >&2; exit 1; }

echo "Authorized: ${#ROLE[@]} accounts   (protected: ${PROTECTED[*]})"
$APPLY && echo "MODE: APPLY - changes will be made" || echo "MODE: DRY RUN - nothing will change"
echo

run() { # run <description> <command...>
    if $APPLY; then
        printf '  [do]   %s\n' "$1"
        shift; "$@" >/dev/null 2>&1 || printf '         ^ FAILED\n'
    else
        printf '  [plan] %s\n' "$1"
    fi
}

# ------------------------------------------------- unauthorized accounts
echo "== Unauthorized accounts =="
found=0
while read -r u; do
    is_protected "$u" && continue
    [[ -n ${ROLE[$u]+x} ]] && continue
    found=1
    if $REMOVE_HOME; then
        run "remove $u (and home dir)" deluser --remove-home "$u"
    else
        run "remove $u (keeping home dir)" deluser "$u"
    fi
done < <(awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' /etc/passwd)
(( found == 0 )) && echo "  none"
echo

# --------------------------------------------------- UID 0 impersonators
echo "== Extra UID 0 accounts =="
found=0
while read -r u; do
    [[ $u == root ]] && continue
    found=1
    echo "  [!] $u has UID 0 - review manually, do not auto-remove"
done < <(awk -F: '$3 == 0 {print $1}' /etc/passwd)
(( found == 0 )) && echo "  none"
echo

# -------------------------------------------------------- missing users
echo "== Missing authorized accounts =="
found=0
for u in "${!ROLE[@]}"; do
    id "$u" &>/dev/null && continue
    found=1
    run "create $u" useradd -m -s /bin/bash "$u"
done
(( found == 0 )) && echo "  none"
echo

# ------------------------------------------------------ group membership
echo "== Admin group membership =="
ADMIN_GROUP=sudo
getent group sudo >/dev/null || ADMIN_GROUP=admin
found=0
for u in "${!ROLE[@]}"; do
    id "$u" &>/dev/null || $APPLY || true
    in_group=false
    id -nG "$u" 2>/dev/null | tr ' ' '\n' | grep -qx "$ADMIN_GROUP" && in_group=true
    if [[ ${ROLE[$u]} == admin ]] && ! $in_group; then
        found=1; run "add $u to $ADMIN_GROUP" usermod -aG "$ADMIN_GROUP" "$u"
    elif [[ ${ROLE[$u]} != admin ]] && $in_group; then
        found=1; run "remove $u from $ADMIN_GROUP" deluser "$u" "$ADMIN_GROUP"
    fi
done
# anyone in the admin group who isn't on the list at all
while read -r u; do
    is_protected "$u" && continue
    [[ -n ${ROLE[$u]+x} ]] && continue
    found=1; run "remove unlisted $u from $ADMIN_GROUP" deluser "$u" "$ADMIN_GROUP"
done < <(getent group "$ADMIN_GROUP" | cut -d: -f4 | tr ',' '\n' | grep -v '^$')
(( found == 0 )) && echo "  none"
echo

# -------------------------------------------------------------- passwords
echo "== Passwords =="
if [[ -z $PASSWORD ]]; then
    echo "  skipped - pass --password 'SomeP@ss!' to set them"
else
    if $APPLY; then
        for u in "${!ROLE[@]}"; do
            is_protected "$u" && continue
            echo "$u:$PASSWORD" | chpasswd 2>/dev/null \
                && echo "  [do]   set password for $u" \
                || echo "  [do]   set password for $u  ^ FAILED"
        done
    else
        echo "  [plan] set password on ${#ROLE[@]} accounts via chpasswd"
    fi
fi
echo

# ------------------------------------------------------------- aging
echo "== Password aging (90/7/14) =="
if $APPLY; then
    for u in "${!ROLE[@]}"; do
        is_protected "$u" && continue
        chage -M 90 -m 7 -W 14 "$u" 2>/dev/null
    done
    echo "  [do]   applied to ${#ROLE[@]} accounts"
else
    echo "  [plan] chage -M 90 -m 7 -W 14 on ${#ROLE[@]} accounts"
fi
echo

# --------------------------------------------------- system account hygiene
echo "== System accounts with login shells =="
found=0
while read -r u shell; do
    [[ $u == root ]] && continue
    [[ $u =~ ^(sync|shutdown|halt)$ ]] && continue
    found=1
    run "lock $u and set nologin (was $shell)" bash -c "usermod -L '$u'; usermod -s /usr/sbin/nologin '$u'"
done < <(awk -F: '$3 < 1000 && $7 !~ /(nologin|false)/ {print $1" "$7}' /etc/passwd)
(( found == 0 )) && echo "  none"
echo

$APPLY || echo "Dry run complete. Re-run with --apply to execute."
