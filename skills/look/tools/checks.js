// checks.js — measurable UI defects in the page's main-frame document, as an
// array of hits. look.sh copies it into the session directory and runs it with
// `playwright-cli run-code --filename=...`; it is one expression, a function
// of the page, so nothing may follow it but comments.
//
// Only the main frame's document is measured: iframes, shadow-DOM interiors
// and other tabs are not entered. Boxes are in document coordinates (viewport
// rectangle plus the scroll offset at the time of the run), rounded to whole
// pixels, so a hit far down the page has a large y. Each hit's selector is a
// path that resolves to exactly one element (verified here), which `shot
// --hit` uses to scroll the element into view.
//
// Hit: {check, selector, text, box: {x,y,w,h}, detail}. Checks: overflow,
// overlap, contrast, small-target, img-alt, img-broken. look.sh adds the
// console-error, request-failed and request-blocked kinds from the CLI.
// Elements with no size (a side of 1 px or less in both directions),
// display:none, visibility:hidden or opacity:0 are ignored everywhere.
async page => page.evaluate(() => {
  const hits = [];
  const all = Array.from(document.querySelectorAll('body, body *'));
  const SKIP_TAGS = new Set(['SCRIPT', 'STYLE', 'NOSCRIPT', 'TEMPLATE', 'HEAD', 'META', 'LINK', 'TITLE']);

  const round = n => Math.round(n);
  const docBox = r => ({x: round(r.left + scrollX), y: round(r.top + scrollY), w: round(r.width), h: round(r.height)});

  const selectorFor = el => {
    if (el.id) {
      const s = '#' + CSS.escape(el.id);
      if (document.querySelectorAll(s).length === 1) return s;
    }
    const parts = [];
    for (let n = el; n && n.nodeType === 1; n = n.parentElement) {
      if (n === document.documentElement) { parts.unshift('html'); break; }
      let i = 1;
      for (let s = n.previousElementSibling; s; s = s.previousElementSibling) if (s.tagName === n.tagName) i++;
      parts.unshift(n.tagName.toLowerCase() + ':nth-of-type(' + i + ')');
    }
    const sel = parts.join(' > ');
    return document.querySelectorAll(sel).length === 1 ? sel : '';
  };

  const visible = el => {
    if (SKIP_TAGS.has(el.tagName)) return false;
    const cs = getComputedStyle(el);
    if (cs.display === 'none' || cs.visibility === 'hidden' || cs.visibility === 'collapse' || +cs.opacity === 0) return false;
    const r = el.getBoundingClientRect();
    return r.width > 1 || r.height > 1;
  };
  // visible() for an element whose box may legitimately be empty (a broken img).
  const rendered = el => {
    const cs = getComputedStyle(el);
    return cs.display !== 'none' && cs.visibility !== 'hidden' && +cs.opacity !== 0;
  };

  const ownText = el => {
    let t = '';
    for (const n of el.childNodes) if (n.nodeType === 3) t += n.nodeValue;
    return t.replace(/\s+/g, ' ').trim();
  };
  const label = el => (ownText(el) || el.getAttribute('aria-label') || el.getAttribute('alt') || el.value || '').slice(0, 80);
  const add = (check, el, box, detail) => {
    hits.push({check, selector: selectorFor(el), text: label(el), box, detail});
  };

  // --- colour -------------------------------------------------------------
  // Computed colours come back as rgb()/rgba() for most inputs but as color(...)
  // for modern syntaxes; a 1x1 canvas turns anything the browser understands
  // into rgba. null means "could not tell", and the caller skips the element.
  const ctx = document.createElement('canvas').getContext('2d', {willReadFrequently: true});
  ctx.canvas.width = ctx.canvas.height = 1;
  const parseColor = s => {
    const m = /^rgba?\(\s*([\d.]+)[,\s]+([\d.]+)[,\s]+([\d.]+)(?:\s*[,/]\s*([\d.]+%?))?\s*\)$/.exec(s);
    if (m) {
      let a = m[4] === undefined ? 1 : m[4].endsWith('%') ? parseFloat(m[4]) / 100 : +m[4];
      return [+m[1], +m[2], +m[3], a];
    }
    try {
      ctx.clearRect(0, 0, 1, 1);
      ctx.fillStyle = '#000';
      ctx.fillStyle = s;
      ctx.fillRect(0, 0, 1, 1);
      const d = ctx.getImageData(0, 0, 1, 1).data;
      return [d[0], d[1], d[2], d[3] / 255];
    } catch (e) { return null; }
  };
  const over = (top, under) => { // top rgba over opaque under rgb
    const a = top[3];
    return [0, 1, 2].map(i => top[i] * a + under[i] * (1 - a));
  };
  const lum = c => {
    const f = v => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); };
    return 0.2126 * f(c[0]) + 0.7152 * f(c[1]) + 0.0722 * f(c[2]);
  };
  // The effective background: the element's own and its ancestors' background
  // colours, composited from the outermost down over white. A background-image
  // or gradient anywhere on the way means the real pixels are unknown; text
  // over one is not measured (guessing would give false hits), so null.
  const backdrop = el => {
    const layers = [];
    for (let n = el; n; n = n.parentElement) {
      const cs = getComputedStyle(n);
      if (cs.backgroundImage && cs.backgroundImage !== 'none') return null;
      const c = parseColor(cs.backgroundColor);
      if (!c) return null;
      if (c[3] > 0) layers.push(c);
      if (c[3] >= 1) break;
    }
    let bg = [255, 255, 255];
    for (let i = layers.length - 1; i >= 0; i--) bg = over(layers[i], bg);
    return bg;
  };
  const effectiveOpacity = el => {
    let o = 1;
    for (let n = el; n; n = n.parentElement) o *= +getComputedStyle(n).opacity;
    return o;
  };

  // --- per-element checks ---------------------------------------------------
  const textEls = new Set();
  for (const el of all) {
    if (el.tagName === 'IMG') {
      if (!rendered(el)) continue;
      const r = el.getBoundingClientRect();
      const hidden = el.getAttribute('aria-hidden') === 'true' || el.getAttribute('role') === 'presentation' || el.getAttribute('role') === 'none';
      if (!el.hasAttribute('alt') && !hidden && !el.getAttribute('aria-label') && !el.getAttribute('aria-labelledby') && !el.title) {
        add('img-alt', el, docBox(r), 'image has no alt attribute (alt="" marks a decorative one)');
      }
      // Vector images without intrinsic size report 0 wide though they drew.
      if (el.getAttribute('src') && el.complete && el.naturalWidth === 0 && !/\.svg(\?|#|$)|^data:image\/svg/i.test(el.getAttribute('src'))) {
        add('img-broken', el, docBox(r), 'image failed to load: ' + el.getAttribute('src').slice(0, 120));
      }
      continue;
    }
    if (!visible(el)) continue;
    const cs = getComputedStyle(el);
    const r = el.getBoundingClientRect();

    // overflow: clipped or ellipsized content wider than its box.
    if (el !== document.body && el !== document.documentElement && el.clientWidth > 0 &&
        el.scrollWidth > el.clientWidth + 1 &&
        (/^(hidden|clip)$/.test(cs.overflowX) || cs.textOverflow === 'ellipsis')) {
      add('overflow', el, docBox(r), 'content is ' + el.scrollWidth + ' px wide in a ' + el.clientWidth + ' px box, and is clipped');
    }

    const text = ownText(el);
    if (text) {
      textEls.add(el);
      // contrast
      if (!el.disabled) {
        const fg0 = parseColor(cs.color), bg = backdrop(el);
        if (fg0 && bg) {
          const fg = over([fg0[0], fg0[1], fg0[2], fg0[3] * effectiveOpacity(el)], bg);
          const l1 = lum(fg), l2 = lum(bg);
          const ratio = (Math.max(l1, l2) + 0.05) / (Math.min(l1, l2) + 0.05);
          const px = parseFloat(cs.fontSize), bold = (parseInt(cs.fontWeight, 10) || 400) >= 700;
          const large = px >= 24 || (px >= 18.66 && bold);
          const need = large ? 3 : 4.5;
          if (ratio < need) add('contrast', el, docBox(r), 'contrast ' + ratio.toFixed(2) + ':1, needs ' + need + ':1 (' + px + ' px' + (bold ? ' bold' : '') + ')');
        }
      }
    }

    // small-target
    if (el.matches('a, button, input, select, [role=button]') && !(el.tagName === 'INPUT' && el.type === 'hidden')) {
      // A link inside a sentence is exempt (WCAG 2.5.8 "inline"): inline, with
      // text of its parent around it.
      const inline = cs.display === 'inline' && el.parentElement && ownText(el.parentElement) !== '';
      if (!inline && (r.width < 24 || r.height < 24)) {
        add('small-target', el, docBox(r), 'target is ' + round(r.width) + 'x' + round(r.height) + ' px, under 24x24');
      }
    }
  }

  // --- overlap ----------------------------------------------------------------
  // Two visible, non-ancestor elements that either hold text of their own or are
  // interactive, whose boxes intersect by more than 4 px both ways. An inline
  // element wrapped over lines is compared box by box (getClientRects).
  const cand = [];
  for (const el of all) {
    if (!(textEls.has(el) || el.matches('a, button, input, select, [role=button]'))) continue;
    if (!visible(el)) continue;
    const rs = Array.from(el.getClientRects()).filter(r => r.width > 1 && r.height > 1);
    if (rs.length) cand.push({el, rs});
  }
  const seen = new Set();
  for (let i = 0; i < cand.length && i < 1500; i++) {
    for (let j = i + 1; j < cand.length && j < 1500; j++) {
      const a = cand[i], b = cand[j];
      if (a.el.contains(b.el) || b.el.contains(a.el)) continue;
      for (const ra of a.rs) {
        let found = null;
        for (const rb of b.rs) {
          const w = Math.min(ra.right, rb.right) - Math.max(ra.left, rb.left);
          const h = Math.min(ra.bottom, rb.bottom) - Math.max(ra.top, rb.top);
          if (w > 4 && h > 4) { found = {left: Math.max(ra.left, rb.left), top: Math.max(ra.top, rb.top), width: w, height: h}; break; }
        }
        if (found) {
          const key = i + ':' + j;
          if (!seen.has(key)) {
            seen.add(key);
            add('overlap', a.el, docBox(found), 'overlaps ' + selectorFor(b.el) + ' by ' + round(found.width) + 'x' + round(found.height) + ' px');
          }
          break;
        }
      }
    }
  }
  return hits;
})
