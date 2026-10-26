// voice-presence — who is connected to a debate's podium voice right now.
// Body: { id: debate uuid }  →  { ids: [user uuid, ...] }  (only the debaters / brought-up guest)
// The "On the podium" row shows a picture only once that person has actually joined the podium voice.
// Secrets: LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET. Deploy with verify_jwt on.
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});
const LK_URL = (Deno.env.get("LIVEKIT_URL") || "").replace(/^wss:/, "https:");
const LK_KEY = Deno.env.get("LIVEKIT_API_KEY") || "";
const LK_SECRET = Deno.env.get("LIVEKIT_API_SECRET") || "";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...cors, "Content-Type": "application/json" } });

const b64url = (buf: ArrayBuffer | Uint8Array) =>
  btoa(String.fromCharCode(...new Uint8Array(buf))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const enc = new TextEncoder();

async function adminToken(room: string) {
  const now = Math.floor(Date.now() / 1000);
  const claims = { iss: LK_KEY, sub: "maintrix-presence", nbf: now - 10, exp: now + 120, video: { room, roomAdmin: true } };
  const data = `${b64url(enc.encode(JSON.stringify({ alg: "HS256", typ: "JWT" })))}.${b64url(enc.encode(JSON.stringify(claims)))}`;
  const key = await crypto.subtle.importKey("raw", enc.encode(LK_SECRET), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return `${data}.${b64url(await crypto.subtle.sign("HMAC", key, enc.encode(data)))}`;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method" }, 405);
  if (!LK_URL || !LK_KEY || !LK_SECRET) return json({ ids: [] });

  const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  const { data: who, error } = await admin.auth.getUser(jwt);
  if (error || !who?.user) return json({ error: "not signed in" }, 401);

  let id = "";
  try { id = String((await req.json()).id || ""); } catch { /* ignore */ }
  if (!UUID.test(id)) return json({ error: "bad id" }, 400);

  const { data: d } = await admin.from("debates").select("id,creator_id,opponent_id,stage_guest,status").eq("id", id).maybeSingle();
  if (!d) return json({ ids: [] });
  const podium = new Set([d.creator_id, d.opponent_id, d.stage_guest].filter(Boolean) as string[]);

  const room = `debate:${d.id}`;
  const r = await fetch(`${LK_URL}/twirp/livekit.RoomService/ListParticipants`, {
    method: "POST",
    headers: { Authorization: `Bearer ${await adminToken(room)}`, "Content-Type": "application/json" },
    body: JSON.stringify({ room }),
  });
  if (!r.ok) return json({ ids: [] }); // no call running yet
  const body = await r.json().catch(() => ({}));
  const ids = ((body.participants || []) as { identity?: string }[])
    .map((p) => String(p.identity || ""))
    .filter((x, i, a) => podium.has(x) && a.indexOf(x) === i);
  return json({ ids });
});
