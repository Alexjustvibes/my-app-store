// send-push — delivers one notification to every device a user has subscribed.
//
// Called by the trg_notify_push database trigger (via pg_net) with
//   POST { user_id, title, body, url, tag, type }
//   header x-push-secret: <vault push_secret>
//
// Keys come from the DB (push_secrets() RPC, service-role only) so nothing has
// to be pasted into Edge Function secrets. Deploy with JWT verification OFF —
// pg_net sends no Supabase JWT; the shared secret header is the auth.
//
// Dead subscriptions (endpoint gone: 404 / 410) are deleted on the spot.

import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const sb = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

let keys: { push_secret?: string; vapid_public?: string; vapid_private?: string } | null = null;
async function loadKeys() {
  if (keys) return keys;
  const { data, error } = await sb.rpc("push_secrets");
  if (error) throw new Error("push_secrets rpc failed: " + error.message);
  keys = data ?? {};
  if (keys.vapid_public && keys.vapid_private) {
    webpush.setVapidDetails("mailto:push@maintrix.app", keys.vapid_public, keys.vapid_private);
  }
  return keys;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("method not allowed", { status: 405 });

  let k;
  try { k = await loadKeys(); } catch (e) { return new Response(String(e), { status: 500 }); }
  if (!k.push_secret || !k.vapid_public || !k.vapid_private) {
    return new Response("push secrets not configured in vault", { status: 503 });
  }
  if (req.headers.get("x-push-secret") !== k.push_secret) {
    return new Response("unauthorized", { status: 401 });
  }

  let msg: { user_id?: string; title?: string; body?: string; url?: string; tag?: string; type?: string };
  try { msg = await req.json(); } catch { return new Response("bad json", { status: 400 }); }
  if (!msg.user_id) return new Response("user_id required", { status: 400 });

  const { data: subs, error } = await sb
    .from("push_subscriptions")
    .select("id,endpoint,p256dh,auth")
    .eq("user_id", msg.user_id);
  if (error) return new Response("subs query failed: " + error.message, { status: 500 });
  if (!subs?.length) return Response.json({ sent: 0, removed: 0 });

  const payload = JSON.stringify({
    title: msg.title || "Maintrix",
    body: msg.body || "",
    url: msg.url || "/",
    tag: msg.tag || undefined,
    type: msg.type || "generic",
  });

  let sent = 0;
  const dead: string[] = [];
  const errors: string[] = [];
  await Promise.all(subs.map(async (s) => {
    try {
      await webpush.sendNotification(
        { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
        payload,
        { TTL: 60 * 60, urgency: msg.type === "dm" ? "high" : "normal" },
      );
      sent++;
    } catch (e) {
      const code = (e as { statusCode?: number })?.statusCode;
      if (code === 404 || code === 410) dead.push(s.id);
      else errors.push(`${code ?? "?"}: ${(e as Error)?.message ?? e}`);
    }
  }));
  if (dead.length) await sb.from("push_subscriptions").delete().in("id", dead);

  return Response.json({ sent, removed: dead.length, errors });
});
