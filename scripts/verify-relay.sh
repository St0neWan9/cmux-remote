#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export WRANGLER_SEND_METRICS=false
npm ci --prefix cloudflare
npm run build --prefix cloudflare
npm test --prefix cloudflare
CMUX_REMOTE_RELAY_TESTS=1 swift test --filter 'LinkRelayIntegrationTests|LinkIntegrationTests|LinkCipherTests|RelayPolicyTests'
