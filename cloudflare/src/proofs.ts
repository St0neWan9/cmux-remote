export interface Signed<T> { value: T; signature: string }
export interface Permit {
  version: number; hostID: string; origin: string; permitID: string;
  kind: "enrollment" | "approved"; clientPublicKey?: string; expiresAt?: number;
}
export interface Registration {
  version: number; hostID: string; hostPublicKey: string; origin: string;
  nonce: string; timestamp: number;
}
export interface Join {
  version: number; hostID: string; clientPublicKey: string; permitDigest: string;
  nonce: string; timestamp: number;
}
export class RelayFailure extends Error {
  constructor(readonly code: string, readonly status = 401) { super(code); }
}
export function canonical(value: unknown): string {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return "[" + value.map(canonical).join(",") + "]";
  const object = value as Record<string, unknown>;
  return "{" + Object.keys(object).sort().map(key => JSON.stringify(key) + ":" + canonical(object[key])).join(",") + "}";
}
export function bytes(value: unknown, domain: string): Uint8Array {
  return new TextEncoder().encode("cmux-remote/2/" + domain + "\n" + canonical(value));
}
export function base64(data: ArrayBuffer | Uint8Array): string {
  const input = data instanceof Uint8Array ? data : new Uint8Array(data);
  let result = "";
  for (let offset = 0; offset < input.length; offset += 16384) result += String.fromCharCode(...input.subarray(offset, offset + 16384));
  return btoa(result);
}
export function unbase64(value: string, maximum: number): Uint8Array {
  if (typeof value !== "string" || value.length > Math.ceil(maximum / 3) * 4 + 4 || !/^[A-Za-z0-9+/]*={0,2}$/.test(value)) throw new RelayFailure("invalid_packet", 400);
  let raw: string;
  try { raw = atob(value); } catch { throw new RelayFailure("invalid_packet", 400); }
  if (raw.length > maximum) throw new RelayFailure("too_large", 413);
  return Uint8Array.from(raw, x => x.charCodeAt(0));
}
export async function digest(data: Uint8Array): Promise<string> {
  return [...new Uint8Array(await crypto.subtle.digest("SHA-256", data))].map(x => x.toString(16).padStart(2, "0")).join("");
}
export async function verify<T>(signed: Signed<T>, domain: string, publicKey: string): Promise<void> {
  if (!signed || typeof signed.signature !== "string") throw new RelayFailure("invalid_proof");
  const raw = unbase64(publicKey, 32), signature = unbase64(signed.signature, 64);
  if (raw.length !== 32 || signature.length !== 64) throw new RelayFailure("invalid_proof");
  const key = await crypto.subtle.importKey("raw", raw, "Ed25519", false, ["verify"]);
  if (!await crypto.subtle.verify("Ed25519", key, signature, bytes(signed.value, domain))) throw new RelayFailure("invalid_proof");
}
export function header<T>(request: Request, name: string): Signed<T> {
  try {
    const value = request.headers.get(name);
    if (!value || value.length > 8192) throw new Error();
    return JSON.parse(new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(unbase64(value, 6144))) as Signed<T>;
  } catch { throw new RelayFailure("invalid_proof"); }
}
export function fresh(nonce: string, timestamp: number, now: number): void {
  if (typeof nonce !== "string" || !/^[0-9a-f-]{36}$/i.test(nonce) || !Number.isSafeInteger(timestamp) || Math.abs(timestamp - now) > 60) throw new RelayFailure("expired_proof");
}
export async function secretMatches(presented: string | null, secret: string | undefined): Promise<boolean> {
  if (!secret || secret.length < 32 || secret.length > 256 || !presented || presented.length > 264) return false;
  const lhs = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(presented)));
  const rhs = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode("Bearer " + secret)));
  let difference = 0; for (let i = 0; i < 32; i++) difference |= lhs[i] ^ rhs[i]; return difference === 0;
}
