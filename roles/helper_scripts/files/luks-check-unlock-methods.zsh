#!/usr/bin/env zsh
set -euo pipefail

command -v jq >/dev/null

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

echo "Checking unlock methods for: $TARGET"
typeset -a warnings
warnings=()

if sudo cryptsetup isLuks --type luks2 "$TARGET"; then
  metadata="$(sudo cryptsetup luksDump --dump-json-metadata "$TARGET")"
  token_count="$(printf '%s\n' "$metadata" | jq -er '(.tokens // {}) | length')"
  if (( token_count > 0 )); then
    warnings+=("LUKS2 tokens are enrolled:")
    warnings+=("$(printf '%s\n' "$metadata" | jq -r '
      .tokens | to_entries[] | "  Token \(.key): \(.value.type // "unknown")"
    ')")
  fi
elif sudo cryptsetup isLuks --type luks1 "$TARGET"; then
  echo "LUKS1 has no token metadata to inspect."
else
  echo "Error: cannot identify the LUKS header."
  exit 1
fi

uuid="$(sudo cryptsetup luksUUID "$TARGET")"
if [[ -f /etc/crypttab ]]; then
  crypttab="$(sudo cat /etc/crypttab)"
  while read -r mapping source keyfile unlock_options remainder; do
    [[ -z "$mapping" || "$mapping" == \#* ]] && continue
    if [[ "$source" != "UUID=$uuid" && "$source" != "$TARGET" &&
          "$(readlink -f -- "$source" 2>/dev/null || true)" != "$TARGET" ]]; then
      continue
    fi

    if [[ -n "$keyfile" && "$keyfile" != none && "$keyfile" != - ]]; then
      warnings+=("crypttab entry $mapping specifies a key file or key source: $keyfile")
    fi
    case ",$unlock_options," in
      *,keyscript=*|*,tpm2-device=*|*,fido2-device=*|*,pkcs11-uri=*)
        warnings+=("crypttab entry $mapping configures an alternative unlock method: $unlock_options")
        ;;
    esac
    for key_path in "/etc/cryptsetup-keys.d/$mapping.key" "/run/cryptsetup-keys.d/$mapping.key"; do
      if sudo test -e "$key_path"; then
        warnings+=("An automatically discovered key file exists: $key_path")
      fi
    done
  done <<< "$crypttab"
fi

echo "A normal LUKS keyslot does not identify whether its secret is a password or a keyfile."
echo "This check cannot rule out external keyfiles, recovery secrets, or keys embedded in an initramfs."

if (( ${#warnings[@]} > 0 )); then
  printf '\n%s\n' '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
  echo 'WARNING: NON-PASSWORD UNLOCK CONFIGURATION DETECTED'
  printf '%s\n' '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
  printf '%s\n' "${warnings[@]}"
  echo "No unlock methods have been changed. Review these findings and take action as appropriate."
  echo "Press Ctrl+C to stop the deployment workflow."
  read "REPLY?Press Enter to acknowledge and continue: "
else
  echo "No enrolled tokens or configured alternative unlock methods were found."
fi