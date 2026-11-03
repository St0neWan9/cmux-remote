#!/usr/bin/env bash
# Signing material never enters this repository. Private keys, exported identities and provisioning profiles live
# in a release directory outside the checkout or in a CI secret; a tracked one is a leaked credential, and an
# open-source repository makes that public the moment it is pushed. Public identifiers (Bundle ID, team, App Store
# Connect app ID) are not secrets — every signed build ships them — so only the material is refused here.
set -euo pipefail
cd "$(dirname "$0")/.."
self=${BASH_SOURCE[0]#./}
fail=0
while IFS= read -r file; do
  case "$file" in
    *.p8|*.p12|*.pem|*.key|*.cer|*.mobileprovision|*.provisionprofile)
      echo "signing material is tracked: $file" >&2; fail=1 ;;
  esac
done < <(git ls-files)
# An armored private key is refused wherever it sits, whatever the file is called. The two halves are joined here
# so this script's own pattern is the only place they appear unbroken.
while IFS= read -r file; do
  echo "a private key is tracked: $file" >&2; fail=1
done < <(git grep -I -l -e "BEGIN PRIVATE KEY" -e "BEGIN RSA PRIVATE KEY" -e "BEGIN EC PRIVATE KEY" \
              -e "BEGIN ENCRYPTED PRIVATE KEY" -- . ":(exclude)$self" || true)
if [ "$fail" -ne 0 ]; then
  echo "Remove the file from the working tree and from history; rotate the credential." >&2
  exit 1
fi
echo "no signing material is tracked"
