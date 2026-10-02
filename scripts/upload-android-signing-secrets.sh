#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
keystore='android/signing/release-keystore.jks'
password='android/signing/password.txt'
repo='MrRice-TW/LyricsFloat'

if ! command -v gh >/dev/null; then
  echo 'Install GitHub CLI first: brew install gh' >&2
  exit 1
fi
if [[ ! -s "$keystore" || ! -s "$password" ]]; then
  echo 'Local signing files are missing. Restore both files from the private backup.' >&2
  exit 1
fi
gh auth status >/dev/null

# gh encrypts each value locally before sending it to GitHub. Neither value is
# placed in command arguments, shell history, the repository, or command output.
base64 < "$keystore" | tr -d '\n' | gh secret set ANDROID_KEYSTORE_BASE64 --repo "$repo" --app actions
gh secret set ANDROID_KEYSTORE_PASSWORD --repo "$repo" --app actions < "$password"

gh secret list --repo "$repo" --app actions | grep -E '^ANDROID_KEYSTORE_(BASE64|PASSWORD)[[:space:]]'
echo 'Android signing secrets are configured. Keep the local backup safe.'
