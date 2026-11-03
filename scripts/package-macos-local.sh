#!/usr/bin/env bash
# Sign, notarize and package the Mac app with local release material instead of the CI secret bundle.
#
#   scripts/package-macos-local.sh \
#     --p12 ~/release/developer-id.p12 --p12-password-file ~/release/developer-id.p12.password \
#     --notary-key ~/release/AuthKey_XXXXXXXXXX.p8 --notary-key-id XXXXXXXXXX \
#     --notary-issuer 00000000-0000-0000-0000-000000000000 \
#     [--version=0.1.0] [--build-number=1] [--notarize]
#
# Every path must be absolute and stay on this machine: the private key and the notary key are handed to
# scripts/with-macos-signing.py, which imports the certificate into a throwaway keychain and never prints a
# secret. Omit --notarize for a signed build that Gatekeeper will reject on other Macs; the artifacts land
# in .build/macos-release/dist either way.
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
  sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
}

version="${CMUX_REMOTE_MAC_VERSION:-0.1.0}"
build="${CMUX_REMOTE_MAC_BUILD_NUMBER:-1}"
p12="${CMUX_REMOTE_MAC_CERT_P12_PATH:-}"
password_file="${CMUX_REMOTE_MAC_CERT_PASSWORD_PATH:-}"
notary_key="${CMUX_REMOTE_NOTARY_KEY_PATH:-}"
notary_key_id="${CMUX_REMOTE_NOTARY_KEY_ID:-}"
notary_issuer="${CMUX_REMOTE_NOTARY_ISSUER:-}"
notarize=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --p12) p12="${2:?--p12 needs a path}"; shift 2 ;;
    --p12=*) p12="${1#*=}"; shift ;;
    --p12-password-file) password_file="${2:?--p12-password-file needs a path}"; shift 2 ;;
    --p12-password-file=*) password_file="${1#*=}"; shift ;;
    --notary-key) notary_key="${2:?--notary-key needs a path}"; shift 2 ;;
    --notary-key=*) notary_key="${1#*=}"; shift ;;
    --notary-key-id) notary_key_id="${2:?--notary-key-id needs a value}"; shift 2 ;;
    --notary-key-id=*) notary_key_id="${1#*=}"; shift ;;
    --notary-issuer) notary_issuer="${2:?--notary-issuer needs a value}"; shift 2 ;;
    --notary-issuer=*) notary_issuer="${1#*=}"; shift ;;
    --version=*) version="${1#*=}"; shift ;;
    --build-number=*) build="${1#*=}"; shift ;;
    --notarize) notarize=(--notarize); shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

require_file() {
  local label="$1" path="$2"
  [[ -n "$path" ]] || { echo "Missing $label. See --help." >&2; exit 2; }
  [[ "$path" == /* ]] || { echo "$label must be an absolute path." >&2; exit 2; }
  [[ -f "$path" ]] || { echo "$label does not name a file." >&2; exit 2; }
  [[ "$path" != *$'\n'* ]] || { echo "$label must not contain a newline." >&2; exit 2; }
}
require_value() {
  local label="$1" value="$2"
  [[ -n "$value" ]] || { echo "Missing $label. See --help." >&2; exit 2; }
  [[ "$value" != *[[:space:]]* ]] || { echo "$label must not contain whitespace." >&2; exit 2; }
}

require_file "Developer ID P12 (--p12)" "$p12"
require_file "P12 password file (--p12-password-file)" "$password_file"
require_file "Notary key (--notary-key)" "$notary_key"
require_value "Notary key id (--notary-key-id)" "$notary_key_id"
require_value "Notary issuer (--notary-issuer)" "$notary_issuer"

# with-macos-signing.py reads these, imports the certificate into a temporary keychain and deletes it after
# the run; package-macos.sh checks the notary credentials before it starts building when --notarize is set.
export CMUX_REMOTE_MAC_CERT_P12_PATH="$p12"
export CMUX_REMOTE_MAC_CERT_PASSWORD_PATH="$password_file"
export CMUX_REMOTE_NOTARY_KEY_PATH="$notary_key"
export CMUX_REMOTE_NOTARY_KEY_ID="$notary_key_id"
export CMUX_REMOTE_NOTARY_ISSUER="$notary_issuer"

# macOS still ships bash 3.2, where an empty array under `set -u` is an unbound variable.
exec python3 scripts/with-macos-signing.py bash scripts/package-macos.sh \
  --version="$version" --build-number="$build" ${notarize[@]+"${notarize[@]}"}
