// Maintrix Edge Function — delete-account
// Deploy with: supabase functions deploy delete-account
// Requires SUPABASE_SERVICE_ROLE_KEY as a function secret (never ship this key
// in the client). Deletes the caller's own auth.users row; `profiles` and every
// row that references it (messages, posts, friendships, ...) cascade via the
// `on delete cascade` foreign keys already in the migrations.
//
// The client calls this via `sb.functions.invoke('delete-account')` — see the
// "Delete account" row in index.html. It must run behind the caller's own JWT
// (the default when invoked from the client SDK) so `getUser()` below only
// ever resolves to the person making the request, never an arbitrary id.

import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';

serve(async (req) => {
  try {
    const authHeader = req.headers.get('Authorization') || '';
    const userClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } }
    );
    const { data: { user }, error: userErr } = await userClient.auth.getUser();
    if (userErr || !user) {
      return new Response(JSON.stringify({ error: 'not authenticated' }), { status: 401 });
    }

    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    );
    const { error: delErr } = await admin.auth.admin.deleteUser(user.id);
    if (delErr) {
      return new Response(JSON.stringify({ error: delErr.message }), { status: 500 });
    }
    return new Response(JSON.stringify({ ok: true }), { status: 200 });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500 });
  }
});
