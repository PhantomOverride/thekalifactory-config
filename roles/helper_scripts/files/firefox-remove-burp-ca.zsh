#!/usr/bin/env zsh
set -euo pipefail

FIREFOX_DIR="${FIREFOX_DIR:-$HOME/.mozilla/firefox}"
CERT_NICKNAME="${CERT_NICKNAME:-Burp CA}"

find "$FIREFOX_DIR" -maxdepth 1 -type d \( -name "*.default*" -o -name "*.dev-edition-default*" -o -name "*.profile*" \) | while read -r profile; do
  if [[ -f "$profile/cert9.db" ]]; then
    certutil -D -n "$CERT_NICKNAME" -d "sql:$profile" || true
    print "Removed from $profile"
  fi
done

print "\nDone."
print "Restart Firefox to apply new settings."
