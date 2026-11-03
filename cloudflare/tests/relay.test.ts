import { test } from "node:test";
import assert from "node:assert/strict";
import { Miniflare, convertV4MiniflareOptions } from "miniflare";
import { base64, bytes, digest } from "../src/proofs.ts";

async function signer() {
  const pair = await crypto.subtle.generateKey("Ed25519", true, ["sign", "verify"]) as CryptoKeyPair;
  const publicKey = base64(await crypto.subtle.exportKey("raw", pair.publicKey));
  const id = await digest(new Uint8Array(await crypto.subtle.exportKey("raw", pair.publicKey)));
  return { publicKey, id, async sign<T>(value: T, domain: string) { return { value, signature: base64(await crypto.subtle.sign("Ed25519", pair.privateKey, bytes(value, domain))) }; } };
}
function next(socket: any): Promise<any> {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => { cleanup(); reject(new Error("Relay message deadline")); }, 5000);
    const message = (event: any) => { cleanup(); resolve(event.data); };
    const closed = () => { cleanup(); reject(new Error("Relay closed before message")); };
    const cleanup = () => { clearTimeout(timeout); socket.removeEventListener("message", message); socket.removeEventListener("close", closed); };
    socket.addEventListener("message", message); socket.addEventListener("close", closed);
  });
}
async function fixture() {
  const mf = new Miniflare(convertV4MiniflareOptions({
    modules: true, scriptPath: new URL("../dist/index.js", import.meta.url).pathname, compatibilityDate: "2026-10-06",
    durableObjects: { ROOMS: { className: "RelayRoom", useSQLite: true }, DIRECTORY: { className: "RelayDirectory", useSQLite: true } },
    ratelimits: { ADMISSION_LIMITER: { namespace_id: "1000", simple: { limit: 1000, period: 60 } } },
    bindings: { BRIDGE_REGISTRATION_KEY: "a".repeat(64) }
  }));
  const host = await signer(), phone = await signer(), origin = "https://relay.example";
  const path = `${origin}/v3/relay/${host.id}`;
  const common = { Upgrade: "websocket", "Sec-WebSocket-Protocol": "cmux-remote.v3" };
  async function bridge(nonce = crypto.randomUUID()) {
    const record = await host.sign({ version: 3, hostID: host.id, hostPublicKey: host.publicKey, origin, nonce, timestamp: Math.floor(Date.now() / 1000) }, "relay3-registration");
    return mf.dispatchFetch(path + "?role=bridge", { headers: { ...common, Authorization: "Bearer " + "a".repeat(64), "X-Cmux-Registration": base64(new TextEncoder().encode(JSON.stringify(record))) } });
  }
  async function join(options: { nonce?: string; actor?: Awaited<ReturnType<typeof signer>>; pending?: boolean; expires?: number } = {}) {
    const actor = options.actor ?? phone;
    const permit = await host.sign({ version: 3, hostID: host.id, origin, permitID: crypto.randomUUID(), kind: options.pending ? "enrollment" : "approved", ...(options.pending ? { expiresAt: options.expires ?? Math.floor(Date.now() / 1000) + 300 } : { clientPublicKey: phone.publicKey }) }, "relay3-permit");
    const proof = await actor.sign({ version: 3, hostID: host.id, clientPublicKey: actor.publicKey, permitDigest: await digest(bytes(permit, "relay3-permit-envelope")), nonce: options.nonce ?? crypto.randomUUID(), timestamp: Math.floor(Date.now() / 1000) }, "relay3-join");
    return mf.dispatchFetch(path + "?role=client", { headers: { ...common, "X-Cmux-Relay-Permit": base64(new TextEncoder().encode(JSON.stringify(permit))), "X-Cmux-Relay-Join": base64(new TextEncoder().encode(JSON.stringify(proof))) } });
  }
  return { mf, host, phone, bridge, join };
}

test("real SQLite DO relays opaque bytes only to the selected phone", async () => {
  const f = await fixture();
  try {
    assert.equal((await f.join()).status, 503);
    const registration = await f.bridge(); assert.equal(registration.status, 101);
    const bridge = registration.webSocket!; bridge.accept();
    const ready = next(bridge); bridge.send(JSON.stringify({ kind: "registry", revoked: [] }));
    assert.equal(JSON.parse(await ready).kind, "ready");
    const opened = next(bridge), first = await f.join(); assert.equal(first.status, 101);
    const phone = first.webSocket!; phone.accept(); const channel = JSON.parse(await opened).channel_id;
    const upstream = next(bridge); phone.send(new Uint8Array([7, 8, 9]));
    const packet = JSON.parse(await upstream); assert.equal(packet.kind, "data"); assert.equal(packet.channel_id, channel); assert.equal(packet.data, "BwgJ");
    const secondOpen = next(bridge), secondJoin = await f.join(); assert.equal(secondJoin.status, 101);
    const secondPhone = secondJoin.webSocket!; secondPhone.accept(); const secondChannel = JSON.parse(await secondOpen).channel_id;
    const secondDownstream = next(secondPhone);
    const downstream = next(phone); bridge.send(JSON.stringify({ kind: "data", channel_id: channel, data: "AQID" }));
    assert.deepEqual([...new Uint8Array(await downstream)], [1, 2, 3]);
    bridge.send(JSON.stringify({ kind: "data", channel_id: secondChannel, data: "BAUG" }));
    assert.deepEqual([...new Uint8Array(await secondDownstream)], [4, 5, 6]);
    const revocation = next(bridge); bridge.send(JSON.stringify({ kind: "registry", revoked: [f.phone.id] }));
    assert.equal(JSON.parse(await revocation).kind, "ready");
    // The relay grants transport; the Bridge rejects a revoked device's reads. A
    // revoked device must still be able to submit a fresh enrollment request.
    const rejoined = await f.join(); assert.equal(rejoined.status, 101);
    rejoined.webSocket!.accept(); rejoined.webSocket!.close();
    bridge.close(); phone.close(); secondPhone.close();
  } finally { await f.mf.dispose(); }
});

test("replayed registration/join, borrowed admission and expired enrollment are denied", async () => {
  const f = await fixture();
  try {
    const nonce = crypto.randomUUID(); const registration = await f.bridge(nonce); assert.equal(registration.status, 101);
    const bridge = registration.webSocket!; bridge.accept();
    assert.equal((await f.bridge(nonce)).status, 409);
    const ready = next(bridge); bridge.send(JSON.stringify({ kind: "registry", revoked: [] })); await ready;
    assert.equal((await f.join({ actor: await signer() })).status, 401);
    assert.equal((await f.join({ pending: true, expires: Math.floor(Date.now() / 1000) - 1 })).status, 401);
    const joinNonce = crypto.randomUUID(), opened = next(bridge), client = await f.join({ nonce: joinNonce });
    assert.equal(client.status, 101); client.webSocket!.accept(); await opened;
    assert.equal((await f.join({ nonce: joinNonce })).status, 409);
    client.webSocket!.close(); bridge.close();
  } finally { await f.mf.dispose(); }
});

test("a registered Bridge lists only its own signed bootstrap and leaves the directory when offline", async () => {
  const f = await fixture();
  try {
    const bridge = (await f.bridge()).webSocket!; bridge.accept();
    const ready = next(bridge); bridge.send(JSON.stringify({ kind: "registry", revoked: [] })); await ready;
    const origin = "https://relay.example", now = Math.floor(Date.now() / 1000), windowID = crypto.randomUUID();
    const permit = await f.host.sign({ version: 3, hostID: f.host.id, origin, permitID: windowID, kind: "enrollment", expiresAt: now + 600 }, "relay3-permit");
    const bootstrap = (actor: typeof f.host) => actor.sign({ version: 2, host: { id: f.host.id, publicKey: actor.publicKey, certificateSHA256: "a".repeat(64), name: "Studio Mac" },
      endpoint: { host: "192.168.1.2", port: 7740, relay: { origin, admission: permit } }, workspaces: ["11111111-1111-1111-1111-111111111111"], windowID, expiresAt: now + 600 }, "bootstrap");
    const list = async () => (await (await f.mf.dispatchFetch(origin + "/v3/directory")).json() as { hosts: string[] }).hosts;
    assert.deepEqual(await list(), []);
    const signed = await bootstrap(f.host);
    bridge.send(JSON.stringify({ kind: "directory", data: base64(new TextEncoder().encode(JSON.stringify(signed))) }));
    let hosts: string[] = [];
    for (let attempt = 0; attempt < 20 && hosts.length === 0; attempt++) { hosts = await list(); if (!hosts.length) await new Promise(r => setTimeout(r, 50)); }
    assert.equal(hosts.length, 1);
    assert.equal(JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(hosts[0]), c => c.charCodeAt(0)))).value.host.name, "Studio Mac");
    bridge.send(JSON.stringify({ kind: "withdraw" }));
    for (let attempt = 0; attempt < 20 && hosts.length > 0; attempt++) { hosts = await list(); if (hosts.length) await new Promise(r => setTimeout(r, 50)); }
    assert.deepEqual(hosts, []);
    // Another key cannot list itself under this host's identity; the Bridge socket is closed.
    const closed = new Promise(resolve => bridge.addEventListener("close", resolve));
    bridge.send(JSON.stringify({ kind: "directory", data: base64(new TextEncoder().encode(JSON.stringify(await bootstrap(await signer())))) }));
    await closed;
    assert.deepEqual(await list(), []);
  } finally { await f.mf.dispose(); }
});

test("a Bridge whose clock runs ahead still lists, but a window beyond the skew allowance closes its socket", async () => {
  const f = await fixture();
  try {
    const bridge = (await f.bridge()).webSocket!; bridge.accept();
    const ready = next(bridge); bridge.send(JSON.stringify({ kind: "registry", revoked: [] })); await ready;
    const origin = "https://relay.example", now = Math.floor(Date.now() / 1000);
    const bootstrap = async (expiresAt: number) => {
      const windowID = crypto.randomUUID();
      const permit = await f.host.sign({ version: 3, hostID: f.host.id, origin, permitID: windowID, kind: "enrollment", expiresAt }, "relay3-permit");
      return f.host.sign({ version: 2, host: { id: f.host.id, publicKey: f.host.publicKey, certificateSHA256: "a".repeat(64), name: "Studio Mac" },
        endpoint: { host: "192.168.1.2", port: 7740, relay: { origin, admission: permit } }, workspaces: ["11111111-1111-1111-1111-111111111111"], windowID, expiresAt }, "bootstrap");
    };
    const list = async () => (await (await f.mf.dispatchFetch(origin + "/v3/directory")).json() as { hosts: string[] }).hosts;
    const send = async (expiresAt: number) => bridge.send(JSON.stringify({ kind: "directory", data: base64(new TextEncoder().encode(JSON.stringify(await bootstrap(expiresAt)))) }));
    // Five seconds ahead of the edge, as a Mac whose clock drifted would stamp it.
    await send(now + 605);
    let hosts: string[] = [];
    for (let attempt = 0; attempt < 20 && hosts.length === 0; attempt++) { hosts = await list(); if (!hosts.length) await new Promise(r => setTimeout(r, 50)); }
    assert.equal(hosts.length, 1);
    const closed = new Promise(resolve => bridge.addEventListener("close", resolve));
    await send(now + 900);
    await closed;
  } finally { await f.mf.dispose(); }
});
