// Maintrix moved to the site root. This worker replaces the old one at apps/maintrix/,
// removes itself and reloads open pages so they follow the redirect to /.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', e => {
  e.waitUntil(self.registration.unregister()
    .then(() => self.clients.matchAll({ type: 'window' }))
    .then(cs => cs.forEach(c => { try { c.navigate(c.url); } catch (_) {} })));
});
