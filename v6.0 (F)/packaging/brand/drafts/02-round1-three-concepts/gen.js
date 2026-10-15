// Generates ledger-grid geometry (points) for each concept. node gen.js > geom.json
const H = 110;
const F = {
  serif: { name: 'Source Serif 4', cap: 66.4, t: 0.0708, // hairline in H
    inkL: { L: 3.9, D: 3.9, G: 4.1, R: 3.9 }, inkW: { L: 51.7, D: 62.8, G: 62.3, R: 61.7 }, stem: 8.3, cell: 1.0 },
  piazzolla: { name: 'Piazzolla', cap: 65.2, t: 0.0613,
    inkL: { L: 2.9, D: 2.9, G: 4.7, R: 2.9 }, inkW: { L: 53.2, D: 65.9, G: 63.1, R: 67.1 }, stem: 10.5, cell: 1.125 },
};
const f2 = v => +v.toFixed(2);
function rect(x1, x2, yc, w) { return `M${f2(x1)} ${f2(yc - w / 2)}H${f2(x2)}V${f2(yc + w / 2)}H${f2(x1)}Z`; }
function rectV(x, y1, y2, w) { return `M${f2(x - w / 2)} ${f2(y1)}H${f2(x + w / 2)}V${f2(y2)}H${f2(x - w / 2)}Z`; }

function build(concept, key, opts) {
  const f = F[key], k = H / f.cap, p = H / 2, t = f.t * H, tb = opts.tb * t, g = opts.gap * H;
  const ext = 0.6 * H, step = 0.5 * H;
  const X0 = 136, oy = opts.oy, order = ['L', 'D', 'G', 'R'];
  const inkw = c => f.inkW[c] * k;
  const out = { hi: [], bd: [], red: [], total: [], letters: [] };
  let Xs = [], Xend;
  if (concept === 'C') {
    const cw = f.cell * H;
    order.forEach((c, i) => Xs.push(X0 + (i + 0.5) * cw - inkw(c) / 2));
    Xend = X0 + 4 * cw;
  } else {
    let x = X0; order.forEach(c => { Xs.push(x); x += inkw(c) + g; }); Xend = x - g;
  }
  const B0 = oy + 250;
  const stemX = i => Xs[i] + f.stem * k;
  const backdropRange = (kk, lo, hi) => [lo - ext + step * kk, hi + ext - step * kk];
  let lo = (concept === 'C') ? X0 : X0, hi = Xend;
  if (concept === 'A' || concept === 'C') {
    const B = B0;
    [B - H, B - H / 2, B].forEach(y => out.hi.push(rect(lo - ext, hi + ext, y, t)));
    const rows = [];
    for (let kk = 1; kk <= 2; kk++) { rows.push({ y: B - H - kk * p, k: kk, dir: -1 }); rows.push({ y: B + kk * p, k: kk, dir: 1 }); }
    rows.forEach(r => {
      const [a, b] = backdropRange(r.k, lo, hi);
      if (opts.total && r.dir === 1 && r.k === 1) return;
      out.bd.push(rect(a, b, r.y, tb));
    });
    if (opts.total) {
      const tw = opts.totalW * t, gp = 1.5 * tw, yc = B + p;
      const a = (concept === 'C') ? lo : lo, b = hi;
      out.total.push(rect(a, b, yc - (gp + tw) / 2, tw)); out.total.push(rect(a, b, yc + (gp + tw) / 2, tw));
    }
    // columns
    let cols = [];
    if (concept === 'A') cols = [0, 1, 3].map(stemX);
    else { for (let j = 0; j <= 4; j++) cols.push(X0 + j * f.cell * H); }
    cols.forEach(x => {
      [-1, 1].forEach(dir => {
        let far = 0;
        for (let kk = 1; kk <= 2; kk++) { const [a, b] = backdropRange(kk, lo, hi); if (x >= a - 0.01 && x <= b + 0.01) far = kk; else break; }
        if (!far) return;
        const y1 = dir < 0 ? B - H : B, y2 = dir < 0 ? B - H - far * p : B + far * p;
        out.bd.push(rectV(x, Math.min(y1, y2), Math.max(y1, y2), tb));
      });
    });
    out.top = B - H - 2 * p - tb / 2; out.bottom = B + 2 * p + tb / 2;
    Xs.forEach((x, i) => { const c = order[i]; out.letters.push({ c, x: f2(x - k * f.inkL[c]), y: B, size: f2(100 * k) }); });
  } else { // B cascade
    const rowsAll = []; for (let n = -4; n <= 5; n++) rowsAll.push(n);
    const y = n => B0 + n * p;
    const inner = n => n >= -2 && n <= 3;
    rowsAll.forEach(n => {
      const kk = inner(n) ? 0 : (n < -2 ? -2 - n : n - 3);
      const a = lo - ext + step * kk, b = hi + ext - step * kk;
      out.bd.push(rect(a, b, y(n), tb));
    });
    Xs.forEach((x, i) => {
      const c = order[i], a = (i === 0 ? x - g / 2 : x - g / 2), b = x + inkw(c) + g / 2;
      [i - 2, i - 1, i].forEach(n => out.hi.push(rect(a, b, y(n), t)));
      out.letters.push({ c, x: f2(x - k * f.inkL[c]), y: y(i), size: f2(100 * k) });
    });
    // columns
    [0, 1, 3].forEach(i => {
      const x = stemX(i);
      const cov = n => { if (inner(n)) return true; const kk = n < -2 ? -2 - n : n - 3; const a = lo - ext + step * kk, b = hi + ext - step * kk; return x >= a && x <= b; };
      let top = i - 2; while (top - 1 >= -4 && cov(top - 1)) top--;
      let bot = i; while (bot + 1 <= 5 && cov(bot + 1)) bot++;
      if (top < i - 2) out.bd.push(rectV(x, y(top), y(i - 2), tb));
      if (bot > i) out.bd.push(rectV(x, y(i), y(bot), tb));
    });
    out.top = y(-4) - tb / 2; out.bottom = y(5) + tb / 2;
  }
  // margin: red double rule
  if (opts.margin) {
    const w = 0.6 * t, gp = 1.5 * w, xm = X0 - 0.5 * H;
    out.red.push(rectV(xm - (gp + w) / 2, out.top, out.bottom, w)); out.red.push(rectV(xm + (gp + w) / 2, out.top, out.bottom, w));
  }
  out.left = Math.min(lo - ext, opts.margin ? X0 - 0.5 * H - 2 * t : 1e9);
  out.right = hi + ext;
  out.t = f2(t); out.tb = f2(tb); out.k = k;
  return out;
}

const cfg = {
  A: { gap: 0.1, tb: 0.5, total: true, totalW: 0.7, margin: true },
  B: { gap: 0.1, tb: 0.5, total: false, margin: true },
  C: { gap: 0.1, tb: 0.5, total: true, totalW: 0.7, margin: false },
};
const res = {};
for (const key of ['serif', 'piazzolla']) for (const c of ['A', 'B', 'C']) {
  const idx = ["A","B","C"].indexOf(c)*2 + (key==="piazzolla"?1:0); const o = build(c, key, Object.assign({oy: 700*idx}, cfg[c]));
  res[c + '-' + key] = { hi: o.hi.join(''), bd: o.bd.join(''), red: o.red.join(''), total: o.total.join(''), letters: o.letters, top: f2(o.top), bottom: f2(o.bottom), left: f2(o.left), right: f2(o.right), t: o.t, tb: o.tb };
}
console.log(JSON.stringify(res, null, 1));
