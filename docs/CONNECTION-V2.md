# Connection protocol v2

The Bridge, iPhone app and shared Mac client use one host identity and per-device authorization. QR entry is retained. The QR contains a host-signed short-lived enrollment window, public host key, TLS certificate fingerprint, endpoint and the owner-selected workspace IDs. It contains no permanent bearer credential or device private key.

## Owner workflow

Run inside a cmux terminal when the socket mode is `cmuxOnly`:

```sh
swift build
.build/debug/cmux-remote serve --pair
```

This initializes private state if needed, starts HTTPS and local administration, advertises `_cmux-remote._tcp` on the LAN and prints the enrollment QR. The window defaults to five minutes. The iPhone scans the code and requests approval. The Mac owner inspects the pending client and approves its exact request:

```sh
.build/debug/cmux-remote enrollment pending
.build/debug/cmux-remote enrollment approve REQUEST_ID --workspace WORKSPACE_UUID --control
```

Use a current UUID from the requested scope. Repeat `--workspace` to approve more than one. Omitting `--control` grants viewing, project reads and Feed reads. `--control` adds conversation control and Feed replies; it does not implicitly add terminal mirroring or terminal input. Other clients can explicitly request separate capabilities, and the owner can use repeated `--capability` flags. An approval can narrow a request's scope and cannot expand it.

The state directory defaults to `~/.local/state/cmux-remote`. When using a custom `--state`, use it consistently for every command. Further owner commands:

```sh
cmux-remote enrollment open --workspace WORKSPACE_UUID
cmux-remote enrollment deny REQUEST_ID
cmux-remote enrollment close
cmux-remote clients list
cmux-remote clients revoke CLIENT_ID
```

`pairing` is an alias for opening a new enrollment window on the running service. Owner operations are restricted to its owner-only Unix socket, never an HTTPS route. A kernel lease prevents a second process from owning the same registry and admin socket. A new process starts with enrollment closed; existing approved clients restore authorization without reopening it.

## Identity and request proof

Host and client identities use CryptoKit Ed25519 signing keys (`Curve25519.Signing`). Identity IDs are lowercase SHA-256 hashes of the raw 32-byte public key. Private host keys and the client registry are owner-protected outside the checkout; iPhone private keys and saved grants use device-only Keychain. Simulator verification uses owner-only sandbox files and does not establish physical Keychain behavior.

Signature input is UTF-8 `cmux-remote/2/DOMAIN\n`, followed by sorted-key JSON with unescaped slashes. Dates use integer epoch seconds. Domains are `bootstrap`, `host`, `enrollment-request`, `enrollment-status`, `grant` and `request`. Enrollment binds host ID, window ID, client ID/public key, request ID, fresh nonce, client kind/name, requested workspace/capability scope and expiry. The owner approves that exact record. Denied, cancelled and expired requests issue no grants.

Bonjour advertisements contain only public discovery metadata. A service name is not trust. First use requires a trusted QR or explicit comparison/confirmation of the advertised host identity. The client pins the exact TLS leaf before transmitting enrollment or signed resource requests and then verifies host signatures with the trusted public key.

Every authenticated resource request has an `Authorization: CmuxV2 BASE64_SIGNED_PROOF` header. Its proof binds host ID, device ID, fresh Bridge epoch, exact method/raw URI/body SHA-256, nonce and timestamp. The server verifies the enrolled device key, rejects revoked clients, accepts timestamps only within 60 seconds, and rejects repeated nonces. The nonce cache is bounded; reaching capacity rejects requests rather than evicting still-valid replay protection. Each server run has a new signed epoch, preventing captured requests from replaying after a restart.

The saved grant is not a bearer token. Possessing it without the device's private key does not authorize requests. Scope and revocation are rechecked after backend awaits and at the final service binding used for reads/writes. Browsing never focuses the host desktop. No route forwards a client-selected cmux RPC method.

On endpoint changes, the saved host ID, public key, TLS pin, device identity and grant must remain unchanged. Existing open views retain the same shared client object while its actor replaces the transport. In-flight writes keep their original transport and are never retried automatically. A changed host identity or certificate fails closed; automatic certificate-renewal continuity is not implemented.

## Routes and migration

Public HTTPS routes:

- `GET /v2/identity`: host-signed identity and runtime epoch.
- `GET /v2/enrollment/bootstrap`: host-signed currently open enrollment window.
- `POST /v2/enrollment/request`: device-signed request for owner approval.
- `POST /v2/enrollment/status`: device-signed query for that exact request.
- `POST /v2/enrollment/cancel`: cancel that exact pending request.

Authenticated `/v2/status`, `/v2/workspaces`, `/v2/sessions`, `/v2/feed` and the conversation/file/decision routes retain the existing resource DTOs, filtered by granted workspaces and capabilities. Unknown workspace bindings fail closed. The shared client retains `/v1/...` resource names as its call-site API and maps them to signed `/v2/...` requests on the wire.

Legacy `/v1` shared-token access is disabled by default. The owner can explicitly enable it with `serve --legacy`; `pairing --legacy` emits the old QR. Previously saved implicit pairings ask for re-enrollment. An explicitly chosen legacy connection can be restored, but it remains shared authority and is never silently promoted to a separately revocable client.

Snapshots and foreground polling still supply conversation updates. Bounded subscriptions, durable mutation receipts/cursors and the Mac mirror feasibility gates are separate work in the unified plan. This connection implementation does not establish physical camera scanning, Wi-Fi handoff or parity with native terminal mirroring.
