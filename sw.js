var CACHE = 'splitmetro-v50';
var FILES = ['./', './index.html', './manifest.json', './guide-voices.js?v=3', './icon-180.png', './icon-192.png', './icon-512.png'];
self.addEventListener('install', function(e){
  e.waitUntil(caches.open(CACHE).then(function(c){ return c.addAll(FILES.map(function(f){ return new Request(f, {cache:'reload'}); })); }).then(function(){ return self.skipWaiting(); }));
});
self.addEventListener('activate', function(e){
  e.waitUntil(caches.keys().then(function(keys){
    return Promise.all(keys.filter(function(k){ return k!==CACHE; }).map(function(k){ return caches.delete(k); }));
  }).then(function(){ return self.clients.claim(); }));
});
self.addEventListener('fetch', function(e){
  e.respondWith(caches.match(e.request).then(function(r){ return r || fetch(e.request); }));
});
