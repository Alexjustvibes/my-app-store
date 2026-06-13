const CACHE = 'wiki-v1';
// App shell + the notes index. Note bodies under ../../notes/ are fetched live
// (network, with cache fallback) so freshly synced notes always show.
const ASSETS = [
  'index.html', 'manifest.json', 'notes-index.json',
  'apple-touch-icon.png', 'icon-192.png', 'icon-512.png'
];

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
