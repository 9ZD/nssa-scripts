#!/usr/bin/env bash
# fstab-fix-paths.sh — fix the mount points of commented-out UUID lines in
# /etc/fstab and turn them back on (Rocky Linux / RHEL).
#
# For every line like   #UUID=1234-abcd  /wrong/path  xfs  defaults  0 0
#   - checks the UUID exists on this machine (blkid)
#   - suggests the path it is mounted on right now, if it is mounted
#   - lets you accept or type the correct mount point (or skip the line)
#   - corrects the filesystem type from blkid, uncomments the line
# Shows the full diff and asks before writing. A backup is always kept.
#
# Usage:  sudo ./fstab-fix-paths.sh

set -euo pipefail

FSTAB="${FSTAB:-/etc/fstab}"

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (sudo) so blkid can read every device." >&2
  exit 1
fi

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
changed=0
new_dirs=()

# Read fstab on fd 3 so the prompts can still read from the keyboard
while IFS= read -r line <&3 || [[ -n $line ]]; do
  if [[ ! $line =~ ^[[:space:]]*#[[:space:]]*(UUID=[^[:space:]]+)[[:space:]]+(.*)$ ]]; then
    printf '%s\n' "$line" >>"$tmp"
    continue
  fi

  spec="${BASH_REMATCH[1]}"
  uuid="${spec#UUID=}"
  uuid="${uuid//\"/}"
  read -r old_path fstype opts dump pass <<<"${BASH_REMATCH[2]}"

  dev=$(blkid -U "$uuid" 2>/dev/null || true)
  if [[ -z $dev ]]; then
    echo "WARN: UUID $uuid is not on any disk in this machine, leaving it commented" >&2
    printf '%s\n' "$line" >>"$tmp"
    continue
  fi

  real_type=$(blkid -s TYPE -o value "$dev" || true)
  echo
  echo "UUID=$uuid  ->  $dev (${real_type:-unknown type})"
  echo "  fstab had mount point: $old_path"

  if [[ $real_type == swap ]]; then
    new_path=none
    echo "  swap partition, mount point set to: none"
  else
    mounted=$(findmnt -n -o TARGET -S "UUID=$uuid" | head -n1 || true)
    default="${mounted:-$old_path}"
    [[ -n $mounted ]] && echo "  currently mounted at:  $mounted"
    read -r -p "  Correct mount point [$default] (s = skip): " answer </dev/tty
    if [[ $answer == s ]]; then
      echo "  skipped, leaving it commented"
      printf '%s\n' "$line" >>"$tmp"
      continue
    fi
    new_path="${answer:-$default}"
    if [[ $new_path != /* ]]; then
      echo "  '$new_path' is not an absolute path, leaving it commented" >&2
      printf '%s\n' "$line" >>"$tmp"
      continue
    fi
    [[ -d $new_path ]] || new_dirs+=("$new_path")
  fi

  if [[ -n $real_type && $real_type != "$fstype" ]]; then
    echo "  filesystem type corrected: ${fstype:-<none>} -> $real_type"
    fstype="$real_type"
  fi

  printf 'UUID=%s\t%s\t%s\t%s\t%s %s\n' \
    "$uuid" "$new_path" "$fstype" "${opts:-defaults}" "${dump:-0}" "${pass:-0}" >>"$tmp"
  changed=$((changed + 1))
done 3<"$FSTAB"

echo
if [[ $changed -eq 0 ]]; then
  echo "Nothing to change: no commented-out UUID lines were fixed."
  exit 0
fi

diff -u "$FSTAB" "$tmp" || true
echo
for d in "${new_dirs[@]+"${new_dirs[@]}"}"; do
  echo "Will create missing directory: $d"
done

read -r -p "Write these $changed change(s) to $FSTAB? [y/N] " ok </dev/tty
if [[ $ok != [yY]* ]]; then
  echo "No changes written."
  exit 0
fi

backup="${FSTAB}.bak.$(date +%Y%m%d-%H%M%S)"
cp -a "$FSTAB" "$backup"
# Write into the existing file so its permissions and SELinux label stay intact
cat "$tmp" >"$FSTAB"
for d in "${new_dirs[@]+"${new_dirs[@]}"}"; do
  mkdir -p "$d"
done
echo "Updated $FSTAB. Backup saved to $backup"

if ! findmnt --verify --tab-file "$FSTAB"; then
  echo "findmnt reported problems. Restore with: sudo cp -a $backup $FSTAB" >&2
  exit 1
fi

systemctl daemon-reload
echo "Done. Run 'sudo mount -a' to test before rebooting."
