// Naikkan VERSION setiap kali kamu mengubah file aplikasi, supaya cache lama dibuang.
const VERSION = 'jf-v3';
const CORE = [
  './', 'index.html', 'manifest.json',
  'supabase.js', 'sortable.min.js',
  'icon-192.png', 'icon-512.png', 'icon-maskable-512.png'
];

self.addEventListener('install', e => {
  // add() satu per satu: file yang belum ada (mis. ikon) tidak menggagalkan seluruh install
  e.waitUntil(caches.open(VERSION).then(c => Promise.all(CORE.map(u => c.add(u).catch(() => {})))));
  self.skipWaiting();
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== VERSION).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);

  // Font Google: cache-first (jarang berubah)
  if (url.hostname === 'fonts.googleapis.com' || url.hostname === 'fonts.gstatic.com') {
    e.respondWith(
      caches.match(req).then(hit => hit || fetch(req).then(r => {
        const cp = r.clone();
        caches.open(VERSION).then(c => c.put(req, cp));
        return r;
      }))
    );
    return;
  }

  // Selain itu hanya file se-origin (API Supabase tidak pernah di-cache)
  if (url.origin !== location.origin) return;

  // Kunci cache tanpa query string (mis. ?code=... setelah login OAuth)
  const key = url.origin + url.pathname;
  e.respondWith(
    fetch(req)
      .then(r => {
        if (r.ok && r.type === 'basic') {
          const cp = r.clone();
          caches.open(VERSION).then(c => c.put(key, cp));
        }
        return r;
      })
      .catch(() => caches.match(key, { ignoreSearch: true })
        .then(hit => hit || (req.mode === 'navigate' ? caches.match('./') : undefined)))
  );
});
