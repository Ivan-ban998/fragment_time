// 6/25 PWA service worker (干净版)
// 目标: HTTPS 下注册成功, 离线 fallback + 缓存 app shell
// HTTP 下: 注册跳过 (浏览器安全策略, build_and_serve.sh 也会禁用)

const CACHE_NAME = 'fragment-time-v1';
const APP_SHELL = [
  '/',
  '/index.html',
  '/manifest.json',
  '/favicon.png',
  '/icons/Icon-192.png',
  '/icons/Icon-512.png',
];

// Install: 预缓存 app shell
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      // 静默失败: 个别资源 404 不影响 SW 注册
      return Promise.all(
        APP_SHELL.map((url) =>
          cache.add(url).catch((e) => console.warn('[SW] cache.add failed:', url, e))
        )
      );
    })
  );
  // 立即激活 (跳过 waiting)
  self.skipWaiting();
});

// Activate: 清旧缓存
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k))
      )
    )
  );
  // 立即接管页面
  self.clients.claim();
});

// Fetch: 网络优先, 失败 fallback 缓存
self.addEventListener('fetch', (event) => {
  // 只处理 GET
  if (event.request.method !== 'GET') return;
  // 跳过 chrome-extension / devtools 请求
  const url = new URL(event.request.url);
  if (!url.protocol.startsWith('http')) return;

  event.respondWith(
    fetch(event.request)
      .then((response) => {
        // 成功: 克隆响应存缓存
        if (response && response.status === 200) {
          const clone = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
        }
        return response;
      })
      .catch(() => {
        // 失败: 取缓存
        return caches.match(event.request).then((cached) => {
          if (cached) return cached;
          // 都没: fallback index.html (SPA)
          if (event.request.mode === 'navigate') {
            return caches.match('/index.html');
          }
        });
      })
  );
});
