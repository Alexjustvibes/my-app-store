// The build id and the self-hosted font list are stamped in by build.mjs — every build gets a
// fresh cache name automatically, and the woff2 files are precached so fonts work offline.
const CACHE = 'maintrix-4edd798a';
const ASSETS = ['index.html', 'app.js?v=4edd798a', 'app.css?v=4edd798a', 'manifest.json', 'apple-touch-icon.png', 'icon-192.png', 'icon-512.png'].concat(["fonts/Fraunces-latin-ext.woff2","fonts/Fraunces-latin.woff2","fonts/Fraunces-vietnamese.woff2","fonts/HankenGrotesk-cyrillic-ext.woff2","fonts/HankenGrotesk-latin-ext.woff2","fonts/HankenGrotesk-latin.woff2","fonts/HankenGrotesk-vietnamese.woff2","fonts/JetBrainsMono-cyrillic-ext.woff2","fonts/JetBrainsMono-cyrillic.woff2","fonts/JetBrainsMono-greek.woff2","fonts/JetBrainsMono-latin-ext.woff2","fonts/JetBrainsMono-latin.woff2","fonts/JetBrainsMono-vietnamese.woff2"]);

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(ASSETS)));
  self.skipWaiting();
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(keys =>
    Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))));
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
  e.respondWith(fetch(e.request, { cache: 'no-store' }).catch(() => caches.match(e.request)));
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
