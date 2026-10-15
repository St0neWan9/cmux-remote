import { DurableObject } from "cloudflare:workers";
import { base64, bytes, digest, fresh, header, Join, Permit, Registration, RelayFailure, secretMatches, Signed, unbase64, verify } from "./proofs";
import { DirectoryEntry, RelayDirectory } from "./directory";
export { RelayDirectory };
interface Env { ROOMS: DurableObjectNamespace; DIRECTORY: DurableObjectNamespace; ADMISSION_LIMITER: RateLimit; BRIDGE_REGISTRATION_KEY?: string }
interface Connection {
  role: "bridge" | "client"; channel: string; clientID?: string; pending?: boolean;
  bridge?: string; ready?: boolean; expiresAt?: number; window: number; messages: number; byteCount: number; origin?: string;
}
interface Bootstrap {
  version: number; host: { id: string; publicKey: string; certificateSHA256: string; name: string };
  endpoint: { host: string; port: number; relay?: { origin: string; admission: Signed<Permit> } };
  workspaces: string[]; windowID: string; expiresAt: number;
}
/** Rooms and the directory are created in Western North America (Los Angeles), the edge that serves the
 * owner's Mac and phone best; a hint only applies when an object is first created, so a new placement needs
 * a new name. A room holds only state its Bridge re-registers on every connection. */
const placement = { locationHint: "wnam" } as const;
const directory = (env: Env) => env.DIRECTORY.get(env.DIRECTORY.idFromName("directory:wnam"), placement);
const identity = (value: unknown): value is string => typeof value === "string" && /^[0-9a-f]{64}$/.test(value);
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === "/v3/directory" && request.method === "GET" && !request.headers.get("Upgrade")) {
      // Hosts that chose to be listed while online; entries are host-signed and verified again by the phone.
      if (!await env.ADMISSION_LIMITER.limit({ key: request.headers.get("CF-Connecting-IP") ?? "unknown" }).then(x => x.success)) return new Response("rate_limited", { status: 429 });
      return directory(env).fetch("https://directory/list");
    }
    if (request.method !== "GET" || request.headers.get("Upgrade")?.toLowerCase() !== "websocket") return new Response("websocket_required", { status: 426 });
    const match = /^\/v3\/relay\/([0-9a-f]{64})$/.exec(url.pathname), role = url.searchParams.get("role");
    if (!match || !["bridge", "client"].includes(role ?? "") || [...url.searchParams].length !== 1 || url.searchParams.getAll("role").length !== 1) return new Response("invalid_route", { status: 400 });
    if (!(request.headers.get("Sec-WebSocket-Protocol") ?? "").split(",").map(x => x.trim()).includes("cmux-remote.v3")) return new Response("unsupported_protocol", { status: 400 });
    if (!await env.ADMISSION_LIMITER.limit({ key: request.headers.get("CF-Connecting-IP") ?? "unknown" }).then(x => x.success)) return new Response("rate_limited", { status: 429 });
    if (role === "bridge" && !await secretMatches(request.headers.get("Authorization"), env.BRIDGE_REGISTRATION_KEY)) return new Response("unauthorized", { status: 401 });
    return env.ROOMS.get(env.ROOMS.idFromName("wnam:" + match[1]), placement).fetch(request);
  }
} satisfies ExportedHandler<Env>;

/** One host's opaque relay, reconstructed from socket attachments after hibernation. */
export class RelayRoom extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS nonces (key TEXT PRIMARY KEY, expires INTEGER NOT NULL)");
    ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS registry (id INTEGER PRIMARY KEY, value TEXT NOT NULL)");
  }
  async fetch(request: Request): Promise<Response> {
    try {
      const url = new URL(request.url), hostID = url.pathname.split("/").at(-1)!, role = url.searchParams.get("role");
      const now = Math.floor(Date.now() / 1000);
      let metadata: Connection;
      if (role === "bridge") {
        if (!await secretMatches(request.headers.get("Authorization"), this.env.BRIDGE_REGISTRATION_KEY)) throw new RelayFailure("unauthorized");
        const signed = header<Registration>(request, "X-Cmux-Registration"), proof = signed.value;
        if (proof.version !== 3 || proof.hostID !== hostID || proof.origin !== url.origin || !identity(hostID)) throw new RelayFailure("invalid_registration");
        fresh(proof.nonce, proof.timestamp, now);
        if (await digest(unbase64(proof.hostPublicKey, 32)) !== hostID) throw new RelayFailure("invalid_identity");
        await verify(signed, "relay3-registration", proof.hostPublicKey);
        this.claimNonce("bridge:" + proof.nonce, proof.timestamp + 61, now);
        const existing = await this.ctx.storage.get<string>("hostKey");
        if (existing && existing !== proof.hostPublicKey) throw new RelayFailure("host_changed");
        await this.ctx.storage.put("hostKey", proof.hostPublicKey);
        await this.ctx.storage.put("hostID", hostID);
        for (const socket of this.ctx.getWebSockets()) socket.close(1012, "bridge_replaced");
        metadata = { role: "bridge", channel: crypto.randomUUID(), ready: false, window: now, messages: 0, byteCount: 0, origin: url.origin };
      } else if (role === "client") {
        const bridge = this.bridge(); if (!bridge) throw new RelayFailure("bridge_offline", 503);
        const owner = bridge.deserializeAttachment() as Connection;
        if (!owner.ready) throw new RelayFailure("bridge_starting", 503);
        const hostKey = await this.ctx.storage.get<string>("hostKey"); if (!hostKey) throw new RelayFailure("bridge_offline", 503);
        const permit = header<Permit>(request, "X-Cmux-Relay-Permit"), signed = header<Join>(request, "X-Cmux-Relay-Join");
        await verify(permit, "relay3-permit", hostKey);
        const value = permit.value, proof = signed.value;
        if (value.version !== 3 || value.hostID !== hostID || value.origin !== url.origin || typeof value.permitID !== "string" || value.permitID.length > 128 || !value.permitID) throw new RelayFailure("invalid_permit");
        if (proof.version !== 3 || proof.hostID !== hostID || proof.permitDigest !== await digest(bytes(permit, "relay3-permit-envelope"))) throw new RelayFailure("invalid_join");
        fresh(proof.nonce, proof.timestamp, now); await verify(signed, "relay3-join", proof.clientPublicKey);
        const clientID = await digest(unbase64(proof.clientPublicKey, 32));
        const pending = value.kind === "enrollment";
        if (pending) {
          if (value.clientPublicKey !== undefined || !Number.isSafeInteger(value.expiresAt) || value.expiresAt! <= now || value.expiresAt! > now + 600) throw new RelayFailure("enrollment_expired");
        } else if (value.kind !== "approved" || value.expiresAt !== undefined || value.clientPublicKey !== proof.clientPublicKey) throw new RelayFailure("invalid_permit");
        const registry = this.ctx.storage.sql.exec<{ value: string }>("SELECT value FROM registry WHERE id = 1").toArray();
        const revoked = registry.length ? JSON.parse(registry[0].value) as string[] : [];
        if (revoked.includes(clientID)) throw new RelayFailure("revoked");
        const clients = this.ctx.getWebSockets("client").filter(x => x.readyState === 1);
        if (clients.filter(x => (x.deserializeAttachment() as Connection).pending === pending).length >= (pending ? 4 : 16)) throw new RelayFailure("capacity", 429);
        this.claimNonce(clientID + ":" + proof.nonce, proof.timestamp + 61, now);
        metadata = { role: "client", channel: crypto.randomUUID(), bridge: owner.channel, clientID, pending, expiresAt: pending ? value.expiresAt : undefined, window: now, messages: 0, byteCount: 0 };
      } else throw new RelayFailure("invalid_role", 400);
      const pair = new WebSocketPair(), [client, server] = Object.values(pair);
      this.ctx.acceptWebSocket(server, metadata.role === "bridge" ? ["bridge"] : ["client", "channel:" + metadata.channel]);
      server.serializeAttachment(metadata);
      if (metadata.role === "bridge") {
        console.log(`relay bridge-connected host=${hostID.slice(0, 8)}`);
      } else if (metadata.role === "client") {
        console.log(`relay client-connected host=${hostID.slice(0, 8)} pending=${metadata.pending}`);
        this.bridge()?.send(JSON.stringify({ kind: "open", channel_id: metadata.channel, client_id: metadata.clientID }));
      }
      return new Response(null, { status: 101, webSocket: client, headers: { "Sec-WebSocket-Protocol": "cmux-remote.v3" } });
    } catch (error) {
      const failure = error instanceof RelayFailure ? error : new RelayFailure("invalid_request", 400);
      return new Response(failure.code, { status: failure.status });
    }
  }
  async webSocketMessage(socket: WebSocket, message: string | ArrayBuffer): Promise<void> {
    try {
      const state = socket.deserializeAttachment() as Connection;
      if (!state) throw new RelayFailure("invalid_connection");
      this.rate(socket, state, typeof message === "string" ? new TextEncoder().encode(message).length : message.byteLength);
      if (state.role === "client") {
        if (typeof message === "string" || message.byteLength > 2_100_000) throw new RelayFailure("invalid_packet");
        if (state.expiresAt && state.expiresAt <= Math.floor(Date.now() / 1000)) throw new RelayFailure("enrollment_expired");
        const bridge = this.bridge(), owner = bridge?.deserializeAttachment() as Connection | undefined;
        if (!bridge || owner?.channel !== state.bridge) throw new RelayFailure("bridge_offline");
        bridge.send(JSON.stringify({ kind: "data", channel_id: state.channel, data: base64(message) }));
      } else {
        if (this.bridge() !== socket || typeof message !== "string" || message.length > 3_000_000) throw new RelayFailure("invalid_bridge_packet");
        const envelope = JSON.parse(message) as { kind: string; channel_id?: string; data?: string; revoked?: unknown[] };
        if (envelope.kind === "directory" || envelope.kind === "withdraw") {
          const hostID = await this.ctx.storage.get<string>("hostID");
          if (!hostID) throw new RelayFailure("invalid_bridge_packet");
          if (envelope.kind === "withdraw") { await directory(this.env).fetch("https://directory/remove", { method: "POST", body: JSON.stringify({ hostID }) }); return; }
          await directory(this.env).fetch("https://directory/put", { method: "POST", body: JSON.stringify(await this.entry(hostID, envelope.data, state)) });
          return;
        }
        if (envelope.kind === "registry") {
          if (!envelope.revoked || envelope.revoked.length > 100 || !envelope.revoked.every(identity)) throw new RelayFailure("invalid_registry");
          // SQLite is synchronous: ordering with client admission/revocation does not depend on detached promises.
          this.ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS registry (id INTEGER PRIMARY KEY, value TEXT NOT NULL)");
          this.ctx.storage.sql.exec("INSERT OR REPLACE INTO registry (id, value) VALUES (1, ?)", JSON.stringify(envelope.revoked));
          state.ready = true; socket.serializeAttachment(state);
          socket.send(JSON.stringify({ kind: "ready" }));
          for (const peer of this.ctx.getWebSockets("client")) if (envelope.revoked.includes((peer.deserializeAttachment() as Connection).clientID ?? "")) peer.close(1008, "revoked");
          return;
        }
        if (!envelope.channel_id || !/^[0-9a-f-]{36}$/.test(envelope.channel_id)) throw new RelayFailure("invalid_channel");
        const peer = this.ctx.getWebSockets("channel:" + envelope.channel_id).find(x => x.readyState === 1 && (x.deserializeAttachment() as Connection).bridge === state.channel);
        if (!peer) return; // A cancelled connection has no offline queue.
        if (envelope.kind === "close") peer.close(1000, "bridge_closed");
        else if (envelope.kind === "data" && envelope.data) {
          const data = unbase64(envelope.data, 2_100_000); peer.send(data);
        } else throw new RelayFailure("invalid_bridge_packet");
      }
    } catch (error) { socket.close(1008, error instanceof RelayFailure ? error.code : "invalid_packet"); }
  }
  async webSocketClose(socket: WebSocket, code: number, reason: string, wasClean: boolean): Promise<void> {
    const state = socket.deserializeAttachment() as Connection | undefined;
    // Who closed the socket and how, so a bridge that drops without a close frame can be told from one the edge ended.
    console.log(`relay ${state?.role ?? "unknown"}-closed channel=${(state?.channel ?? "?").slice(0, 8)} code=${code} clean=${wasClean} reason=${reason.slice(0, 40)}`);
    if (state?.role === "bridge") {
      const hostID = await this.ctx.storage.get<string>("hostID");
      console.log(`relay bridge-disconnected host=${hostID?.slice(0, 8) ?? "unknown"}`);
      const replacement = this.bridge();
      if (!replacement || (replacement.deserializeAttachment() as Connection).channel === state.channel) {
        for (const peer of this.ctx.getWebSockets("client")) if ((peer.deserializeAttachment() as Connection).bridge === state.channel) peer.close(1012, "bridge_offline");
        // An offline host leaves the directory; its next registration lists it again.
        const hostID = await this.ctx.storage.get<string>("hostID");
        if (hostID) await directory(this.env).fetch("https://directory/remove", { method: "POST", body: JSON.stringify({ hostID }) });
      }
    } else if (state?.role === "client") {
      console.log(`relay client-disconnected channel=${state.channel.slice(0, 8)}`);
      this.bridge()?.send(JSON.stringify({ kind: "close", channel_id: state.channel }));
    }
  }
  webSocketError(socket: WebSocket, error: unknown): void {
    const state = socket.deserializeAttachment() as Connection | undefined;
    console.log(`relay ${state?.role ?? "unknown"}-error channel=${(state?.channel ?? "?").slice(0, 8)} error=${String((error as Error)?.message ?? error).slice(0, 80)}`);
    socket.close(1011, "connection_failed");
  }
  /** Accepts only this host's own signed bootstrap with a current relay enrollment permit for this origin. */
  private async entry(hostID: string, data: string | undefined, state: Connection): Promise<DirectoryEntry> {
    const hostKey = await this.ctx.storage.get<string>("hostKey");
    if (!hostKey || !data || !state.origin) throw new RelayFailure("invalid_directory");
    let signed: Signed<Bootstrap>;
    try { signed = JSON.parse(new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(unbase64(data, 8192))) as Signed<Bootstrap>; } catch { throw new RelayFailure("invalid_directory"); }
    const value = signed?.value, now = Math.floor(Date.now() / 1000), relay = value?.endpoint?.relay;
    if (value?.version !== 2 || value.host?.id !== hostID || value.host.publicKey !== hostKey || !relay || relay.origin !== state.origin
      || !Number.isSafeInteger(value.expiresAt) || value.expiresAt <= now || value.expiresAt > now + 600
      || typeof value.host.name !== "string" || value.host.name.length > 128) throw new RelayFailure("invalid_directory");
    await verify(signed, "bootstrap", hostKey);
    const permit = relay.admission?.value;
    if (permit?.kind !== "enrollment" || permit.hostID !== hostID || permit.origin !== state.origin || permit.permitID !== value.windowID || permit.expiresAt !== value.expiresAt) throw new RelayFailure("invalid_directory");
    await verify(relay.admission, "relay3-permit", hostKey);
    return { hostID, value: data, expires: value.expiresAt };
  }
  private bridge(): WebSocket | undefined { return this.ctx.getWebSockets("bridge").find(x => x.readyState === 1); }
  private claimNonce(key: string, expires: number, now: number): void {
    this.ctx.storage.sql.exec("DELETE FROM nonces WHERE expires <= ?", now);
    const count = this.ctx.storage.sql.exec<{ count: number }>("SELECT COUNT(*) AS count FROM nonces").one().count;
    if (count >= 4096) throw new RelayFailure("capacity", 429);
    const found = this.ctx.storage.sql.exec("SELECT key FROM nonces WHERE key = ?", key).toArray();
    if (found.length) throw new RelayFailure("replayed_proof", 409);
    this.ctx.storage.sql.exec("INSERT INTO nonces (key, expires) VALUES (?, ?)", key, expires);
  }
  private rate(socket: WebSocket, state: Connection, count: number): void {
    const now = Math.floor(Date.now() / 1000);
    if (state.window !== now) { state.window = now; state.messages = 0; state.byteCount = 0; }
    state.messages++; state.byteCount += count;
    if (count > 3_000_000 || state.messages > (state.role === "bridge" ? 1024 : 256) || state.byteCount > (state.role === "bridge" ? 16_777_216 : 4_194_304)) {
      console.warn(`relay rate-limited role=${state.role} messages=${state.messages} bytes=${state.byteCount}`);
      throw new RelayFailure("rate_limited", 429);
    }
    socket.serializeAttachment(state);
  }
}
