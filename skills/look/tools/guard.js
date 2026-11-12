// guard.js — the network guard for a look session. look.sh copies this file
// into the session directory as guard.gen.js with the GUARD_CONFIG placeholder
// below replaced by JSON, then runs it once with
// `playwright-cli run-code --filename=guard.gen.js`, after `open about:blank`
// and before the first real navigation. It is one expression, a function of
// the page, so nothing may follow it but comments.
//
// Config: {allowPost: [glob], denyGetWords: [word], disposableHost: host|null}
//
// One route on the browser context sees every request of every page and
// popup in the session, including dedicated workers, and decides it:
//
//   1. GET, HEAD and OPTIONS pass, unless a deny word is in the URL.
//   2. Any other method on the disposable host passes. The host is compared
//      as URL.hostname, exactly and case-insensitively, on any port:
//      127.0.0.1 is not 127.0.0.10 and not localhost. Writes are lifted only
//      there; every other host keeps the write block. Deny words still block
//      reads on the disposable host (a logout ends the run there too), but
//      not its writes: naming a host disposable says deleting there is fine.
//   3. A POST that matches an allowPost glob passes, unless a deny word is in
//      the URL: an allowlisted path with "delete" in it stays blocked, since
//      the allowlist says "this POST only reads" and the word says otherwise.
//   4. Everything else is aborted with 'blockedbyclient', so it shows in
//      `look.sh cli <s> requests --all` as [FAILED] net::ERR_BLOCKED_BY_CLIENT.
//      That list is the guard's log; nothing else is kept. Anything the guard
//      cannot parse, and any error while deciding, is blocked too.
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
// Known limits:
//   - WebSocket messages do not pass through routes; a page with an open
//     socket can still write over it. The handshake GET is decided like any
//     other GET.
//   - Service workers' own requests bypass context routes, so look.sh starts
//     every session with serviceWorkers: "block" (no registration succeeds).
//   - Redirects are not decided again: an allowed request that the server
//     redirects (307/308 keep the method) is followed by the network stack.
//     Like the deny words, this is a heuristic, not a proof of read-only.
//   - The route covers this browser context only. look.sh cli refuses what
//     would leave it: run-code (page.request bypasses routes), a second open,
//     and tab-new --isolated-context.
async page => {
  const config = /*GUARD_CONFIG*/;
  if (!Array.isArray(config.allowPost) || !Array.isArray(config.denyGetWords) ||
      !(config.disposableHost === null || typeof config.disposableHost === 'string'))
    throw new Error('look guard: bad config');

  const READS = new Set(['GET', 'HEAD', 'OPTIONS']);
  const words = new Set(config.denyGetWords.map(w => String(w).toLowerCase()));
  const disposable = config.disposableHost ? config.disposableHost.toLowerCase() : null;

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

  const passes = (method, href) => {
    const url = new URL(href);
    const m = method.toUpperCase();
    if (READS.has(m)) return !hasDenyWord(url);
    if (disposable !== null && url.hostname.toLowerCase() === disposable) return true;
    const bare = url.protocol + '//' + url.host + url.pathname;
    if (m === 'POST' && allowPost.some(re => re.test(bare))) return !hasDenyWord(url);
    return false;
  };

  await page.context().route('**/*', route => {
    let ok = false;
    try {
      const request = route.request();
      ok = passes(request.method(), request.url());
    } catch {
      ok = false;
    }
    return (ok ? route.continue() : route.abort('blockedbyclient')).catch(() => {});
  });
  // Assembled, so the code the CLI echoes back never contains the sentinel.
  return ['look', 'guard', 'on'].join('-');
}
