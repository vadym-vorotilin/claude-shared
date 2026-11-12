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
// An element is ignored everywhere when it has no size (a side of 1 px or
// less in both directions), or is display:none, visibility:hidden or fully
// transparent (its own opacity or the product over its ancestors), or sits in
// an ancestor that is 0 px along an axis it clips (a collapsed container).
// A hit may also carry `rel`: its box relative to its element's box, so a
// marked shot can find the box again after the page has scrolled.
// {check:"limit"} is a note, not a defect: a cap was reached (see overlap).
async page => page.evaluate(() => {
  const hits = [];
  const OVERLAP_CAP = 1500;
  const all = Array.from(document.querySelectorAll('body, body *'));
  const SKIP_TAGS = new Set(['SCRIPT', 'STYLE', 'NOSCRIPT', 'TEMPLATE', 'HEAD', 'META', 'LINK', 'TITLE']);
  const TARGET = 'a, button, input, select, [role=button]';

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

  // --- what is visible -------------------------------------------------------
  // Per element, cached: the product of opacity over it and its ancestors, and
  // whether it or an ancestor is 0 px along an axis it clips.
  const states = new Map();
  const stateOf = el => {
    if (!el) return {op: 1, clip: false};
    let st = states.get(el);
    if (st) return st;
    const p = stateOf(el.parentElement), cs = getComputedStyle(el);
    const zero = cs.display !== 'inline' && cs.display !== 'contents' &&
      ((cs.overflowY !== 'visible' && el.clientHeight === 0) || (cs.overflowX !== 'visible' && el.clientWidth === 0));
    st = {op: p.op * (+cs.opacity), clip: p.clip || zero};
    states.set(el, st);
    return st;
  };
  const shown = el => { // not hidden by display, visibility, opacity or a collapsed ancestor
    if (SKIP_TAGS.has(el.tagName)) return false;
    if (typeof el.checkVisibility === 'function' &&
        !el.checkVisibility({checkOpacity: true, checkVisibilityCSS: true, opacityProperty: true, visibilityProperty: true})) return false;
    const cs = getComputedStyle(el);
    if (cs.display === 'none' || cs.visibility === 'hidden' || cs.visibility === 'collapse') return false;
    return stateOf(el).op > 0 && !stateOf(el.parentElement).clip;
  };
  const visible = el => {
    if (!shown(el)) return false;
    const r = el.getBoundingClientRect();
    return r.width > 1 || r.height > 1;
  };

  // The parts of an element's boxes that are not cut off by an ancestor that
  // clips (overflow other than visible), in viewport coordinates. Content
  // scrolled out of a pane is not on screen, so it neither overlaps nor crowds
  // anything. An absolutely positioned element is clipped only by ancestors
  // from its containing block up; a fixed one by none (approximate: transforms
  // and the like also make containing blocks).
  const visibleRects = (el, raw, inclusive) => {
    let rs = (raw || Array.from(el.getClientRects())).filter(r => r.width > 1 && r.height > 1);
    let pos = getComputedStyle(el).position;
    for (let a = inclusive ? el : el.parentElement; a && rs.length; a = a.parentElement) {
      const cs = getComputedStyle(a);
      if (pos === 'fixed') break;
      // An ancestor with clip-path or an absolute clip rectangle hides what
      // it holds (the usual screen-reader-only text).
      if (cs.clipPath !== 'none' || (cs.clip !== 'auto' && cs.position === 'absolute')) return [];
      const clips = a !== document.documentElement && a !== document.body && (cs.overflowX !== 'visible' || cs.overflowY !== 'visible');
      if (pos !== 'absolute' || cs.position !== 'static') {
        if (pos === 'absolute') pos = 'relative'; // its containing block reached
        if (clips) {
          const b = a.getBoundingClientRect();
          const L = b.left + a.clientLeft, T = b.top + a.clientTop, R = L + a.clientWidth, B = T + a.clientHeight;
          rs = rs.map(r => ({left: Math.max(r.left, L), top: Math.max(r.top, T), right: Math.min(r.right, R), bottom: Math.min(r.bottom, B)}))
            .filter(r => r.right - r.left > 1 && r.bottom - r.top > 1)
            .map(r => ({left: r.left, top: r.top, right: r.right, bottom: r.bottom, width: r.right - r.left, height: r.bottom - r.top}));
        }
      }
      if (cs.position === 'fixed') break;
    }
    return rs;
  };
  // Whether a text node is drawn text: it holds a letter or digit, sits outside
  // any <svg> (an svg <title> is a tooltip, not text on the page), and some
  // part of it, over 1x1 px, survives the clipping of its ancestors. Text only
  // a screen reader gets (sr-only spans) is not drawn.
  const drawnTextNode = n => {
    if (!/[\p{L}\p{N}]/u.test(n.nodeValue)) return false;
    const p = n.parentElement;
    if (!p || p.closest('svg') || !shown(p)) return false;
    const range = document.createRange();
    range.selectNodeContents(n);
    return visibleRects(p, Array.from(range.getClientRects()), true).length > 0;
  };
  const holdsDrawnText = el => { // anywhere inside el
    const w = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
    for (let n = w.nextNode(); n; n = w.nextNode()) if (drawnTextNode(n)) return true;
    return false;
  };
  const hasOwnDrawnText = el => Array.from(el.childNodes).some(n => n.nodeType === 3 && drawnTextNode(n));

  // Whether something drawn crosses the bottom edge of el's padding box: a text
  // range's client rect or a child element's rect. scrollHeight alone also
  // counts empty space (the strip under an inline image's baseline), which is
  // not cropped content.
  const drawnPastBottom = (el, r) => {
    const edge = r.top + el.clientTop + el.clientHeight + 1;
    const range = document.createRange();
    for (const n of el.childNodes) {
      let rects = [];
      if (n.nodeType === 3 && n.nodeValue.trim()) { range.selectNodeContents(n); rects = Array.from(range.getClientRects()); }
      else if (n.nodeType === 1) rects = [n.getBoundingClientRect()];
      if (rects.some(q => (q.width > 0 || q.height > 0) && q.bottom > edge)) return true;
    }
    return false;
  };

  const ownText = el => {
    let t = '';
    for (const n of el.childNodes) if (n.nodeType === 3) t += n.nodeValue;
    return t.replace(/\s+/g, ' ').trim();
  };
  // What a text field shows (placeholders are not measured; passwords are masked).
  const FIELD_NO_TEXT = /^(password|hidden|checkbox|radio|range|color|file|image)$/;
  const isField = el => el.tagName === 'TEXTAREA' || (el.tagName === 'INPUT' && !FIELD_NO_TEXT.test(el.type));
  const textOf = el => isField(el) ? (el.value || '').replace(/\s+/g, ' ').trim() : ownText(el);
  const label = el => (textOf(el) || el.getAttribute('aria-label') || el.getAttribute('alt') || el.value || '').slice(0, 80);
  const add = (check, el, box, detail) => {
    const r = el.getBoundingClientRect();
    hits.push({check, selector: selectorFor(el), text: label(el), box, detail,
      rel: {x: box.x - round(r.left + scrollX), y: box.y - round(r.top + scrollY), w: box.w, h: box.h}});
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
      const a = m[4] === undefined ? 1 : m[4].endsWith('%') ? parseFloat(m[4]) / 100 : +m[4];
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
  // What shows through when no ancestor is opaque: the canvas. Chromium paints
  // it dark (#121212) when the root's used color-scheme is dark, else white.
  const canvas = (() => {
    // The root's own color-scheme, else the <meta name=color-scheme> (which the
    // computed value does not reflect: it reads "normal" then).
    let rs = getComputedStyle(document.documentElement).colorScheme || '';
    if (!rs || rs === 'normal') {
      const m = document.querySelector('meta[name="color-scheme"]');
      rs = m ? m.content : '';
    }
    const dark = /\bdark\b/.test(rs) && (!/\blight\b/.test(rs) || matchMedia('(prefers-color-scheme: dark)').matches);
    return dark ? [18, 18, 18] : [255, 255, 255];
  })();
  // The effective background: the element's own and its ancestors' background
  // colours, composited from the outermost down over the canvas. A
  // background-image or gradient anywhere on the way means the real pixels are
  // unknown; text over one is not measured (guessing would give false hits), so null.
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
    let bg = canvas;
    for (let i = layers.length - 1; i >= 0; i--) bg = over(layers[i], bg);
    return bg;
  };

  // --- per-element checks ---------------------------------------------------
  const textEls = new Set();
  const targets = []; // visible, enabled targets: {el, r, cs}
  for (const el of all) {
    if (el.tagName === 'IMG') {
      if (!shown(el)) continue;
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

    // overflow: content cropped by its box, sideways or down. Text fields scroll
    // their value instead of cropping it, so they are not measured.
    if (el !== document.body && el !== document.documentElement && !/^(INPUT|TEXTAREA|SELECT)$/.test(el.tagName)) {
      const clipX = /^(hidden|clip)$/.test(cs.overflowX), clipY = /^(hidden|clip)$/.test(cs.overflowY);
      const clamped = cs.webkitLineClamp && cs.webkitLineClamp !== 'none';
      if (el.clientWidth > 0 && el.scrollWidth > el.clientWidth + 1 && (clipX || cs.textOverflow === 'ellipsis')) {
        add('overflow', el, docBox(r), 'content is ' + el.scrollWidth + ' px wide in a ' + el.clientWidth + ' px box, and is clipped');
      } else if (el.clientHeight > 0 && el.scrollHeight > el.clientHeight + 1 && (clipY || clamped) && drawnPastBottom(el, r)) {
        add('overflow', el, docBox(r), 'content is ' + el.scrollHeight + ' px tall in a ' + el.clientHeight + ' px box, and is ' + (clamped ? 'cut by line-clamp' : 'clipped'));
      }
    }

    const text = textOf(el);
    if (text) {
      if (!isField(el)) textEls.add(el);
      // contrast
      if (!el.disabled) {
        const fg0 = parseColor(cs.color), bg = backdrop(el);
        if (fg0 && bg) {
          const fg = over([fg0[0], fg0[1], fg0[2], fg0[3] * stateOf(el).op], bg);
          const l1 = lum(fg), l2 = lum(bg);
          const ratio = (Math.max(l1, l2) + 0.05) / (Math.min(l1, l2) + 0.05);
          const px = parseFloat(cs.fontSize), bold = (parseInt(cs.fontWeight, 10) || 400) >= 700;
          const large = px >= 24 || (px >= 18.66 && bold);
          const need = large ? 3 : 4.5;
          if (ratio < need) add('contrast', el, docBox(r), 'contrast ' + ratio.toFixed(2) + ':1, needs ' + need + ':1 (' + px + ' px' + (bold ? ' bold' : '') + ')');
        }
      }
    }

    if (el.matches(TARGET) && !(el.tagName === 'INPUT' && el.type === 'hidden') && !el.disabled && visibleRects(el).length) targets.push({el, r, cs});
  }

  // --- small-target (WCAG 2.5.8) ----------------------------------------------
  // A target under 24x24 passes when
  //  - it is exempt (see exempt): inline with drawn text of its own or of its
  //    parent's, so its size is set by the line height of text (a link in a
  //    sentence, a nav link, a link alone in a paragraph); an icon-only inline
  //    link is not, even with sr-only text or an svg <title>, or
  //  - spacing: a 24 px circle centred on its box touches no other target and
  //    no other undersized target's circle. Touching by under half a pixel is
  //    not counted, so layout rounding cannot make a 24 px grid fire.
  // Exempt: inline, and holding drawn text or standing in drawn text of its
  // parent's own (a separator such as a dot is not text).
  const exempt = t => {
    if (t.exempt === undefined) {
      t.exempt = t.cs.display === 'inline' &&
        (holdsDrawnText(t.el) || (!!t.el.parentElement && hasOwnDrawnText(t.el.parentElement)));
    }
    return t.exempt;
  };
  const isSmall = t => t.r.width < 24 || t.r.height < 24;
  const small = targets.filter(isSmall);
  const centre = t => [t.r.left + t.r.width / 2, t.r.top + t.r.height / 2];
  for (const t of small) {
    if (exempt(t)) continue;
    const [cx, cy] = centre(t);
    let crowded = false;
    for (const o of targets) {
      if (o === t || o.el.contains(t.el) || t.el.contains(o.el)) continue;
      const dx = Math.max(o.r.left - cx, 0, cx - o.r.right), dy = Math.max(o.r.top - cy, 0, cy - o.r.bottom);
      if (Math.hypot(dx, dy) < 12 - 0.5) { crowded = true; break; }
      if (isSmall(o) && !exempt(o)) {
        const [ox, oy] = centre(o);
        if (Math.hypot(ox - cx, oy - cy) < 24 - 0.5) { crowded = true; break; }
      }
    }
    if (crowded) add('small-target', t.el, docBox(t.r), 'target is ' + round(t.r.width) + 'x' + round(t.r.height) + ' px, under 24x24, and another target is within 24 px');
  }

  // --- overlap ----------------------------------------------------------------
  // Two visible, non-ancestor elements that either hold text of their own or are
  // interactive, whose boxes intersect by more than 4 px both ways. A label and
  // the control it labels may overlap (a floating label). An inline element
  // wrapped over lines is compared box by box (getClientRects). Comparing is
  // quadratic, so only the first OVERLAP_CAP candidates in document order are
  // compared; beyond that a {check:"limit"} note says so.
  const cand = [];
  for (const el of all) {
    if (!(textEls.has(el) || el.matches(TARGET))) continue;
    if (!visible(el)) continue;
    const rs = visibleRects(el);
    if (rs.length) cand.push({el, rs});
  }
  const compared = cand.slice(0, OVERLAP_CAP);
  if (cand.length > OVERLAP_CAP) {
    hits.push({check: 'limit', selector: '', text: '', box: null,
      detail: 'overlap compared only the first ' + OVERLAP_CAP + ' of ' + cand.length + ' text or interactive elements'});
  }
  const labels = (a, b) => a.tagName === 'LABEL' && a.control === b;
  for (let i = 0; i < compared.length; i++) {
    for (let j = i + 1; j < compared.length; j++) {
      const a = compared[i], b = compared[j];
      if (a.el.contains(b.el) || b.el.contains(a.el) || labels(a.el, b.el) || labels(b.el, a.el)) continue;
      for (const ra of a.rs) {
        let found = null;
        for (const rb of b.rs) {
          const w = Math.min(ra.right, rb.right) - Math.max(ra.left, rb.left);
          const h = Math.min(ra.bottom, rb.bottom) - Math.max(ra.top, rb.top);
          if (w > 4 && h > 4) { found = {left: Math.max(ra.left, rb.left), top: Math.max(ra.top, rb.top), width: w, height: h}; break; }
        }
        if (found) {
          add('overlap', a.el, docBox(found), 'overlaps ' + selectorFor(b.el) + ' by ' + round(found.width) + 'x' + round(found.height) + ' px');
          break;
        }
      }
    }
  }
  return hits;
})
