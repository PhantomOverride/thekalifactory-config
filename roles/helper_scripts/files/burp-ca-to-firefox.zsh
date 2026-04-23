#!/usr/bin/env zsh
set -euo pipefail

echo "=================================================="
echo "This script requires Burp Suite to be running."
echo ""
echo "Expected: http://127.0.0.1:8080"
echo "Make sure Burp Proxy listener is active on port 8080."
echo "=================================================="
echo ""

read "confirm?Press ENTER to continue (Ctrl+C to cancel)... "
echo ""

# Config
BURP_CERT_URL="${BURP_CERT_URL:-http://127.0.0.1:8080/cert}"
FIREFOX_DIR="${FIREFOX_DIR:-$HOME/.mozilla/firefox}"
CERT_NICKNAME="${CERT_NICKNAME:-Burp CA}"

# Temp files
WORKDIR="$(mktemp -d)"
DER_CERT="$WORKDIR/burp.der"
PEM_CERT="$WORKDIR/burp.pem"

cleanup() {
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    print -u2 "Missing required command: $1"
    exit 1
  }
}

need_cmd curl
need_cmd openssl
need_cmd certutil

if [[ ! -d "$FIREFOX_DIR" ]]; then
  print -u2 "Firefox profile directory not found: $FIREFOX_DIR"
  exit 1
fi

print "Downloading Burp CA certificate from: $BURP_CERT_URL"
curl --fail --silent --show-error --location "$BURP_CERT_URL" -o "$DER_CERT"

# Convert to PEM. If the download is already PEM, keep it.
if openssl x509 -inform DER -in "$DER_CERT" -out "$PEM_CERT" >/dev/null 2>&1; then
  print "Converted DER certificate to PEM."
elif openssl x509 -in "$DER_CERT" -out "$PEM_CERT" >/dev/null 2>&1; then
  print "Downloaded certificate was already PEM."
else
  print -u2 "Could not parse certificate from $BURP_CERT_URL"
  exit 1
fi

# Basic display for sanity check
print "\nCertificate subject:"
openssl x509 -in "$PEM_CERT" -noout -subject || true
print "Certificate fingerprint (SHA256):"
openssl x509 -in "$PEM_CERT" -noout -fingerprint -sha256 || true
print ""

typeset -a profiles
profiles=()

# Prefer profiles from profiles.ini if present
if [[ -f "$FIREFOX_DIR/profiles.ini" ]]; then
  while IFS= read -r line; do
    if [[ "$line" == Path=* ]]; then
      prof_path="${line#Path=}"
      if [[ -d "$FIREFOX_DIR/$prof_path" ]]; then
        profiles+=("$FIREFOX_DIR/$prof_path")
      fi
    fi
  done < "$FIREFOX_DIR/profiles.ini"
fi

# Fallback: discover profile-like dirs
if (( ${#profiles[@]} == 0 )); then
  while IFS= read -r dir; do
    profiles+=("$dir")
  done < <(find "$FIREFOX_DIR" -maxdepth 1 -type d \( -name "*.default*" -o -name "*.dev-edition-default*" -o -name "*.profile*" \) | sort)
fi

if (( ${#profiles[@]} == 0 )); then
  print -u2 "No Firefox profiles found under $FIREFOX_DIR"
  exit 1
fi

print "Found ${#profiles[@]} Firefox profile(s)."

for profile in "${profiles[@]}"; do
  print "\n==> Importing into profile: $profile"

  # Ensure NSS DB exists for the profile
  if [[ ! -f "$profile/cert9.db" ]]; then
    print "Creating NSS DB in profile..."
    certutil -N --empty-password -d "sql:$profile" >/dev/null 2>&1 || true
  fi

  # Remove existing nickname if present
  if certutil -L -d "sql:$profile" | grep -Fq "$CERT_NICKNAME"; then
    print "Removing existing certificate nickname: $CERT_NICKNAME"
    certutil -D -n "$CERT_NICKNAME" -d "sql:$profile" || true
  fi

  # Trust flags:
  # C,, = trusted CA for issuing server certs
  certutil -A -n "$CERT_NICKNAME" -t "C,," -i "$PEM_CERT" -d "sql:$profile"

  print "Verifying import..."
  certutil -L -d "sql:$profile" -n "$CERT_NICKNAME"
done

print "\nDone."
print "Restart Firefox to apply new settings."
