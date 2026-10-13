#!/usr/bin/env bash
# Deploys the relay Worker to the Cloudflare account that `wrangler login` authorized,
# then stores the Bridge registration key as a Worker secret. The key is generated into
# an owner-only file and only ever travels through stdin; it is never printed or passed in argv.
set -euo pipefail
cd "$(dirname "$0")/.."
key_file="${1:-$HOME/.local/state/cmux-remote/relay-registration-key}"
case "$key_file" in /*) ;; *) echo "Use an absolute key file path." >&2; exit 2 ;; esac
export WRANGLER_SEND_METRICS=false
npm ci --prefix cloudflare --no-audit --no-fund >/dev/null
cd cloudflare
if ! npx wrangler whoami 2>/dev/null | grep -q "You are logged in"; then
  echo "Not logged in to Cloudflare. Run: cd cloudflare && npx wrangler login" >&2; exit 3
fi
if [[ ! -e "$key_file" ]]; then
  mkdir -p "$(dirname "$key_file")"; chmod 700 "$(dirname "$key_file")"
  (umask 077; openssl rand -hex 32 > "$key_file")
  echo "Created registration key file: $key_file"
fi
test -f "$key_file" && test ! -L "$key_file" || { echo "The key file must be a regular file." >&2; exit 2; }
test "$(stat -f '%u' "$key_file")" = "$(id -u)" || { echo "The key file must belong to you." >&2; exit 2; }
test "$(( 8#$(stat -f '%Lp' "$key_file") & 8#077 ))" = 0 || { echo "The key file must be private (chmod 600)." >&2; exit 2; }
output="$(npx wrangler deploy 2>&1)" || { printf '%s\n' "$output" >&2; exit 1; }
origin="$(printf '%s\n' "$output" | grep -Eo 'https://[A-Za-z0-9.-]+\.workers\.dev' | head -n 1 || true)"
tr -d '\n' < "$key_file" | npx wrangler secret put BRIDGE_REGISTRATION_KEY >/dev/null
echo "Relay deployed."
echo "Relay origin: ${origin:-see the wrangler deploy output above}"
echo "Registration key file: $key_file"
echo "On the Mac: stop sharing, enter both values under Share This Mac > Cloud relay, save, then start sharing."
