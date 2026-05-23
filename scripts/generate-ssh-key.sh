#!/usr/bin/env bash
set -euo pipefail

# Generate an SSH key for pasting into GitHub, Bitbucket, etc.
#
# Defaults to ed25519, stores the key at ~/.ssh/id_ed25519_<host>, adds it to
# ssh-agent with the macOS keychain, appends an ~/.ssh/config block for the
# host, prints the public key, and copies it to the clipboard.

HOST="github"
EMAIL=""
NAME="genkio"
KEY_TYPE="ed25519"
PASSPHRASE=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [--host github|bitbucket|<name>] [--email <addr>] [--name <name>] [--type ed25519|rsa] [--passphrase]

Options:
  --host         Target host label, used in filename and ssh config (default: github)
  --email        Email used as the key comment (default: 5327840+genkio@users.noreply.github.com)
  --name         Git user.name written to ~/.gitconfig.local (default: genkio)
  --type         Key type: ed25519 (default) or rsa (4096-bit)
  --passphrase   Prompt for a passphrase (default: no passphrase)
  -h, --help     Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --email) EMAIL="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --type) KEY_TYPE="$2"; shift 2 ;;
    --passphrase) PASSPHRASE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

# Normalise to filename-safe label
HOST="$(echo "$HOST" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '_' | sed 's/_*$//')"
if [[ -z "$HOST" ]]; then
  echo "Invalid host label." >&2
  exit 1
fi

case "$HOST" in
  github)    HOSTNAME="github.com" ;;
  bitbucket) HOSTNAME="bitbucket.org" ;;
  gitlab)    HOSTNAME="gitlab.com" ;;
  *)         HOSTNAME="$HOST" ;;
esac

if [[ -z "$EMAIL" ]]; then
  EMAIL="5327840+genkio@users.noreply.github.com"
fi

SSH_DIR="$HOME/.ssh"
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

case "$KEY_TYPE" in
  ed25519) KEYGEN_ARGS=(-t ed25519) ;;
  rsa)     KEYGEN_ARGS=(-t rsa -b 4096) ;;
  *) echo "Unsupported key type: $KEY_TYPE" >&2; exit 1 ;;
esac

KEY_PATH="$SSH_DIR/${HOST}"

if [[ -e "$KEY_PATH" || -e "${KEY_PATH}.pub" ]]; then
  echo "Key already exists at $KEY_PATH"
  read -r -p "Overwrite? [y/N]: " ans
  case "$ans" in
    y|Y|yes|YES) rm -f "$KEY_PATH" "${KEY_PATH}.pub" ;;
    *) echo "Aborting."; exit 1 ;;
  esac
fi

if [[ "$PASSPHRASE" -eq 0 ]]; then
  KEYGEN_ARGS+=(-N "")
fi

ssh-keygen "${KEYGEN_ARGS[@]}" -C "$EMAIL" -f "$KEY_PATH"
chmod 600 "$KEY_PATH"
chmod 644 "${KEY_PATH}.pub"

# Add to ssh-agent (macOS: store passphrase in keychain)
if [[ "$(uname -s)" == "Darwin" ]]; then
  eval "$(ssh-agent -s)" >/dev/null
  ssh-add --apple-use-keychain "$KEY_PATH" || ssh-add -K "$KEY_PATH" || true
else
  eval "$(ssh-agent -s)" >/dev/null
  ssh-add "$KEY_PATH" || true
fi

# Append an ssh config block if no matching Host entry exists
CONFIG="$SSH_DIR/config"
touch "$CONFIG"
chmod 600 "$CONFIG"
if ! grep -E "^Host[[:space:]]+(.* )?${HOSTNAME}( |$)" "$CONFIG" >/dev/null 2>&1; then
  {
    echo ""
    echo "Host $HOSTNAME"
    echo "  HostName $HOSTNAME"
    echo "  User git"
    echo "  IdentityFile $KEY_PATH"
    echo "  AddKeysToAgent yes"
    if [[ "$(uname -s)" == "Darwin" ]]; then
      echo "  UseKeychain yes"
    fi
  } >> "$CONFIG"
  echo "Appended $HOSTNAME block to $CONFIG"
else
  echo "$CONFIG already has a Host entry for $HOSTNAME, leaving it alone."
fi

# Sync the name/email into ~/.gitconfig.local if it exists (seeded by opinionated-flow.sh).
GITCONFIG_LOCAL="$HOME/.gitconfig.local"
if [[ -f "$GITCONFIG_LOCAL" ]] && command -v git >/dev/null 2>&1; then
  CURRENT_EMAIL="$(git config -f "$GITCONFIG_LOCAL" user.email 2>/dev/null || true)"
  if [[ "$CURRENT_EMAIL" != "$EMAIL" ]]; then
    git config -f "$GITCONFIG_LOCAL" user.email "$EMAIL"
    echo "Updated user.email in $GITCONFIG_LOCAL to $EMAIL"
  fi
  CURRENT_NAME="$(git config -f "$GITCONFIG_LOCAL" user.name 2>/dev/null || true)"
  if [[ "$CURRENT_NAME" != "$NAME" ]]; then
    git config -f "$GITCONFIG_LOCAL" user.name "$NAME"
    echo "Updated user.name in $GITCONFIG_LOCAL to $NAME"
  fi
fi

PUBKEY="$(cat "${KEY_PATH}.pub")"

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
PASTE_URL=""
case "$HOST" in
  github)    PASTE_URL="https://github.com/settings/ssh/new" ;;
  bitbucket) PASTE_URL="https://bitbucket.org/account/settings/ssh-keys/" ;;
  gitlab)    PASTE_URL="https://gitlab.com/-/user_settings/ssh_keys" ;;
esac
if [[ -n "$PASTE_URL" ]]; then
  echo "Paste at: $PASTE_URL"
  if command -v open >/dev/null 2>&1; then
    open "$PASTE_URL"
  fi
fi
echo "Test with: ssh -T git@${HOSTNAME}"
