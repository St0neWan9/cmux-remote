import { readFileSync } from "node:fs";
import { Miniflare, convertV4MiniflareOptions } from "miniflare";
const mf = new Miniflare(convertV4MiniflareOptions({
  modules: true, scriptPath: new URL("../dist/index.js", import.meta.url).pathname,
  compatibilityDate: "2026-10-13", host: "127.0.0.1", port: 0,
  https: true, httpsCert: readFileSync(process.argv[2], "utf8"), httpsKey: readFileSync(process.argv[3], "utf8"),
  durableObjects: { ROOMS: { className: "RelayRoom", useSQLite: true } },
  ratelimits: { ADMISSION_LIMITER: { namespace_id: "1000", simple: { limit: 1000, period: 60 } } },
  bindings: { BRIDGE_REGISTRATION_KEY: "a".repeat(64) }
}));
console.log((await mf.ready).origin);
let stopping = false;
async function stop() { if (stopping) return; stopping = true; await mf.dispose(); process.exit(0); }
process.on("SIGTERM", stop); process.on("SIGINT", stop); process.stdin.on("end", stop); process.stdin.resume();
