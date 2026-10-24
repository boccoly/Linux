#!/usr/bin/env bash
#
# make-baseline.sh - capture a clean-system baseline for diffing later
#
# RUN THIS ON A FRESH, CLEAN LINUX MINT VM. Never on a competition image.
#
# Install Mint from the ISO, boot it, apply NO updates and install NOTHING,
# then run this. The whole point is to capture the factory state.
#
# Usage:  sudo bash make-baseline.sh [output-dir]
#
set -euo pipefail

OUT="${1:-./baseline}"

if [[ $EUID -ne 0 ]]; then
    echo "Run with sudo - needs to read all of /etc." >&2
    exit 1
fi

for c in zip gzip; do
    command -v "$c" >/dev/null || { echo "Missing: $c  (sudo apt install -y $c)" >&2; exit 1; }
done

# ---------------------------------------------------------------- version
MINT_REL=$(sed -n 's/^RELEASE=//p' /etc/linuxmint/info 2>/dev/null || true)
MINT_CODE=$(sed -n 's/^CODENAME=//p' /etc/linuxmint/info 2>/dev/null || true)
MINT_ED=$(sed -n 's/^EDITION=//p' /etc/linuxmint/info 2>/dev/null | tr -d '"' | awk '{print $1}' || true)
# Fallback: the mint-info-* package name states the edition definitively
if [[ -z ${MINT_ED:-} ]]; then
    MINT_ED=$(dpkg-query -W -f='${Package}\n' 'mint-info-*' 2>/dev/null | head -1 | sed 's/^mint-info-//' || true)
fi
UBU_BASE=$(sed -n 's/^DISTRIB_CODENAME=//p' /etc/upstream-release/lsb-release 2>/dev/null || true)

if [[ -n $MINT_REL ]]; then
    TAG="mint${MINT_REL%%.*}"
else
    echo "Not a Mint system. Falling back to lsb_release." >&2
    TAG=$(lsb_release -is 2>/dev/null | tr 'A-Z' 'a-z')$(lsb_release -rs 2>/dev/null | cut -d. -f1)
fi

DEST="$OUT/$TAG"
mkdir -p "$DEST"
DEST=$(cd "$DEST" && pwd)     # absolute - the zip steps cd to /

echo "Baseline tag : $TAG"
echo "Mint release : ${MINT_REL:-unknown} ${MINT_CODE:-}"
echo "Edition      : ${MINT_ED:-unknown}"
echo "Ubuntu base  : ${UBU_BASE:-unknown}"
echo "Writing to   : $DEST"
echo

# ------------------------------------------------------------------- etc
echo "[*] Snapshotting /etc ..."
( cd / && zip -rqy "$DEST/etc.zip" etc )
echo "    etc.zip  $(du -h "$DEST/etc.zip" | cut -f1)"

# ------------------------------------------------------------------- var
# Skip the churny parts - caches, logs and libs differ on every boot and
# would bury the real findings.
echo "[*] Snapshotting /var (excluding cache, log, lib, backups) ..."
( cd / && zip -rqy "$DEST/var.zip" var \
    -x 'var/cache/*' 'var/log/*' 'var/lib/*' 'var/backups/*' \
       'var/tmp/*' 'var/spool/*' 'var/crash/*' )
echo "    var.zip  $(du -h "$DEST/var.zip" | cut -f1)"

# -------------------------------------------------------------- packages
echo "[*] Package manifests ..."
dpkg-query -W -f='${Package}\n' | sort -u > "$DEST/pkgorig.txt"
apt-mark showmanual | sort -u                > "$DEST/pkgmanual.txt"
echo "    pkgorig.txt    $(wc -l < "$DEST/pkgorig.txt") packages installed"
echo "    pkgmanual.txt  $(wc -l < "$DEST/pkgmanual.txt") manually installed"

# ------------------------------------------------------- state manifests
echo "[*] State manifests ..."
find / -xdev -type f -perm -4000 2>/dev/null | sort > "$DEST/suid.txt"
find / -xdev -type f -perm -2000 2>/dev/null | sort > "$DEST/sgid.txt"
find / -xdev -type f -perm -0002 2>/dev/null | sort > "$DEST/world-writable.txt"

systemctl list-unit-files --type=service --state=enabled --no-legend --no-pager 2>/dev/null \
    | awk '{print $1}' | sort > "$DEST/services-enabled.txt"

awk -F: '{print $1":"$3":"$7}' /etc/passwd | sort > "$DEST/passwd.txt"
awk -F: '{print $1":"$3":"$4}' /etc/group  | sort > "$DEST/group.txt"

{
    echo "tag=$TAG"
    echo "mint_release=${MINT_REL:-unknown}"
    echo "mint_codename=${MINT_CODE:-unknown}"
    echo "mint_edition=${MINT_ED:-unknown}"
    echo "ubuntu_base=${UBU_BASE:-unknown}"
    echo "kernel=$(uname -r)"
    echo "captured=$(date --rfc-3339=seconds)"
} > "$DEST/BASELINE-INFO"

echo
echo "Done. Copy the whole '$DEST' directory into the repo at:"
echo "    baseline/$TAG/"
echo
echo "Then at round time:  sudo bash scripts/baseline-diff.sh baseline/$TAG"
