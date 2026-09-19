const CACHE = 'maintrix-v50';
const ASSETS = ['index.html', 'manifest.json', 'apple-touch-icon.png', 'icon-192.png', 'icon-512.png'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(ASSETS)));
  self.skipWaiting();
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(keys =>
    Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))));
  self.clients.claim();
});
self.addEventListener('fetch', e => {
  e.respondWith(fetch(e.request).catch(() => caches.match(e.request)));
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
  const target = new URL(rel, self.registration.scope).href;
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
