// guard.js — the network guard for a look session. look.sh copies this file
// into the session directory as guard.gen.js with the GUARD_CONFIG placeholder
// below replaced by JSON, then runs it once with
// `playwright-cli run-code --filename=guard.gen.js`, after `open about:blank`
// and before the first real navigation. It is one expression, a function of
// the page, so nothing may follow it but comments.
//
// Config: {allowPost: [glob], denyGetWords: [word],
//          disposableHost: "HOST:PORT" | null, allowWebsocket: boolean}
//
// Where it sits. HTTP requests are intercepted in the browser process, through
// a browser-level CDP session with Fetch interception on every URL. That
// sees the requests of every page, popup, frame and tab, of dedicated and
// shared workers, and the ones a page sends as it goes away (sendBeacon and
// keepalive fetches in pagehide/unload, <a ping>). A page cannot reach this
// layer from its own JavaScript. There is deliberately NO Playwright page or
// context route: one sees a request first and, when its document goes away,
// releases the leave-time beacons without this layer seeing them (checked
// against 0.1.24 with Chromium: the beacons reached the server).
// WebSockets are not HTTP requests to Fetch, so a context routeWebSocket
// decides each connection.
//
// The rules, for each HTTP request:
//
//   1. GET, HEAD and OPTIONS pass, unless a deny word is in the URL.
//   2. Any other method on the disposable server passes. The server is one
//      host and one port, compared as URL.host: the host name canonical
//      (127.1 is 127.0.0.1) and case-insensitive, so 127.0.0.1 is not
//      127.0.0.10 and not localhost. HOST:PORT matches that port only, the
//      scheme's default port normalised (h:443 is https://h/), so a dev
//      server on :5173 does not lift writes to a tunnel on :8080. The port
//      is required: a bare HOST would be two servers, on 80 and 443, so a
//      config without one stops the guard and the open fails, as does any
//      value not in the form look.sh writes (a lower-case name or IPv4
//      address, or a bracketed IPv6 one, then :PORT).
//      Writes are lifted only there; every other server keeps the write
//      block. Deny words still block reads on the disposable server (a
//      logout ends the run there too), but not its writes: naming a server
//      disposable says deleting there is fine.
//   3. A POST that matches an allowPost glob passes, unless a deny word is in
//      the URL, or its path has an encoded slash or backslash (%2F, %5C),
//      which a glob's `*` would cross. An allowlisted path with "delete" in it
//      stays blocked: the allowlist says "this POST only reads" and the word
//      says otherwise.
//   4. Everything else fails with BlockedByClient. A blocked request a page
//      made shows in `look.sh cli <s> requests --all` as
//      [FAILED] net::ERR_BLOCKED_BY_CLIENT; one sent as its page went away,
//      or by a worker, may not be listed at all, but is not sent either.
//      Anything the guard cannot parse, and any error while deciding, is
//      blocked too.
//
// WebSockets: a connection opens only to the disposable server (the same
// host-and-port rule, ws: and wss: taking 80 and 443), or to any host
// when look.sh open was given --allow-websocket (WebSocket messages may
// write: nothing inspects them). Any other is closed by the guard before it
// reaches the server, with code 4000 and reason "blocked by the look guard".
//
// A deny word is in the URL when it equals, ignoring case, a whole path
// segment or a whole query parameter name or value. Segments are
// percent-decoded, and a ";..." suffix and one file extension are dropped
// first, so /logout, /LogOut/, /logout.php, /logout;jsessionid=X,
// ?action=delete and ?logout=1 all match; /delete-guide, /removed,
// ?q=deleted and ?deleted=1 do not.
//
// Globs: Playwright's URL glob dialect, implemented here (run-code exposes no
// matcher). `**` matches any characters, `/` included; `*` matches any
// characters but `/`; everything else is literal (no `?` wildcard, no {a,b}).
// A glob is matched against scheme://host[:port]/path, with the query and
// fragment removed, so `**/api/ds/query*` matches /api/ds/query?x=1 and a
// URL cannot match by carrying the path in its query string.
//
// Threat model: a careless agent and the app's own code, not a hostile page.
// Known limits:
//   - The WebSocket route works by replacing the page's WebSocket object, so
//     a hostile page could get a pristine one back, and a worker's own
//     WebSocket is not routed at all. HTTP interception has no such gap.
//   - Deny words and the allowlist are heuristics about what a URL does, not
//     a proof that it only reads; so is trusting a redirect chain.
//   - Service workers are blocked from registering (serviceWorkers: "block"
//     in the session's config), so none can answer for the network.
//   - Code that does not go through the browser (Playwright's page.request,
//     run-code) bypasses all of this: look.sh cli does not pass run-code on.
async page => {
  const config = /*GUARD_CONFIG*/;
  if (!Array.isArray(config.allowPost) || !Array.isArray(config.denyGetWords) ||
      !(config.disposableHost === null || typeof config.disposableHost === 'string') ||
      typeof config.allowWebsocket !== 'boolean')
    throw new Error('look guard: bad config');

  const READS = new Set(['GET', 'HEAD', 'OPTIONS']);
  const words = new Set(config.denyGetWords.map(w => String(w).toLowerCase()));
  // {hostname, port}, the port in decimal. Only the canonical form look.sh
  // writes is read: a lower-case name or IPv4 address that starts and ends
  // with a letter or digit, or a bracketed IPv6 one, and a port. Anything else (no port, userinfo, a path) is an error,
  // never what new URL would make of it: x@evil.test is evil.test. The value
  // must also be its own canonical form, so 127.1:80 or h:080 stop the guard
  // too: they mean look.sh's canonicalisation was skipped.
  const disposable = (() => {
    if (config.disposableHost === null) return null;
    const m = /^([a-z0-9](?:[a-z0-9.-]*[a-z0-9])?|\[[0-9a-f:.]+\]):([0-9]{1,5})$/.exec(config.disposableHost);
    if (!m) throw new Error('look guard: bad disposable host');
    const port = String(Number(m[2]));
    if (!(+port >= 1 && +port <= 65535)) throw new Error('look guard: bad disposable port');
    const hostname = new URL('http://' + m[1]).hostname;
    if (hostname + ':' + port !== config.disposableHost)
      throw new Error('look guard: bad disposable host, not canonical');
    return {hostname, port};
  })();
  const DEFAULT_PORT = {'http:': '80', 'https:': '443', 'ws:': '80', 'wss:': '443'};

  const globToRegExp = glob => {
    let re = '';
    for (let i = 0; i < glob.length; i++) {
      const c = glob[i];
      if (c === '*' && glob[i + 1] === '*') { re += '.*'; i++; }
      else if (c === '*') re += '[^/]*';
      else re += c.replace(/[\\^$.|?+()[\]{}]/g, '\\$&');
    }
    return new RegExp('^' + re + '$');
  };
  const allowPost = config.allowPost.map(g => globToRegExp(String(g)));

  const decode = s => { try { return decodeURIComponent(s); } catch { return s; } };
  const isWord = s => words.has(s.trim().toLowerCase());
  const hasDenyWord = url => {
    for (const raw of url.pathname.split('/')) {
      for (const seg of decode(raw).split('/')) {
        const bare = seg.split(';')[0];
        if (isWord(bare) || isWord(bare.replace(/\.[A-Za-z0-9]+$/, ''))) return true;
      }
    }
    for (const [name, value] of url.searchParams) if (isWord(name) || isWord(value)) return true;
    return false;
  };
  const onDisposable = url => {
    if (disposable === null || url.hostname !== disposable.hostname) return false;
    return (url.port || DEFAULT_PORT[url.protocol]) === disposable.port;
  };

  const passes = (method, href) => {
    const url = new URL(href);
    const m = method.toUpperCase();
    if (READS.has(m)) return !hasDenyWord(url);
    if (onDisposable(url)) return true;
    if (m !== 'POST' || /%2f|%5c/i.test(url.pathname)) return false;
    const bare = url.protocol + '//' + url.host + url.pathname;
    return allowPost.some(re => re.test(bare)) && !hasDenyWord(url);
  };
  const websocketPasses = href => config.allowWebsocket || onDisposable(new URL(href));

  const context = page.context();
  const browser = context.browser();
  if (!browser) throw new Error('look guard: no browser to attach to');
  const cdp = await browser.newBrowserCDPSession();
  cdp.on('Fetch.requestPaused', event => {
    let ok = false;
    try {
      ok = passes(event.request.method, event.request.url);
    } catch {
      ok = false;
    }
    const reply = ok
      ? cdp.send('Fetch.continueRequest', {requestId: event.requestId})
      : cdp.send('Fetch.failRequest', {requestId: event.requestId, errorReason: 'BlockedByClient'});
    reply.catch(() => {});
  });
  await cdp.send('Fetch.enable', {patterns: [{urlPattern: '*'}]});

  await context.routeWebSocket(/.*/, ws => {
    let ok = false;
    try {
      ok = websocketPasses(ws.url());
    } catch {
      ok = false;
    }
    if (ok) ws.connectToServer();
    else ws.close({code: 4000, reason: 'blocked by the look guard'});
  });

  // Assembled, so the code the CLI echoes back never contains the sentinel.
  return ['look', 'guard', 'on'].join('-');
}
