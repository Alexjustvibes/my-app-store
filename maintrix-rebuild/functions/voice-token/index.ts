// voice-token — mints a LiveKit access token for a voice room.
// Body: { kind: "room" | "channel" | "debate", id: uuid }  →  { token, url, role }
//   room    : a chat room / DM / group — anyone who can read it may talk
//   channel : a server voice channel (voice_channels.id) — same rule via its room
//   debate  : debaters (and the brought-up guest) are speakers, everyone else listens
// Secrets: LIVEKIT_URL (wss://<project>.livekit.cloud), LIVEKIT_API_KEY, LIVEKIT_API_SECRET.
// Deploy with verify_jwt on.
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});
const LK_URL = Deno.env.get("LIVEKIT_URL") || "";
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

async function livekitToken(identity: string, name: string, room: string, canPublish: boolean) {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "HS256", typ: "JWT" };
  const claims = {
    iss: LK_KEY, sub: identity, name, jti: `${identity}-${now}`,
    nbf: now - 10, exp: now + 6 * 3600,
    video: { room, roomJoin: true, canSubscribe: true, canPublish, canPublishData: true },
  };
  const data = `${b64url(enc.encode(JSON.stringify(header)))}.${b64url(enc.encode(JSON.stringify(claims)))}`;
  const key = await crypto.subtle.importKey("raw", enc.encode(LK_SECRET), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(data));
  return `${data}.${b64url(sig)}`;
}

async function canReadRoom(roomId: string, uid: string) {
  const { data: r } = await admin.from("rooms").select("id,is_public").eq("id", roomId).maybeSingle();
  if (!r) return false;
  if (r.is_public) return true;
  const { data: m } = await admin.from("room_members").select("user_id").eq("room_id", roomId).eq("user_id", uid).maybeSingle();
  return !!m;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method" }, 405);
  if (!LK_URL || !LK_KEY || !LK_SECRET) return json({ error: "Voice isn't set up yet" }, 503);

  const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  const { data: who, error } = await admin.auth.getUser(jwt);
  if (error || !who?.user) return json({ error: "not signed in" }, 401);
  const uid = who.user.id;

  let kind = "", id = "";
  try { const b = await req.json(); kind = String(b.kind || ""); id = String(b.id || ""); } catch { /* ignore */ }
  if (!UUID.test(id)) return json({ error: "bad id" }, 400);

  const { data: me } = await admin.from("profiles").select("name,handle,banned").eq("id", uid).maybeSingle();
  if (!me || me.banned) return json({ error: "not allowed" }, 403);

  let speaker = true;
  if (kind === "room") {
    if (!(await canReadRoom(id, uid))) return json({ error: "not allowed" }, 403);
  } else if (kind === "channel") {
    const { data: ch } = await admin.from("voice_channels").select("room_id").eq("id", id).maybeSingle();
    if (!ch || !(await canReadRoom(ch.room_id, uid))) return json({ error: "not allowed" }, 403);
  } else if (kind === "debate") {
    const { data: d } = await admin.from("debates").select("creator_id,opponent_id,stage_guest,status").eq("id", id).maybeSingle();
    if (!d) return json({ error: "not found" }, 404);
    speaker = [d.creator_id, d.opponent_id, d.stage_guest].includes(uid) && d.status !== "ended";
  } else {
    return json({ error: "bad kind" }, 400);
  }

  const token = await livekitToken(uid, String(me.name || me.handle || "Member").slice(0, 60), `${kind}:${id}`, speaker);
  return json({ token, url: LK_URL, role: speaker ? "speaker" : "listener" });
});
