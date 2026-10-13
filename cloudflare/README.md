# cmux-remote Cloudflare relay

A Worker and one SQLite Durable Object per Bridge route opaque encrypted
WebSocket packets. The Bridge and phone connect outward; the Mac needs no public
IP or inbound port. Pairing, workspace authority, files and Agent execution stay
on the Bridge. Users of the phone need no Cloudflare or cmux cloud account.

## Local validation

```sh
# From the repository root; no Cloudflare account or deployment is needed.
scripts/verify-relay.sh
```

This typechecks/bundles the Worker in dry-run mode, runs real SQLite DO routing
and admission tests in Miniflare, then runs the Swift Bridge/client against that
same local runtime over fixture TLS. The Swift integration test supplies an exact
fixture certificate delegate; production cloud transport uses system PKI and
rejects redirects. Local evidence is not a physical cellular-network acceptance.

The toolchain is pinned in package-lock.json. Wrangler 4.149.0 currently depends
on Miniflare 5.20261006.1-alpha; its supported v4-options conversion is used in
local fixtures. Update them together and rerun interoperability tests.

## Deploy when your Cloudflare account is ready

Run inside `cloudflare/`:

```sh
npm ci
npx wrangler login
npx wrangler secret put BRIDGE_REGISTRATION_KEY
npm run deploy
```

Create a unique random key of at least 32 characters. Store the same key in a
Mac file owned by your user with permissions 600. This is a project registration
key, not a Cloudflare API token. Do not put it in source, a QR, a URL, or chat.
Wrangler handles account authentication locally. Record the final HTTPS origin
printed by deployment, such as `https://cmux-remote-relay.YOUR-SUBDOMAIN.workers.dev`.

The Wrangler migration creates the SQLite Durable Object class. The rate-limit
binding bounds admission by client IP; the DO also bounds connections, messages,
bytes, nonce replay state and pending enrollment. There is no content database,
R2 upload, offline command queue or shared phone bearer password.

On the Mac, either enter the origin and private key file in Remote Settings while
sharing is off, or run the Bridge with:

```sh
cmux-remote serve --relay https://YOUR-RELAY.workers.dev \
  --relay-key-file /absolute/private/path/registration-key --pair
```

The saved state stores the origin and filename; it does not copy the key into
JSON. Resident startup reloads this configuration. Existing approved phones can
refresh host-signed relay reachability over LAN; the iPhone home refresh saves it
without changing their grants. New QR enrollment supplies both paths and a short
admission window, then the Mac owner approves the exact device as before.

Turning off sharing stops both LAN serving and the outgoing relay. Removing
relay configuration while sharing is off retains LAN use. The relay only admits
transport: all data requests still require the currently enrolled device's
signed proof and Bridge's current workspace authorization. A revoked public
admission proof cannot authorize any resource.

## Acceptance after deployment

1. Pair on Wi-Fi and verify the same approved workspace and conversation history.
2. Disable phone Wi-Fi, connect over cellular, verify the host identity stays the
   same and read/send/stop/supported approvals/attachments still target the same
   Agent on the Mac.
3. Break connectivity during a send: inspect its existing operation receipt;
   reconnect must not silently send it a second time.
4. Revoke the phone on Mac and confirm reads, controls and subscriptions stop.
5. Stop sharing and confirm both network paths are unavailable.

Do not send acceptance prompts or stop commands to an unrelated running Agent.
Use an owner-selected test workspace. Background push notifications/APNs and
provider token streaming are outside this transport implementation.

[Full protocol and architecture plan](../docs/WEBSOCKET-RELAY.md)
