// The build id and the precache manifest are stamped in by build.mjs — every build gets a fresh
// cache name automatically, and INTEGRITY maps each precached path (app, styles, worker,
// icons, self-hosted fonts) to the SHA-256 of the exact bytes that build emitted.
const CACHE = 'maintrix-c54be1a5';
const INTEGRITY = {"index.html":"b4eb4b6e374d29b6461d35fb00a1f4427f994de4780b67cac44ef894f66820bc","app.js?v=c54be1a5":"61f61a9a97d7e2e92f2fc4cbeee0c438b60f600c0aa2564bcdd6a3c19b518b35","app.css?v=c54be1a5":"5d509df6b89ea4ae0f53010f7929b6ea4df701626b71db2a9fa0f4ac87181857","pow-worker.js?v=c54be1a5":"fe630df7c3d02b0e3c709288973128cfa164fa8df111691f69e15565e834a59d","manifest.json":"ff1ab8ea73ad8da46381753655f73579b30a0c52caa811271a1e6eb27bc6c33b","apple-touch-icon.png":"166460cc9aab37863053c7bf1e8cde3c9c4699143ea8dc28437f417f20888b95","icon-192.png":"57ed7d909c3ff69eba9bb276c1bacec42a3ffaf169cca5c167acd4c325171c74","icon-512.png":"fd73d989f33949a7a7e4472806261d703717d3c3fdd1073e3c6b18fedd119980","fonts/Fraunces-latin-ext.woff2":"f18853f63a870ebef013e30e789d8d544f102e4acd94988e57c223d9c796ddf4","fonts/Fraunces-latin.woff2":"a2930b27d13a228bd9ab6a49269b5f800237892ad560cb9dd7fab01b1620f88e","fonts/Fraunces-vietnamese.woff2":"7234ed860a9cc83045413c4faee63c960a8f2d1917adcf728119307d56e0d783","fonts/HankenGrotesk-cyrillic-ext.woff2":"e9201eddf1d41d0b62253295d869ce3cf65768f7102b797f02c7f8c876b4a9d5","fonts/HankenGrotesk-latin-ext.woff2":"992b5d147edde9d637ce22e7bb9cc9e6909c05410226b36a2e581ada9877eb4a","fonts/HankenGrotesk-latin.woff2":"768af2923e0ab1549f1dfba0a5c8ea749c4c01f01d8e77ffaf7fcd12f57a0a24","fonts/HankenGrotesk-vietnamese.woff2":"7ba47c78279dc529afe577dc2476bc8fd3c0e32f78efa26dca9f9382d49a157d","fonts/JetBrainsMono-cyrillic-ext.woff2":"cb182feeed4d798ff6961d3c79f7026279448fca0676438aaecb21f3fc39553a","fonts/JetBrainsMono-cyrillic.woff2":"d6c74dfddab488c40652ff116952624a88f8fa1de196732fd58b8e042a8967d2","fonts/JetBrainsMono-greek.woff2":"26c9ed511def1f0fd3d1b5fe6d5c0c594d9ef8dd2435d2ff240ea265a416b6e4","fonts/JetBrainsMono-latin-ext.woff2":"bb7b98e92899b511e8f3e99c924142f4421896b2cbc9406c3727c25427662cc9","fonts/JetBrainsMono-latin.woff2":"879df9319f1cbf633bee1dd489e376a9e1e8c458f4abddcfe381cb83b5e6b027","fonts/JetBrainsMono-vietnamese.woff2":"5b6dee4610cdaab7c4218c1692aa9a536414010eef4e5b3cfb25f45007811bcc"};
const ASSETS = Object.keys(INTEGRITY);

const hex = buf => Array.from(new Uint8Array(buf), b => b.toString(16).padStart(2, '0')).join('');
// Precache with verification: an asset is stored only if its bytes hash to what this build
// expects. A stale CDN copy, a proxy rewrite or a tampered response is simply not cached, so
// the offline fallback can never serve anything but this build's own files. (The page's own
// loads are covered by SRI in index.html; this closes the same gap for the SW cache.)
self.addEventListener('install', e => {
  e.waitUntil((async () => {
    const c = await caches.open(CACHE);
    await Promise.all(ASSETS.map(async a => {
      try {
        const r = await fetch(a, { cache: 'no-store' });
        if (!r.ok) return;
        const buf = await r.arrayBuffer();
        if (hex(await crypto.subtle.digest('SHA-256', buf)) !== INTEGRITY[a]) return;
        await c.put(a, new Response(buf, { status: 200, headers: r.headers }));
      } catch (_) {}
    }));
  })());
  self.skipWaiting();
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(keys =>
    Promise.all(keys.filter(k => k.startsWith('maintrix-') && k !== CACHE).map(k => caches.delete(k)))));
  self.clients.claim();
});
// cache:'no-store' matters here — without it, "network first" can still be silently satisfied
// by the *browser's own* HTTP cache (not this service worker's cache) if the static host didn't
// send strict no-cache headers, so a real deploy could sit invisible behind a stale HTTP-cached
// copy even though this code always calls fetch(). Forcing no-store means every fetch this SW
// makes genuinely hits the network.
self.addEventListener('fetch', e => {
  // only this origin's GETs — API/storage/relay traffic goes straight to the network untouched
  if (e.request.method !== 'GET' || new URL(e.request.url).origin !== self.location.origin) return;
  // the site root also hosts other folders (the app store under store/, its apps under apps/) —
  // this worker leaves them to their own workers and the network
  { const p = new URL(e.request.url).pathname, sc = new URL(self.registration.scope).pathname; if (p.startsWith(sc + 'apps/') || p.startsWith(sc + 'store/')) return; }
  e.respondWith(fetch(e.request, { cache: 'no-store' }).catch(() => caches.match(e.request).then(hit => hit || (e.request.mode === 'navigate' ? caches.match('index.html') : undefined))));
});

// ── Web Push ──
// Every push MUST show a notification (Chrome and iOS both penalize silent
// pushes), even if the app is in the foreground — the in-app bell already
// dedupes there.
self.addEventListener('push', e => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch (_) { d = { title: 'Maintrix', body: e.data ? e.data.text() : '' }; }
  const title = d.title || 'Maintrix';
  const opts = {
    body: d.body || '',
    icon: 'icon-192.png',
    badge: 'icon-192.png',
    tag: d.tag || undefined,
    renotify: !!d.tag,
    data: { url: d.url || './', type: d.type || '' },
  };
  e.waitUntil(self.registration.showNotification(title, opts));
});

// Tap → focus an open Maintrix window and route it, else open one.
self.addEventListener('notificationclick', e => {
  e.notification.close();
  const rel = (e.notification.data && e.notification.data.url) || './';
  let target = new URL(rel, self.registration.scope).href;
  // never let a push payload steer the app to another origin
  if (new URL(target).origin !== self.location.origin) target = self.registration.scope;
  e.waitUntil((async () => {
    const wins = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const w of wins) {
      if (new URL(w.url).origin === self.location.origin) {
        try { await w.focus(); } catch (_) {}
        w.postMessage({ type: 'push-open', url: target });
        return;
      }
    }
    await self.clients.openWindow(target);
  })());
});

// Endpoint rotated by the browser — the page re-syncs on next open, and the
// old row is pruned server-side when it 404s. Nothing to do here but note it.
self.addEventListener('pushsubscriptionchange', () => {});
