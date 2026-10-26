// debate-floor — keeps LiveKit voice permissions in step with the debate floor.
// Called by the debates update trigger (pg_net) with { id } whenever the turn, hold or guest changes.
//   held (waiting for "I'm ready")  → nobody may publish audio
//   someone has the floor           → only they may publish
//   all turns done (final votes)    → both debaters may publish
// Secrets: PUSH_HOOK_SECRET (shared hook secret), LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET.
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});
const LK_URL = (Deno.env.get("LIVEKIT_URL") || "").replace(/^wss:/, "https:");
const LK_KEY = Deno.env.get("LIVEKIT_API_KEY") || "";
const LK_SECRET = Deno.env.get("LIVEKIT_API_SECRET") || "";

const b64url = (buf: ArrayBuffer | Uint8Array) =>
  btoa(String.fromCharCode(...new Uint8Array(buf))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const enc = new TextEncoder();

async function adminToken(room: string) {
  const now = Math.floor(Date.now() / 1000);
  const claims = { iss: LK_KEY, sub: "maintrix-floor", nbf: now - 10, exp: now + 300, video: { room, roomAdmin: true } };
  const data = `${b64url(enc.encode(JSON.stringify({ alg: "HS256", typ: "JWT" })))}.${b64url(enc.encode(JSON.stringify(claims)))}`;
  const key = await crypto.subtle.importKey("raw", enc.encode(LK_SECRET), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return `${data}.${b64url(await crypto.subtle.sign("HMAC", key, enc.encode(data)))}`;
}

async function setPublish(room: string, identity: string, canPublish: boolean, token: string) {
  const r = await fetch(`${LK_URL}/twirp/livekit.RoomService/UpdateParticipant`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({ room, identity, permission: { canSubscribe: true, canPublish, canPublishData: true } }),
  });
  // 404 = they're not in the call right now; their next voice pass carries the right permission
  return r.status;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("method", { status: 405 });
  if (req.headers.get("x-push-secret") !== Deno.env.get("PUSH_HOOK_SECRET")) return new Response("forbidden", { status: 403 });
  if (!LK_URL || !LK_KEY || !LK_SECRET) return new Response("voice not configured", { status: 200 });

  let id = "";
  try { id = String((await req.json()).id || ""); } catch { /* ignore */ }
  if (!/^[0-9a-f-]{36}$/i.test(id)) return new Response("bad id", { status: 400 });

  const { data: d } = await db.from("debates")
    .select("id,status,creator_id,opponent_id,stage_guest,turn_holder,paused_at").eq("id", id).maybeSingle();
  if (!d || d.status !== "active") return new Response("not active", { status: 200 });

  const room = `debate:${d.id}`;
  const people = [d.creator_id, d.opponent_id, d.stage_guest].filter((x, i, a) => x && a.indexOf(x) === i) as string[];
  const allowed = (uid: string) =>
    !d.paused_at && (d.turn_holder ? d.turn_holder === uid : uid === d.creator_id || uid === d.opponent_id);

  const token = await adminToken(room);
  const result: Record<string, number> = {};
  for (const uid of people) result[uid] = await setPublish(room, uid, allowed(uid), token);
  return new Response(JSON.stringify({ room, result }), { headers: { "Content-Type": "application/json" } });
});
