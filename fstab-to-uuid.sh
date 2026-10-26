#!/usr/bin/env bash
# fstab-to-uuid.sh — look up the UUID of every /dev/... device in /etc/fstab
# and rewrite those entries as UUID=... (Rocky Linux / RHEL).
#
# Usage:
#   sudo ./fstab-to-uuid.sh            # dry run: show what would change
#   sudo ./fstab-to-uuid.sh --apply    # back up fstab, then write the changes
#   add --all to also convert /dev/mapper/* (LVM) entries, which are
#   already stable names and are skipped by default.

set -euo pipefail

FSTAB="${FSTAB:-/etc/fstab}"
APPLY=0
ALL=0
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    --all)   ALL=1 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (sudo) so blkid can read every device." >&2
  exit 1
fi

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
changed=0

while IFS= read -r line || [[ -n $line ]]; do
  # Keep comments and blank lines untouched
  if [[ $line =~ ^[[:space:]]*(#|$) ]]; then
    printf '%s\n' "$line" >>"$tmp"
    continue
  fi

  # Split off the first field while preserving the original spacing of the rest
  lead="${line%%[![:space:]]*}"
  body="${line#"$lead"}"
  dev="${body%%[[:space:]]*}"
  rest="${body#"$dev"}"

  if [[ $dev != /dev/* ]] || { [[ $ALL -eq 0 ]] && [[ $dev == /dev/mapper/* ]]; }; then
    printf '%s\n' "$line" >>"$tmp"
    continue
  fi

  if [[ ! -b $dev ]]; then
    echo "WARN: $dev is not a block device on this system, leaving it as-is" >&2
    printf '%s\n' "$line" >>"$tmp"
    continue
  fi

  uuid=$(blkid -s UUID -o value "$dev" || true)
  if [[ -z $uuid ]]; then
    echo "WARN: no UUID found for $dev, leaving it as-is" >&2
    printf '%s\n' "$line" >>"$tmp"
    continue
  fi

  echo "  $dev -> UUID=$uuid"
  printf '%s\n' "${lead}UUID=${uuid}${rest}" >>"$tmp"
  changed=$((changed + 1))
done <"$FSTAB"

if [[ $changed -eq 0 ]]; then
  echo "Nothing to change: no /dev/... entries needed converting."
  exit 0
fi

echo
diff -u "$FSTAB" "$tmp" || true
echo

if [[ $APPLY -eq 0 ]]; then
  echo "Dry run only. Re-run with --apply to write these $changed change(s)."
  exit 0
fi

backup="${FSTAB}.bak.$(date +%Y%m%d-%H%M%S)"
cp -a "$FSTAB" "$backup"
# Write into the existing file so its permissions and SELinux label stay intact
cat "$tmp" >"$FSTAB"
echo "Updated $FSTAB ($changed entries). Backup saved to $backup"

if ! findmnt --verify --tab-file "$FSTAB"; then
  echo "findmnt reported problems. Restore with: cp -a $backup $FSTAB" >&2
  exit 1
fi

systemctl daemon-reload
echo "Done. Test with 'sudo mount -a' before rebooting."
