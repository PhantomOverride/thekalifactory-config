#!/usr/bin/env zsh
set -euo pipefail

# Reset user pw
echo "Running passwd, please change your password."
passwd

echo "Checking LUKS unlock methods now."
/opt/scripts/luks-check-unlock-methods.zsh

# Reset encryption passphrase
echo "Changing LUKS passphrase now."
/opt/scripts/luks-change-passphrase.zsh

echo "Checking whether root storage can be expanded."
/opt/scripts/expand-root-storage.zsh

# Re-encrypting entire drive with new encryption keys
echo "Re-encrypting disk now."
/opt/scripts/luks-reencrypt.zsh

echo "Done! Let's reboot to make sure you remembered your new passwords."

read "answer?Reboot now? [Y/n]: "
answer=${answer:-Y}

if [[ "$answer" =~ ^[Yy]$ ]]; then
  reboot
else
  echo "Skipping reboot."
fi
