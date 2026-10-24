#!/usr/bin/env bash
#
# baseline-diff.sh - compare this image against a clean-system baseline
#
# Read-only. Shows what is DIFFERENT about this machine rather than
# what is on a generic checklist. This is how you find vulnerabilities
# nobody wrote down.
#
# Usage:  sudo bash baseline-diff.sh baseline/mint22 [output-dir]
#
set -uo pipefail

BASE="${1:-}"
OUT="${2:-./basediff-$(date +%Y%m%d-%H%M%S)}"

if [[ -z $BASE || ! -d $BASE ]]; then
    echo "Usage: sudo bash baseline-diff.sh <baseline-dir> [output-dir]" >&2
    echo "Available:" >&2; ls -1 baseline/ 2>/dev/null >&2
    exit 1
fi
[[ $EUID -ne 0 ]] && echo "Not root - results will be incomplete." >&2

mkdir -p "$OUT"
WORK="$OUT/.clean"
mkdir -p "$WORK"

cat "$BASE/BASELINE-INFO" 2>/dev/null
echo "Comparing against: $BASE"
echo

# Pure noise - differs on every install, never a finding.
# NOTE: passwd/shadow/group are deliberately NOT filtered. They always
# differ, and that difference is exactly what you are looking for.
# shadow/gshadow are excluded from the snapshot (credentials), so they would
# otherwise show as spurious "missing". Read them by hand - see checklist/2-users.md.
NOISE='machine-id|/hostname$|/hosts$|resolv\.conf|/fstab$|/mtab$|blkid\.tab|crypttab|ssh/ssh_host_|ssl/private/|lvm/(archive|backup)/|NetworkManager/system-connections/|netplan/|udev/rules\.d/70-persistent|/cups/|printcap|\.cache$|ld\.so\.cache|^etc/shadow|^etc/gshadow|^shadow-?$|^gshadow-?$'

# ------------------------------------------------------------------- etc
echo "[*] Unpacking clean /etc ..."
[[ -d $WORK/etc ]] || unzip -qo "$BASE/etc.zip" -d "$WORK/"

echo "[*] Diffing /etc ..."
( cd "$WORK/etc" && find . -type f -o -type l ) 2>/dev/null | sed 's|^\./||' | sort > "$OUT/.etc-clean"
( cd /etc        && find . -type f -o -type l ) 2>/dev/null | sed 's|^\./||' | sort > "$OUT/.etc-live"

{
    echo "### Files only on THIS image (added after install) ###"
    comm -13 "$OUT/.etc-clean" "$OUT/.etc-live" | grep -Ev "$NOISE"
} > "$OUT/etc-added.txt"

{
    echo "### Files MISSING from this image (deleted) ###"
    comm -23 "$OUT/.etc-clean" "$OUT/.etc-live" | grep -Ev "$NOISE"
} > "$OUT/etc-missing.txt"

{
    echo "### Content differences (clean vs live) ###"
    while read -r f; do
        [[ -f "$WORK/etc/$f" && -f "/etc/$f" ]] || continue
        cmp -s "$WORK/etc/$f" "/etc/$f" || echo "$f"
    done < <(comm -12 "$OUT/.etc-clean" "$OUT/.etc-live" | grep -Ev "$NOISE")
} > "$OUT/etc-changed.txt"

# Full text diff of the files that changed, for reading
{
    diff -ru --no-dereference "$WORK/etc" /etc 2>/dev/null
} > "$OUT/etc-full.diff"

# -------------------------------------------------------------- packages
echo "[*] Diffing packages ..."
dpkg-query -W -f='${Package}\n' 2>/dev/null | sort -u > "$OUT/.pkgs-now"
{
    echo "### Packages ADDED since clean install ###"
    comm -23 "$OUT/.pkgs-now" "$BASE/pkgorig.txt"
} > "$OUT/pkg-added.txt"
{
    echo "### Packages REMOVED since clean install ###"
    comm -13 "$OUT/.pkgs-now" "$BASE/pkgorig.txt"
} > "$OUT/pkg-removed.txt"

# ------------------------------------------------------------------ state
echo "[*] Diffing system state ..."
cmpfile() { # cmpfile <baseline-file> <live-command-output-file> <out> <label>
    { echo "### $4 ###"
      echo "--- only on THIS image ---"; comm -23 "$2" "$1"
      echo "--- missing from this image ---"; comm -13 "$2" "$1"
    } > "$3"
}

find / -xdev -type f -perm -4000 2>/dev/null | sort > "$OUT/.suid-now"
cmpfile "$BASE/suid.txt" "$OUT/.suid-now" "$OUT/suid-diff.txt" "SUID binaries"

find / -xdev -type f -perm -0002 2>/dev/null | sort > "$OUT/.ww-now"
cmpfile "$BASE/world-writable.txt" "$OUT/.ww-now" "$OUT/world-writable-diff.txt" "World-writable files"

systemctl list-unit-files --type=service --state=enabled --no-legend --no-pager 2>/dev/null \
    | awk '{print $1}' | sort > "$OUT/.svc-now"
cmpfile "$BASE/services-enabled.txt" "$OUT/.svc-now" "$OUT/services-diff.txt" "Enabled services"

awk -F: '{print $1":"$3":"$7}' /etc/passwd | sort > "$OUT/.passwd-now"
cmpfile "$BASE/passwd.txt" "$OUT/.passwd-now" "$OUT/users-diff.txt" "Accounts (name:uid:shell)"

awk -F: '{print $1":"$3":"$4}' /etc/group | sort > "$OUT/.group-now"
cmpfile "$BASE/group.txt" "$OUT/.group-now" "$OUT/groups-diff.txt" "Groups (name:gid:members)"

rm -f "$OUT"/.pkgs-now "$OUT"/.suid-now "$OUT"/.ww-now "$OUT"/.svc-now "$OUT"/.passwd-now "$OUT"/.group-now "$OUT"/.etc-clean "$OUT"/.etc-live

# ---------------------------------------------------------------- summary
{
    echo "baseline-diff summary - $(date)"
    echo "baseline: $BASE"
    echo
    printf 'Accounts/groups changed   : %s\n' "$(( $(grep -cv '^#\|^---' "$OUT/users-diff.txt") + $(grep -cv '^#\|^---' "$OUT/groups-diff.txt") ))"
    printf 'Packages added            : %s\n' "$(grep -cv '^#' "$OUT/pkg-added.txt")"
    printf 'Packages removed          : %s\n' "$(grep -cv '^#' "$OUT/pkg-removed.txt")"
    printf '/etc files added          : %s\n' "$(grep -cv '^#' "$OUT/etc-added.txt")"
    printf '/etc files missing        : %s\n' "$(grep -cv '^#' "$OUT/etc-missing.txt")"
    printf '/etc files changed        : %s\n' "$(grep -cv '^#' "$OUT/etc-changed.txt")"
    printf 'SUID differences          : %s\n' "$(grep -cv '^#\|^---' "$OUT/suid-diff.txt")"
    printf 'Enabled-service diffs     : %s\n' "$(grep -cv '^#\|^---' "$OUT/services-diff.txt")"
    echo
    echo "Read in this order:"
    echo "  users-diff.txt      unauthorized and hidden accounts"
    echo "  pkg-added.txt       prohibited software, unexpected servers"
    echo "  etc-changed.txt     tampered configs  (details in etc-full.diff)"
    echo "  services-diff.txt   things enabled that shouldn't be"
    echo "  suid-diff.txt       privilege escalation"
    echo "  etc-added.txt       dropped-in persistence"
} | tee "$OUT/SUMMARY.txt"

echo
echo "Output in: $OUT"
echo "Clean copy kept at $WORK - delete it when done to save space."
