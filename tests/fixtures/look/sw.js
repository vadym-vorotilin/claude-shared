// A service worker that does nothing. A guarded session must not register it:
// a service worker's own requests do not pass through the guard.
self.addEventListener('fetch', () => {});
