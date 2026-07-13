#!/usr/bin/env bash
set -euo pipefail

# Generate a GPG signing key for Git commits.
#
# Defaults to RSA 4096 with 3y expiry, no passphrase so git can sign without
# prompting. Prints the public key for pasting into GitHub, sets
# user.signingkey + commit.gpgsign in ~/.gitconfig.local if present, and
# copies the armored public key to the clipboard.

source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

NAME="genkio"
EMAIL=""
KEY_TYPE="RSA"
KEY_LENGTH="4096"
EXPIRE="3y"
PASSPHRASE=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [--name <name>] [--email <addr>] [--type RSA|EDDSA] [--length <bits>] [--expire <spec>] [--passphrase]

Options:
  --name         Real name on the key (default: genkio)
  --email        Email on the key (default: 5327840+genkio@users.noreply.github.com)
  --type         Key type: RSA (default) or EDDSA
  --length       RSA key length in bits (default: 4096, ignored for EDDSA)
  --expire       Expiry, e.g. 1y, 3y, 0 for never (default: 3y)
  --passphrase   Prompt for a passphrase (default: no passphrase so git can sign unattended)
  -h, --help     Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) NAME="$2"; shift 2 ;;
    --email) EMAIL="$2"; shift 2 ;;
    --type) KEY_TYPE="$2"; shift 2 ;;
    --length) KEY_LENGTH="$2"; shift 2 ;;
    --expire) EXPIRE="$2"; shift 2 ;;
    --passphrase) PASSPHRASE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) err "unknown option: $1"; usage; exit 1 ;;
  esac
done

if [[ -z "$EMAIL" ]]; then
  EMAIL="5327840+genkio@users.noreply.github.com"
fi

if ! command -v gpg >/dev/null 2>&1; then
  err "gpg not found. Install GnuPG first (e.g. brew install gnupg)."
  exit 1
fi

case "$KEY_TYPE" in
  RSA|rsa)     KEY_TYPE="RSA" ;;
  EDDSA|eddsa) KEY_TYPE="EDDSA" ;;
  *) err "unsupported key type: $KEY_TYPE (use RSA or EDDSA)"; exit 1 ;;
esac

# A key for this identity may already exist; generating another leaves
# duplicate keys in the keyring, and Git keeps using the old user.signingkey
# unless this script rewrites it below. Default to aborting.
if gpg --list-secret-keys --with-colons "$EMAIL" 2>/dev/null | grep -q '^sec:'; then
  echo "A GPG secret key already exists for $EMAIL:"
  gpg --list-secret-keys --keyid-format=long "$EMAIL" 2>/dev/null || true
  read -r -p "Create another key anyway? [y/N]: " ans
  case "$ans" in
    y|Y|yes|YES) ;;
    *) echo "Aborting."; exit 1 ;;
  esac
fi

BATCH_FILE="$(mktemp -t gpg-genkey.XXXXXX)"
STATUS_FILE="$(mktemp -t gpg-genstatus.XXXXXX)"
trap 'rm -f "$BATCH_FILE" "$STATUS_FILE"' EXIT

{
  if [[ "$KEY_TYPE" == "EDDSA" ]]; then
    echo "Key-Type: EDDSA"
    echo "Key-Curve: ed25519"
  else
    echo "Key-Type: RSA"
    echo "Key-Length: $KEY_LENGTH"
  fi
  echo "Key-Usage: sign"
  echo "Name-Real: $NAME"
  echo "Name-Email: $EMAIL"
  echo "Expire-Date: $EXPIRE"
  if [[ "$PASSPHRASE" -eq 0 ]]; then
    echo "%no-protection"
  fi
  echo "%commit"
} > "$BATCH_FILE"

echo "Generating $KEY_TYPE key for $NAME <$EMAIL> (expires: $EXPIRE)..."
gpg --batch --status-file "$STATUS_FILE" --generate-key "$BATCH_FILE"

# Read the fingerprint straight from gpg's status output for the key we just
# created, so we never mis-select an older key when several share this email.
KEY_ID="$(awk '/^\[GNUPG:\] KEY_CREATED/ { print $4 }' "$STATUS_FILE")"

if [[ -z "$KEY_ID" ]]; then
  err "could not locate generated key for $EMAIL"
  exit 1
fi

echo "Created key: $KEY_ID"

# Sync signing config into ~/.gitconfig.local if it exists.
GITCONFIG_LOCAL="$HOME/.gitconfig.local"
if [[ -f "$GITCONFIG_LOCAL" ]] && command -v git >/dev/null 2>&1; then
  CURRENT_NAME="$(git config -f "$GITCONFIG_LOCAL" user.name 2>/dev/null || true)"
  if [[ "$CURRENT_NAME" != "$NAME" ]]; then
    git config -f "$GITCONFIG_LOCAL" user.name "$NAME"
    echo "Updated user.name in $GITCONFIG_LOCAL to $NAME"
  fi
  CURRENT_EMAIL="$(git config -f "$GITCONFIG_LOCAL" user.email 2>/dev/null || true)"
  if [[ "$CURRENT_EMAIL" != "$EMAIL" ]]; then
    git config -f "$GITCONFIG_LOCAL" user.email "$EMAIL"
    echo "Updated user.email in $GITCONFIG_LOCAL to $EMAIL"
  fi
  git config -f "$GITCONFIG_LOCAL" user.signingkey "$KEY_ID"
  git config -f "$GITCONFIG_LOCAL" commit.gpgsign true
  git config -f "$GITCONFIG_LOCAL" gpg.program "$(command -v gpg)"
  echo "Updated user.signingkey/commit.gpgsign/gpg.program in $GITCONFIG_LOCAL"
fi

PUBKEY="$(gpg --armor --export "$KEY_ID")"

if command -v pbcopy >/dev/null 2>&1; then
  printf '%s' "$PUBKEY" | pbcopy
  COPIED=" (copied to clipboard)"
else
  COPIED=""
fi

echo ""
echo "Public key${COPIED}:"
echo ""
echo "$PUBKEY"
echo ""
PASTE_URL="https://github.com/settings/gpg/new"
echo "Paste at: $PASTE_URL"
if command -v open >/dev/null 2>&1; then
  read -r -p "Open in browser? [y/N]: " ans
  case "$ans" in
    y|Y|yes|YES) open "$PASTE_URL" ;;
  esac
fi
echo "Test with: echo test | gpg --clearsign --local-user $KEY_ID"
