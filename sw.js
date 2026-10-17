/* Scale & Tell push worker: does not cache private user content or API responses. */
'use strict';
self.addEventListener('push', event => {
  let payload = {};
  try { payload = event.data ? event.data.json() : {}; }
  catch (_) { payload = { body: event.data ? event.data.text() : '' }; }
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) payload = {};
  const title = typeof payload.title === 'string' && payload.title.trim() ? payload.title.slice(0, 90) : 'Scale & Tell';
  const body = typeof payload.body === 'string' && payload.body.trim() ? payload.body.slice(0, 250) : 'Open your Care Schedule to review what is due.';
  event.waitUntil(self.registration.showNotification(title, {
    body, icon: './icons/icon-192.png', badge: './icons/icon-192.png',
    tag: 'scale-tell-care', renotify: false, data: { openCareSchedule: true }
  }));
});
self.addEventListener('notificationclick', event => {
  event.notification.close();
  const destination = new URL('./?care=1', self.registration.scope).href;
  event.waitUntil((async () => {
    const windows = await clients.matchAll({ type: 'window', includeUncontrolled: true });
    const existing = windows.find(c => c.url.startsWith(self.registration.scope));
    if (existing) {
      await existing.focus();
      existing.postMessage({ type: 'OPEN_CARE_SCHEDULE' });
    } else if (clients.openWindow) {
      await clients.openWindow(destination);
    }
  })());
});
