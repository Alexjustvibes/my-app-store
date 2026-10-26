// send-push — called by the notifications insert trigger (pg_net) with { id }.
// Loads the notification, respects the recipient's notif_prefs, and delivers a Web Push
// to each of their subscriptions. Dead subscriptions (404/410) are pruned.
// Secrets: PUSH_HOOK_SECRET, VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY (+ the built-in SUPABASE_* vars).
import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import webpush from "npm:web-push@3.6.7";

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});
webpush.setVapidDetails(
  "mailto:support@maintrix.online",
  Deno.env.get("VAPID_PUBLIC_KEY")!,
  Deno.env.get("VAPID_PRIVATE_KEY")!,
);

// notification type → the toggle in Settings → Notifications (client's own mapping)
const PREF: Record<string, string> = {
  dm: "dms", tag: "mentions", reply: "replies",
  friend: "friends", friend_request: "friends",
  like: "likes", post_like: "likes", comment: "comments",
  debate_join: "debates", debate_end: "debates",
  ranked_match: "debates", ranked_turn: "debates", ranked_live: "debates", ranked_cancel: "debates",
  debate_live: "debate_live", badge: "badges", server_join: "servers", update: "updates",
  post_new: "posts_new", vc_start: "voice",
};

function prefOn(prefs: Record<string, unknown>, key: string) {
  return prefs[key] !== false;
}

const clip = (s: unknown, n: number) => String(s ?? "").slice(0, n);

function compose(type: string, who: string, e: Record<string, any>): { title: string; body: string } {
  const prev = clip(e.preview, 120);
  switch (type) {
    case "dm":
      if (e.group) return { title: clip(e.title || "Group", 60), body: `${who}: ${prev || (e.media_kind ? "sent an attachment" : "new message")}` };
      return { title: who, body: prev || (e.media_kind === "audio" ? "Sent you a voice note" : e.media_kind ? "Sent you an attachment" : "Sent you a message") };
    case "tag": return { title: `${who} mentioned you`, body: prev };
    case "reply": return { title: `${who} replied`, body: prev };
    case "friend_request": return { title: "Friend request", body: `${who} wants to be friends` };
    case "friend": return { title: "New friend", body: `${who} accepted your friend request` };
    case "like": return { title: "New like", body: `${who} liked you` };
    case "post_like": return { title: "New like", body: `${who} liked your post${prev ? `: ${prev}` : ""}` };
    case "comment": return { title: `${who} commented`, body: prev };
    case "debate_join": return { title: "Debate starting", body: `${who} joined “${clip(e.title, 80)}”` };
    case "debate_end": return { title: "Debate ended", body: `Results are in for “${clip(e.title, 80)}”` };
    case "debate_live": return { title: e.ranked ? "Ranked debate live" : "Debate live", body: `${clip(e.title, 80)} — ${clip(e.a, 40)} vs ${clip(e.b, 40)}` };
    case "ranked_match": return { title: "Ranked match found", body: `You're matched with ${who}` };
    case "ranked_turn": return { title: "Ranked", body: `${who} is waiting on you` };
    case "ranked_live": return { title: "Ranked debate live", body: clip(e.title, 100) || "Your match is starting" };
    case "ranked_cancel": return { title: "Ranked", body: "Your match was cancelled" };
    case "badge": return { title: "New badge", body: `You earned ${clip(e.label || e.title, 60)}` };
    case "server_join": return { title: clip(e.title || "Your server", 60), body: `${who} joined` };
    case "update": return { title: "Maintrix update", body: clip(e.summary || e.title || "Something new is here", 120) };
    case "post_new": return { title: `${who} posted`, body: prev || "New post in the feed" };
    case "vc_start": return { title: "Voice chat in the Nexus", body: `${who} joined the voice chat — hop in` };
    case "everyone": return { title: `${who} pinged @everyone`, body: prev };
    default: return { title: "Maintrix", body: clip(e.text || e.preview || "You have a new notification", 140) };
  }
}

function link(type: string, e: Record<string, any>) {
  if (type.startsWith("ranked_")) return "./?ranked=1";
  if (type === "update") return "./?updates=1";
  if (e.debate_id) return `./?debate=${e.debate_id}`;
  if (e.post_id) return `./?post=${e.post_id}`;
  if (e.room_id) return `./?room=${e.room_id}`;
  return "./?notifs=1";
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("method", { status: 405 });
  if (req.headers.get("x-push-secret") !== Deno.env.get("PUSH_HOOK_SECRET")) return new Response("forbidden", { status: 403 });

  let id = "";
  try { id = String((await req.json()).id || ""); } catch { /* ignore */ }
  if (!/^[0-9a-f-]{36}$/i.test(id)) return new Response("bad id", { status: 400 });

  const { data: n } = await db.from("notifications").select("id,user_id,type,actor_id,entity").eq("id", id).maybeSingle();
  if (!n) return new Response("gone", { status: 200 });

  const [{ data: me }, { data: actor }, { data: subs }] = await Promise.all([
    db.from("profiles").select("notif_prefs").eq("id", n.user_id).maybeSingle(),
    n.actor_id ? db.from("profiles").select("name,handle").eq("id", n.actor_id).maybeSingle() : Promise.resolve({ data: null }),
    db.from("push_subscriptions").select("id,endpoint,p256dh,auth").eq("user_id", n.user_id),
  ]);
  const prefs = Object.assign({ push: true }, (me?.notif_prefs as Record<string, unknown>) || {});
  if (prefs.push === false) return new Response("push off", { status: 200 });
  const key = PREF[n.type];
  if (key && !prefOn(prefs, key)) return new Response("muted", { status: 200 });
  if (!subs?.length) return new Response("no subs", { status: 200 });

  const who = clip((actor as any)?.name || ((actor as any)?.handle ? "@" + (actor as any).handle : "Someone"), 40);
  const e = (n.entity as Record<string, any>) || {};
  const { title, body } = compose(n.type, who, e);
  const tag = n.type === "dm" && e.room_id ? `dm-${e.room_id}` : `${n.type}-${n.id}`;
  const payload = JSON.stringify({ title, body, tag, url: link(n.type, e), type: n.type });

  const dead: string[] = [];
  await Promise.all(subs.map(async (s) => {
    try {
      await webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, payload, { TTL: 3600, urgency: "high" });
    } catch (err) {
      const code = (err as { statusCode?: number }).statusCode;
      if (code === 404 || code === 410 || code === 403) dead.push(s.id);
    }
  }));
  if (dead.length) await db.from("push_subscriptions").delete().in("id", dead);
  return new Response(JSON.stringify({ sent: subs.length - dead.length, pruned: dead.length }), {
    headers: { "Content-Type": "application/json" },
  });
});
