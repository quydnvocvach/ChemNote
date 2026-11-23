/* ChemNote Pro v3.0.0 — OTA Auto-Update & Offline-First Service Worker */
const CACHE_NAME = 'chemnote-pro-v3.0.0';
const CORE_ASSETS = [
  './',
  './chemnote_preview.html',
  './manifest.json',
  './icon.svg'
];
const OPTIONAL_CDN = [
  'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js',
  'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then(async (cache) => {
      await cache.addAll(CORE_ASSETS);
      for (const url of OPTIONAL_CDN) {
        try { await cache.add(url); } catch (_) {}
      }
    })
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('message', (event) => {
  if (event.data && event.data.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.hostname.includes('googleapis.com') || url.hostname.includes('accounts.google.com')) return;

  // Network-First for HTML/navigation so OTA updates apply immediately when online
  const isNav = req.mode === 'navigate' || url.pathname.endsWith('/') || url.pathname.endsWith('.html');
  if (isNav) {
    event.respondWith(
      fetch(req).then((res) => {
        if (res && res.status === 200) {
          const copy = res.clone();
          caches.open(CACHE_NAME).then((c) => c.put(req, copy)).catch(() => {});
        }
        return res;
      }).catch(() => caches.match(req).then((c) => c || caches.match('./chemnote_preview.html')))
    );
    return;
  }

  // Stale-While-Revalidate for local assets & PDF.js CDN
  event.respondWith(
    caches.match(req).then((cached) => {
      const netFetch = fetch(req).then((res) => {
        if (res && res.status === 200 && (url.origin === location.origin || url.hostname.includes('cdnjs.cloudflare.com'))) {
          const copy = res.clone();
          caches.open(CACHE_NAME).then((c) => c.put(req, copy)).catch(() => {});
        }
        return res;
      }).catch(() => cached);
      return cached || netFetch;
    })
  );
});
