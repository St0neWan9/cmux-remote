import { DurableObject } from "cloudflare:workers";
export interface DirectoryEntry { hostID: string; value: string; expires: number }

/** Bounded index of currently listed hosts; values stay host-signed and are verified again by phones. */
export class RelayDirectory extends DurableObject<Record<string, unknown>> {
  constructor(ctx: DurableObjectState, env: Record<string, unknown>) {
    super(ctx, env);
    ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS entries (host_id TEXT PRIMARY KEY, value TEXT NOT NULL, expires INTEGER NOT NULL, updated INTEGER NOT NULL)");
  }
  async fetch(request: Request): Promise<Response> {
    const now = Math.floor(Date.now() / 1000), path = new URL(request.url).pathname;
    this.ctx.storage.sql.exec("DELETE FROM entries WHERE expires <= ?", now);
    if (path === "/list") {
      const rows = this.ctx.storage.sql.exec<{ value: string }>("SELECT value FROM entries ORDER BY updated DESC LIMIT 64").toArray();
      return Response.json({ hosts: rows.map(row => row.value) }, { headers: { "Cache-Control": "no-store" } });
    }
    const body = await request.json() as Partial<DirectoryEntry>;
    if (typeof body.hostID !== "string" || !/^[0-9a-f]{64}$/.test(body.hostID)) return new Response("invalid_directory", { status: 400 });
    if (path === "/remove") { this.ctx.storage.sql.exec("DELETE FROM entries WHERE host_id = ?", body.hostID); return new Response(null, { status: 204 }); }
    if (path !== "/put" || typeof body.value !== "string" || body.value.length > 12_000 || !Number.isSafeInteger(body.expires)) return new Response("invalid_directory", { status: 400 });
    const known = this.ctx.storage.sql.exec("SELECT host_id FROM entries WHERE host_id = ?", body.hostID).toArray().length > 0;
    const count = this.ctx.storage.sql.exec<{ count: number }>("SELECT COUNT(*) AS count FROM entries").one().count;
    if (!known && count >= 256) return new Response("capacity", { status: 429 });
    this.ctx.storage.sql.exec("INSERT OR REPLACE INTO entries (host_id, value, expires, updated) VALUES (?, ?, ?, ?)", body.hostID, body.value, body.expires, now);
    return new Response(null, { status: 204 });
  }
}
