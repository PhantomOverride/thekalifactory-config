#!/usr/bin/env zsh
set -euo pipefail

TARGET="$(
  lsblk -rpo NAME,TYPE,FSTYPE |
  awk '$2=="part" && $3=="crypto_LUKS" {print $1}'
)"

COUNT="$(printf '%s\n' "$TARGET" | sed '/^$/d' | wc -l)"

if [[ "$COUNT" -eq 0 ]]; then
  echo "Error: no LUKS partition found."
  exit 1
elif [[ "$COUNT" -gt 1 ]]; then
  echo "Error: multiple LUKS partitions found:"
  printf '%s\n' "$TARGET"
  exit 1
fi

echo "Target LUKS partition: $TARGET"
echo "This will re-encrypt the device and rotate the master key."
echo "It will ask for an existing valid passphrase."
echo
read "reply?Type YES to continue: "
[[ "$reply" == "YES" ]] || { echo "Aborted."; exit 1; }

sudo cryptsetup reencrypt "$TARGET"

echo
echo "Re-encryption completed for $TARGET"
