// delete-account — a signed-in user permanently deletes their OWN account.
// Removes their uploads ({uid}/… in the media and attachments buckets), then the auth user;
// every public table row cascades from profiles (on delete cascade / set null).
// Deploy with verify_jwt on. Only ever acts on the caller's own id.
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const URL_ = Deno.env.get("SUPABASE_URL")!;
const admin = createClient(URL_, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...cors, "Content-Type": "application/json" } });

async function wipeFolder(bucket: string, uid: string) {
  for (let i = 0; i < 50; i++) {
    const { data, error } = await admin.storage.from(bucket).list(uid, { limit: 1000 });
    if (error || !data?.length) return;
    const paths = data.map((f) => `${uid}/${f.name}`);
    const { error: rmErr } = await admin.storage.from(bucket).remove(paths);
    if (rmErr) return;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method" }, 405);

  const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  const { data: who, error } = await admin.auth.getUser(jwt);
  if (error || !who?.user) return json({ error: "not signed in" }, 401);
  const uid = who.user.id;

  await Promise.all([wipeFolder("media", uid), wipeFolder("attachments", uid)]);
  const { error: delErr } = await admin.auth.admin.deleteUser(uid);
  if (delErr) return json({ error: delErr.message }, 500);
  return json({ ok: true });
});
