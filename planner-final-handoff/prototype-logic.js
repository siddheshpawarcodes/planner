const PX = 1.1, GAP = 6, TAU = Math.PI * 2;
const NEU = {
  dark: { bg:'#0F1012', s1:'#1A1B1E', s2:'#25272B', ln:'#2E3035', tx:'#F2F2EF', t2:'#A9ABB0', t3:'#80838A', veil:'rgba(15,16,18,.86)', scrim:'rgba(0,0,0,.52)' },
  light:{ bg:'#F4F3EF', s1:'#E8E7E2', s2:'#DCDAD3', ln:'#D3D1CA', tx:'#121212', t2:'#4D4D4A', t3:'#686863', veil:'rgba(244,243,239,.88)', scrim:'rgba(18,18,18,.30)' }
};
const CAT = {
  study:{ n:'Study', c:'#2450E6', ink:'#FFFFFF' }, build:{ n:'Build', c:'#00875A', ink:'#FFFFFF' }, body:{ n:'Body', c:'#D9331A', ink:'#FFFFFF' },
  people:{ n:'People', c:'#C92A76', ink:'#FFFFFF' }, self:{ n:'Self', c:'#F5B800', ink:'#1A1404' }, work:{ n:'Work', c:'#5A6B7D', ink:'#FFFFFF' }, rest:{ n:'Rest', c:'#8C6A40', ink:'#FFFFFF' }
};
const CATS = ['study', 'build', 'body', 'people', 'self', 'work', 'rest'];
const DAYN = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'], DAYL = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'], DAY1 = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
const dnum = d => d < 3 ? 28 + d : d - 2, dmon = d => d < 3 ? 'September' : 'October', dmons = d => d < 3 ? 'Sep' : 'Oct';
const dayLabel = d => `${DAYL[d % 7]} ${dnum(d)} ${dmon(d)}`;
const dayShort = d => `${DAYN[d % 7]} ${dnum(d)}`;
const when = (d, m) => `${DAYN[d % 7]} ${dnum(d)} ${dmons(d)}, ${fmt(m)}`;
const rgb = h => { const n = parseInt(h.slice(1), 16); return [n >> 16, (n >> 8) & 255, n & 255]; };
const hexA = (h, a) => { const c = rgb(h); return `rgba(${c[0]},${c[1]},${c[2]},${a})`; };
const mixHex = (a, b, t) => { const A = rgb(a), B = rgb(b); return '#' + A.map((v, i) => Math.round(v + (B[i] - v) * t).toString(16).padStart(2, '0')).join(''); };
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const ceil5 = m => Math.ceil(m / 5) * 5;
const fmt = m => { m = ((Math.floor(m) % 1440) + 1440) % 1440; return String(Math.floor(m / 60)).padStart(2, '0') + ':' + String(m % 60).padStart(2, '0'); };
const dur = m => { m = Math.max(0, Math.round(m)); const h = Math.floor(m / 60), r = m % 60; return h && r ? `${h}h ${r}m` : h ? `${h}h` : `${r}m`; };
const hrs = x => dur(x * 60);

const COMMITS = [
  { id:'dinner', title:'Dinner', cat:'rest', s:1140, e:1200, days:'all', on:true, label:'Every day, 19:00 → 20:00' },
  { id:'gym', title:'Gym', cat:'body', s:540, e:600, days:5, on:false, label:'Saturdays, 09:00 → 10:00' },
  { id:'call', title:'Family call', cat:'people', s:1080, e:1110, days:6, on:false, label:'Sundays, 18:00 → 18:30' }
];
const defRoutine = () => ({ wake:420, ws:480, we:1140, sleep:1440, noWork:false, commits:COMMITS.map(c => ({ ...c })) });

function baseItems(d, R) {
  const wk = d % 7 < 5 && !R.noWork;
  const out = [];
  const ready = wk ? R.ws : R.wake + 60;
  if (ready > R.wake) out.push({ id:'morn', k:'prot', title:'Getting ready', s:R.wake, e:ready });
  if (wk) out.push({ id:'work', k:'fixed', cat:'work', title:'Office', s:R.ws, e:R.we });
  R.commits.forEach(c => { if (!c.on) return; const ok = c.days === 'all' || (c.days === 'wk' && d % 7 < 5) || (c.days === 'we' && d % 7 >= 5) || c.days === d % 7; if (ok) out.push({ id:'c_' + c.id, k:'fixed', cat:c.cat, title:c.title, s:c.s, e:c.e }); });
  out.push({ id:'wind', k:'prot', title:'Wind-down', s:R.sleep - 30, e:R.sleep });
  out.sort((a, b) => a.s - b.s);
  const res = []; let end = R.wake;
  out.forEach(x => { const y = { ...x, s:Math.max(x.s, end), e:Math.min(x.e, R.sleep) }; if (y.e - y.s >= 10) { res.push(y); end = y.e; } });
  return [{ id:'wake', k:'marker', title:'Wake', s:R.wake, e:R.wake }, ...res, { id:'sleep', k:'marker', title:'Sleep', s:R.sleep, e:R.sleep }];
}
const live = t => !t.deleted && !t.skipped && t.s != null;
function buildDay(d, R, all) {
  const base = baseItems(d, R);
  const ts = all.filter(t => t.day === d && live(t)).slice().sort((a, b) => a.s - b.s);
  const brks = [];
  ts.forEach(t => { if (t.e - t.s < 120) return; const b = { id:'brk_' + t.id, k:'break', title:'Break', s:t.e, e:t.e + 15, parent:t.id };
    if (b.e <= R.sleep && !ts.some(o => o !== t && o.s < b.e && o.e > b.s) && !base.some(x => x.k === 'fixed' && x.s < b.e && x.e > b.s)) brks.push(b); });
  const cover = ts.concat(brks), items = [];
  base.forEach(x => {
    if (x.k !== 'prot') { items.push(x); return; }
    let pcs = [[x.s, x.e]];
    cover.forEach(t => { pcs = pcs.flatMap(([a, b]) => (t.e <= a || t.s >= b) ? [[a, b]] : [[a, Math.max(a, t.s)], [Math.min(b, t.e), b]].filter(([p, q]) => q - p >= 10)); });
    pcs.forEach(([a, b], i) => items.push({ ...x, id:x.id + (i ? '_' + i : ''), s:a, e:b }));
  });
  const busy = items.filter(x => x.k !== 'marker').concat(cover).map(x => [x.s, x.e]).sort((a, b) => a[0] - b[0]);
  const gaps = []; let c = R.wake;
  busy.forEach(([a, b]) => { if (a - c >= 10) gaps.push({ id:'gap' + c, k:'open', title:'Open', s:c, e:a }); c = Math.max(c, b); });
  if (R.sleep - c >= 10) gaps.push({ id:'gap' + c, k:'open', title:'Open', s:c, e:R.sleep });
  const rank = x => x.id === 'wake' ? -1 : x.id === 'sleep' ? 1 : 0;
  const seq = items.concat(ts.map(t => ({ ...t, k:'task', tid:t.id })), brks, gaps).sort((a, b) => a.s - b.s || rank(a) - rank(b));
  let y = 0;
  const laid = seq.map(it => { const dd = it.e - it.s; let h;
    if (it.k === 'marker') h = 30; else if (it.k === 'fixed') h = dd > 90 ? 58 : Math.max(36, dd * PX); else if (it.k === 'break') h = 22; else if (it.k === 'prot') h = Math.max(28, dd * PX); else if (it.k === 'task') h = Math.max(44, dd * PX); else h = Math.max(36, dd * PX);
    const o = { ...it, y, h }; y += h + GAP; return o; });
  return { seq:laid, base, ts, brks, gaps, height:y };
}
function capOf(d, R, all, t0) {
  const B = buildDay(d, R, all);
  const cl = x => Math.max(0, x.e - Math.max(x.s, t0));
  let avail = 0, brk = 0, planned = 0, done = 0; const segs = [];
  B.seq.forEach(x => { if (x.k === 'open' || x.k === 'task' || x.k === 'break' || x.k === 'prot') avail += cl(x); if (x.k === 'break') brk += cl(x); });
  const prot = B.base.filter(x => x.k === 'prot').reduce((a, x) => a + cl(x), 0);
  B.ts.forEach(t => { if (t.done) { done += t.e - t.s; return; } const m = cl(t); if (m > 0) { planned += m; segs.push({ cat:t.cat, m, id:t.id }); } });
  const buffer = Math.min(20, Math.max(0, avail - prot - brk));
  let real = Math.max(0, avail - prot - brk - buffer);
  if (d % 7 >= 5) real = Math.min(real, 360);
  return { avail, prot, brk, buffer, real, planned, done, segs, over:planned - real, B };
}
function busyOf(d, R, all, o) {
  const iv = [];
  baseItems(d, R).forEach(x => { if (x.k === 'fixed') iv.push([x.s, x.e]); if (x.k === 'prot' && !(o.allowWind && x.id === 'wind')) iv.push([x.s, x.e]); });
  all.forEach(t => { if (t.day !== d || !live(t) || t.id === o.excl) return; iv.push([t.s, t.e + (t.e - t.s >= 120 ? 15 : 0)]); });
  return iv;
}
function earliestFree(iv, from, dd, limit) {
  let x = from, moved = true, n = 0;
  while (moved && n++ < 60) { moved = false; for (const [a, b] of iv) if (a < x + dd && b > x) { x = b; moved = true; } }
  return x + dd <= limit ? x : null;
}
function findSlot(d, dd, R, all, o = {}) {
  const lo = Math.max(R.wake, o.after || 0);
  const pf = o.at != null ? o.at : o.pref === 'morning' ? 540 : o.pref === 'afternoon' ? 780 : o.pref === 'evening' ? 1080 : (d % 7 >= 5 ? 600 : 0);
  const tries = [Math.max(lo, pf), lo];
  for (const wind of o.allowWind ? [false, true] : [false]) {
    const iv = busyOf(d, R, all, { excl:o.excl, allowWind:wind });
    for (const f of tries) { const x = earliestFree(iv, ceil5(f), dd, R.sleep); if (x != null) return { s:x, e:x + dd, over:wind }; }
  }
  return null;
}
function ripple(all, id, day, s, R) {
  const t = all.find(x => x.id === id), dd = t.e - t.s;
  const baseIv = busyOf(day, R, [], {});
  let st = earliestFree(baseIv, s, dd, R.sleep + 180); if (st == null) st = s;
  const moved = { ...t, day, s:st, e:st + dd };
  const occ = baseIv.concat([[moved.s, moved.e + (dd >= 120 ? 15 : 0)]]);
  all.forEach(x => { if (x.id !== id && x.day === day && live(x) && x.done) occ.push([x.s, x.e]); });
  const upd = {};
  all.filter(x => x.id !== id && x.day === day && live(x) && !x.done).sort((a, b) => a.s - b.s).forEach(o => {
    const od = o.e - o.s; const ns = earliestFree(occ, o.s, od, 99999); upd[o.id] = { s:ns, e:ns + od }; occ.push([ns, ns + od + (od >= 120 ? 15 : 0)]); });
  return all.map(x => x.id === id ? moved : upd[x.id] ? { ...x, ...upd[x.id] } : x);
}
const mk = (id, title, cat, day, s, d, x) => ({ id, title, cat, day, s, e:s == null ? null : s + d, dur:d, done:false, skipped:false, deleted:false, prio:'normal', deadline:null, recur:null, src:'manual', ...(x || {}) });
const INBOX = () => [mk('i1', 'Read Laxmikanth ch. 4', 'study', null, null, 45), mk('i2', 'Call family', 'people', null, null, 30), mk('i3', 'Plan the week', 'self', null, null, 20)];
function guessCat(t) {
  t = (t || '').toLowerCase();
  if (/polity|study|upsc|revise|exam|history|laxmikanth|test/.test(t)) return 'study';
  if (/flutter|code|build|wmm|app|project|design/.test(t)) return 'build';
  if (/gym|exercise|run|yoga|walk|workout|swim/.test(t)) return 'body';
  if (/call|family|friend|mum|mom|dad|dinner with/.test(t)) return 'people';
  if (/read|journal|plan|meditat|write/.test(t)) return 'self';
  if (/office|meeting|report|email|work/.test(t)) return 'work';
  if (/rest|nap|break|relax/.test(t)) return 'rest';
  return 'self';
}
const CMDS = [
  { k:'multi', say:'Tomorrow I want to study polity for two hours, exercise for 45 minutes and learn Flutter for one hour.', key:['tomorrow', 'study', 'polity', 'two', 'hours', 'exercise', '45', 'minutes', 'learn', 'flutter', 'one', 'hour'] },
  { k:'add', say:'Add gym tomorrow for one hour.', key:['add', 'gym', 'tomorrow', 'one', 'hour'] },
  { k:'move', say:'Move gym to Saturday.', key:['move', 'gym', 'saturday'] },
  { k:'complete', say:'Mark gym complete.', key:['mark', 'gym', 'complete'] },
  { k:'del', say:'Delete my gym task.', key:['delete', 'gym'] },
  { k:'ask', say:'What do I have tomorrow?', key:['what', 'have', 'tomorrow'] },
  { k:'evening', say:'Plan my evening.', key:['plan', 'evening'] },
  { k:'resched', say:'Reschedule unfinished tasks.', key:['reschedule', 'unfinished'] },
  { k:'recur', say:'Add a recurring gym session every Monday.', key:['recurring', 'gym', 'every', 'monday'] }
];
const WMOCK = { study:[0, 0, 1.67, 1.5, 1.5, 2, 2], build:[0, 0, 0, 1, 0.5, 3, 1], body:[0, 0, 0, 0, 0, 0.75, 0.75], people:[0, 0, 0, 0, 0.5, 1, 0.5], self:[0, 0.25, 0.25, 0.5, 0.25, 0.25, 0.5], rest:[0, 1, 1, 1, 1, 1, 1], work:[0, 11, 11, 11, 11, 0, 0] };
const WENV = [0, 1.25, 4, 4.5, 4.25, 9.25, 6.75];
const HEATF = (r, c) => {
  const h = 6 + c / 2, wk = r < 5; let v = 0;
  const q = Math.abs((Math.sin((r + 1) * 12.9898 + (c + 1) * 78.233) * 43758.5453) % 1);
  if (h >= 7 && h < 8) v = wk ? 1.2 : 0.4;
  if (!wk && h >= 10 && h < 13) v = 2.2;
  if (!wk && h >= 14 && h < 17) v = r === 5 ? 3 : 1.4;
  if (h >= 20 && h < 20.5) v = 1.8;
  if (h >= 20.5 && h < 22.5) v = wk ? 3.4 : 2.4;
  if (h >= 22.5 && h < 23.5) v = wk ? 1.6 : 0.8;
  v += (q - 0.5) * 1.3;
  return v < 0.6 ? 0 : Math.max(0, Math.min(4, Math.round(v)));
};
const ICON = {
  plus:'M12 5v14M5 12h14', close:'M6 6l12 12M18 6L6 18', back:'M15 5l-7 7 7 7', chev:'M9 5l7 7-7 7',
  sliders:'M4 7h9M17 7h3M4 17h3M11 17h9', mic:'M12 15a3 3 0 0 0 3-3V6a3 3 0 0 0-6 0v6a3 3 0 0 0 3 3zM6 11a6 6 0 0 0 12 0M12 17v3',
  cloudoff:'M7.5 18h9.5a3.5 3.5 0 0 0 .6-6.95A5.5 5.5 0 0 0 7 9.7 4.2 4.2 0 0 0 7.5 18zM4 4l16 16', cloud:'M7.5 18h9.5a3.5 3.5 0 0 0 .6-6.95A5.5 5.5 0 0 0 7 9.7 4.2 4.2 0 0 0 7.5 18z'
};

function drawOrb(cv, p, t, opt) {
  if (!cv) return; const ctx = cv.getContext('2d'), S = cv.width; let c = S / 2; const cy = S / 2;
  ctx.clearRect(0, 0, S, S);
  const core = p.core || [236, 233, 226];
  const R = S * 0.2 * (1 + 0.06 * p.succ) * (1 - 0.08 * p.cancel);
  c += Math.sin(t * 38) * p.cancel * R * 0.09;
  const css = (k, a) => a == null ? `rgb(${k[0] | 0},${k[1] | 0},${k[2] | 0})` : `rgba(${k[0] | 0},${k[1] | 0},${k[2] | 0},${a})`;
  const mixc = (a, b, q) => a.map((v, i) => v + (b[i] - v) * q);
  const halo = Math.min(1, p.amp) * (1 - p.succ) * (1 - p.deny);
  if (halo > 0.03) { const g = ctx.createRadialGradient(c, cy, R * 0.9, c, cy, R * 2.2); g.addColorStop(0, css(core, 0.18 * halo)); g.addColorStop(1, css(core, 0)); ctx.fillStyle = g; ctx.fillRect(0, 0, S, S); }
  for (const rp of p.ripples) { const age = (t - rp.t0) / 1.7; if (age < 0 || age > 1) continue; ctx.strokeStyle = css(core, (1 - age) * (1 - age) * 0.6 * rp.s); ctx.lineWidth = S * (0.006 * (1 - age) + 0.0015); ctx.beginPath(); ctx.arc(c, cy, R * (1.06 + age * 1.2), 0, TAU); ctx.stroke(); }
  const M = 120, pts = [];
  for (let i = 0; i < M; i++) {
    const th = i / M * TAU;
    let d = p.amp * (0.11 * Math.sin(3 * th + t * 2.3) + 0.07 * Math.sin(5 * th - t * 3.2) + 0.04 * Math.sin(9 * th + t * 5.1))
      + 0.016 * Math.sin(2 * th + t * 0.9) * (0.35 + p.idle) + p.wob * 0.08 * Math.cos(2 * th)
      + p.proc * 0.03 * Math.pow(Math.max(0, Math.cos(th - t * 2.6)), 6) - p.pulse * 0.05;
    d *= (1 - p.succ * 0.85); const r = R * (1 + d); pts.push([c + r * Math.cos(th), cy + r * Math.sin(th)]);
  }
  const path = () => { ctx.beginPath(); for (let i = 0; i <= M; i++) { const a = pts[i % M], b = pts[(i + 1) % M]; const mx = (a[0] + b[0]) / 2, my = (a[1] + b[1]) / 2; if (i === 0) ctx.moveTo(mx, my); else ctx.quadraticCurveTo(a[0], a[1], mx, my); } ctx.closePath(); };
  ctx.save(); ctx.shadowColor = opt.light ? 'rgba(25,20,10,.30)' : 'rgba(0,0,0,.65)'; ctx.shadowBlur = S * 0.06; ctx.shadowOffsetY = S * 0.025;
  const g = ctx.createRadialGradient(c - R * 0.35, cy - R * 0.42, R * 0.04, c, cy, R * 1.15);
  g.addColorStop(0, '#3d3f44'); g.addColorStop(0.5, '#18191c'); g.addColorStop(1, '#050506'); path(); ctx.fillStyle = g; ctx.fill(); ctx.restore();
  ctx.save(); path(); ctx.clip();
  const lit = 1 - 0.7 * p.deny - 0.5 * p.cancel;
  const spill = ctx.createRadialGradient(c, cy + R * 0.2, 0, c, cy + R * 0.2, R * 1.15); spill.addColorStop(0, css(core, 0.34 * lit)); spill.addColorStop(1, css(core, 0)); ctx.fillStyle = spill; ctx.fillRect(0, 0, S, S);
  const breath = 0.5 + 0.5 * Math.sin(t * 1.5);
  let cr = R * (0.24 + 0.04 * breath * p.idle + p.amp * 0.2) * (1 - 0.5 * p.proc) * (1 - 0.3 * p.cancel); cr += (R * 0.95 - cr) * p.succ;
  const corePath = () => { ctx.beginPath(); for (let i = 0; i <= 64; i++) { const th = i / 64 * TAU; const dd = 1 + p.amp * (0.16 * Math.sin(2 * th - t * 3) + 0.09 * Math.sin(4 * th + t * 4.2)) * (1 - p.succ); const x = c + cr * dd * Math.cos(th), y = cy + cr * dd * Math.sin(th); i ? ctx.lineTo(x, y) : ctx.moveTo(x, y); } ctx.closePath(); };
  ctx.save();
  if (p.deny > 0.5) { corePath(); ctx.strokeStyle = css(mixc(core, [120, 122, 128], 0.5), 0.9); ctx.lineWidth = S * 0.012; ctx.stroke(); ctx.beginPath(); ctx.moveTo(c - cr * 0.8, cy + cr * 0.8); ctx.lineTo(c + cr * 0.8, cy - cr * 0.8); ctx.stroke(); }
  else {
    ctx.shadowColor = css(core, 0.95 * lit); ctx.shadowBlur = R * 0.55 * lit;
    const cg = ctx.createRadialGradient(c - cr * 0.3, cy - cr * 0.35, 0, c, cy, cr * 1.15);
    cg.addColorStop(0, css(mixc(core, [255, 255, 255], 0.5))); cg.addColorStop(0.45, css(core)); cg.addColorStop(1, css(mixc(core, [0, 0, 0], 0.22)));
    ctx.globalAlpha = 0.35 + 0.65 * lit; ctx.fillStyle = cg; corePath(); ctx.fill(); ctx.globalAlpha = 1;
  }
  if (p.proc > 0.02) for (let k = 0; k < 3; k++) { const a = t * 2.8 + k * TAU / 3, rr = R * 0.46; ctx.beginPath(); ctx.arc(c + Math.cos(a) * rr, cy + Math.sin(a) * rr, R * 0.085 * p.proc, 0, TAU); ctx.fillStyle = css(mixc(core, [255, 255, 255], 0.2), p.proc); ctx.fill(); }
  ctx.restore();
  const fr = ctx.createRadialGradient(c, cy, R * 0.72, c, cy, R * 1.1); fr.addColorStop(0, 'rgba(255,255,255,0)'); fr.addColorStop(1, 'rgba(255,255,255,0.14)'); ctx.fillStyle = fr; ctx.fillRect(0, 0, S, S);
  ctx.save(); ctx.translate(c - R * 0.34 + p.wob * R * 0.05, cy - R * 0.5); ctx.rotate(-0.5); ctx.scale(1, 0.55);
  const sg = ctx.createRadialGradient(0, 0, 0, 0, 0, R * 0.44); sg.addColorStop(0, 'rgba(255,255,255,0.55)'); sg.addColorStop(0.45, 'rgba(255,255,255,0.12)'); sg.addColorStop(1, 'rgba(255,255,255,0)');
  ctx.fillStyle = sg; ctx.beginPath(); ctx.arc(0, 0, R * 0.44, 0, TAU); ctx.fill(); ctx.restore(); ctx.restore();
  const rg = ctx.createLinearGradient(c - R, cy - R, c + R, cy + R); rg.addColorStop(0, 'rgba(255,255,255,.4)'); rg.addColorStop(0.5, 'rgba(255,255,255,.05)'); rg.addColorStop(1, 'rgba(255,255,255,.16)');
  path(); ctx.strokeStyle = rg; ctx.lineWidth = S * 0.003; ctx.stroke();
  if (p.succ > 0.35) {
    const q = Math.min(1, (p.succ - 0.35) / 0.55); const P = [[-0.26, 0.01], [-0.07, 0.19], [0.27, -0.17]].map(([x, y]) => [c + x * R, cy + y * R]);
    const l1 = Math.hypot(P[1][0] - P[0][0], P[1][1] - P[0][1]), l2 = Math.hypot(P[2][0] - P[1][0], P[2][1] - P[1][1]); let L = q * (l1 + l2);
    ctx.beginPath(); ctx.moveTo(P[0][0], P[0][1]);
    if (L <= l1) ctx.lineTo(P[0][0] + (P[1][0] - P[0][0]) * L / l1, P[0][1] + (P[1][1] - P[0][1]) * L / l1); else { ctx.lineTo(P[1][0], P[1][1]); L -= l1; ctx.lineTo(P[1][0] + (P[2][0] - P[1][0]) * L / l2, P[1][1] + (P[2][1] - P[1][1]) * L / l2); }
    const lum = (0.299 * core[0] + 0.587 * core[1] + 0.114 * core[2]) / 255;
    ctx.strokeStyle = lum > 0.62 ? '#1a1404' : '#ffffff'; ctx.lineWidth = S * 0.022; ctx.lineCap = 'round'; ctx.lineJoin = 'round'; ctx.stroke();
  }
}
const smoothPath = (pts) => { let d = `M${pts[0][0].toFixed(1)} ${pts[0][1].toFixed(1)}`; for (let i = 1; i < pts.length; i++) { const [x0, y0] = pts[i - 1], [x1, y1] = pts[i], mx = (x1 - x0) / 2; d += ` C${(x0 + mx).toFixed(1)} ${y0.toFixed(1)} ${(x1 - mx).toFixed(1)} ${y1.toFixed(1)} ${x1.toFixed(1)} ${y1.toFixed(1)}`; } return d; };
function arcD(cx, cy, r, m0, m1) {
  const pt = m => { const a = m / 1440 * TAU - Math.PI / 2; return [cx + r * Math.cos(a), cy + r * Math.sin(a)]; };
  const [x0, y0] = pt(m0), [x1, y1] = pt(m1);
  return `M${x0.toFixed(2)} ${y0.toFixed(2)} A${r} ${r} 0 ${(m1 - m0) > 720 ? 1 : 0} 1 ${x1.toFixed(2)} ${y1.toFixed(2)}`;
}

class Component extends DCLogic {
  phoneRef = React.createRef(); tlRef = React.createRef(); orbRef = React.createRef(); boardRef = React.createRef(); planRef = React.createRef();
  p = { amp:0, idle:1, proc:0, succ:0, wob:0, wobV:0, pulse:0, cancel:0, deny:0, ripples:[] };
  timers = []; lastTop = {};
  state = this.snap('onboard');

  base() {
    return { screen:'app', ob:{ step:0, wake:420, ws:480, we:1140, sleep:1440, noWork:false, commits:COMMITS.map(c => ({ ...c })), cu:null }, obN:0, obOut:false, appIn:true,
      routine:defRoutine(), day:1, now:1180, tab:'today', tday:0, dayPhase:'in', view:'strip', dialIn:true,
      planSeg:'week', weekSel:1, tasks:[], deadlines:[], upcoming:[], series:[],
      sweeping:{}, leaving:{}, hold:{}, fresh:{}, place:{}, scanning:false, winLit:false, winIds:[],
      note:null, voice:'idle', cmd:'multi', wordN:0, parsed:false, showRes:false, resN:0, res:null,
      overAck:{}, capOpen:false, missDismiss:{},
      sheet:null, sheetOpen:false, sid:null, f:null, delArm:false, pickDate:false, pickFor:null,
      pk:0, heatOn:false, ribOn:false, ribSel:null, ribAll:false, weekComplete:false, heatSel:null,
      review:false, rStage:0, rOn:false,
      settings:false, sPage:'root', drive:'off', driveProg:0, lastBackup:null, autoBackup:true, online:true, restoreAsk:false,
      notif:{ next:true, missed:true, review:true }, wakeOn:true, statSkip:false, dialDefault:false,
      themeLocal:null, rmLocal:null, micOK:true, mic:false, micErr:false, speed:1,
      drag:null, recalc:null, navBump:0, active:'tue', obVoice:false };
  }
  snap(k) {
    const b = this.base(), I = INBOX();
    if (k === 'onboard') return { ...b, screen:'onboarding', appIn:false, tasks:I, active:'onboard' };
    if (k === 'tue' || k === 'voice') return { ...b, tasks:I, active:k };
    const pol = mk('t1', 'Study polity', 'study', 2, 1200, 120, { src:'voice' });
    const ex = mk('t2', 'Exercise', 'body', 2, 1335, 45, { src:'voice' });
    const fl = mk('t3', 'Learn Flutter', 'build', 3, 1200, 60, { src:'voice', moved:1 });
    const DL = [{ id:'d1', title:'WMM report due', day:4, m:1080, cat:'work' }];
    const UP = [{ id:'u1', title:'UPSC prelims mock', day:12, cat:'study', note:'3 study blocks planned before it' }, { id:'u2', title:'Flutter course, module 3', day:16, cat:'build', note:'Nothing planned for it yet' }];
    if (k === 'wed') return { ...b, day:2, now:1300, tasks:[...I, pol, ex, fl], active:k, overAck:{ 2:true }, deadlines:DL, upcoming:UP };
    const polD = { ...pol, done:true, e:1300, pe:1320, doneAt:1300 };
    if (k === 'missed') return { ...b, day:2, now:1385, tasks:[...I, polD, ex, fl], active:k, deadlines:DL, upcoming:UP };
    const wk = [polD, { ...ex, day:5, s:600, e:645, moved:1 }, fl, { ...I[0], day:3, s:1275, e:1320 },
      mk('t4', 'Revise polity notes', 'study', 4, 1200, 90), { ...I[1], day:4, s:1290, e:1320 },
      mk('t6', 'Polity practice test', 'study', 5, 660, 120), mk('t5', 'WMM side project', 'build', 5, 840, 180), mk('t7', 'Flutter: state management', 'build', 5, 1200, 90),
      mk('t8', 'Polity: fundamental rights', 'study', 6, 600, 120), mk('t9', 'Read fiction', 'self', 6, 960, 60), { ...I[2], day:6, s:1080, e:1100 }, mk('i4', 'Journal', 'self', null, null, 15)];
    if (k === 'week') return { ...b, day:3, now:1150, tab:'plan', planSeg:'week', weekSel:3, tasks:wk, deadlines:DL, upcoming:UP, active:k };
    if (k === 'sunday') {
      const t = wk.map(x => x.day == null ? x : x.id === 't7' || x.id === 't9' ? { ...x, skipped:true } : x.day < 6 || x.id === 't8' || x.id === 'i3' ? { ...x, done:true } : x);
      return { ...b, day:6, now:1260, tab:'progress', tasks:t, deadlines:DL, upcoming:UP, weekComplete:true, review:true, rStage:0, active:k, drive:'synced', lastBackup:'Today 19:02' };
    }
    if (k === 'settings') return { ...b, tasks:I, settings:true, sPage:'root', active:k };
    return { ...b, tasks:I };
  }
  jump(k) {
    this.clearTimers(); this.stopMic(); this.speaking = false; this.lastTop = {};
    const keep = { themeLocal:this.state.themeLocal, rmLocal:this.state.rmLocal, micOK:this.state.micOK, mic:this.state.mic, online:this.state.online, speed:this.state.speed, cmd:this.state.cmd };
    const ns = { ...this.snap(k), ...keep };
    if (k === 'voice') ns.cmd = 'multi';
    this.setState(ns);
    this.at(60, () => { this.scrollToNow(); if (k === 'voice') this.at(500, () => this.tapOrb()); if (k === 'sunday') { this.openProgress(); this.at(400, () => this.openReview()); } if (k === 'week') this.at(30, () => this.setState({ recalc:null })); });
  }

  rm() { const l = this.state.rmLocal; if (l === true || l === false) return l; const v = this.props.reducedMotion; if (v === true) return true; return typeof matchMedia !== 'undefined' && matchMedia('(prefers-reduced-motion: reduce)').matches; }
  theme() { return this.state.themeLocal || this.props.theme || 'dark'; }
  N() { return NEU[this.theme()]; }
  at(ms, fn) { this.timers.push(setTimeout(fn, ms)); }
  clearTimers() { this.timers.forEach(clearTimeout); this.timers = []; }
  M() { return this.rm() ? 0.05 : 1; }
  applyVars() {
    const el = this.phoneRef.current; if (!el) return; const C = this.N();
    Object.keys(C).forEach(k => el.style.setProperty('--' + k, C[k]));
    el.style.setProperty('--m', this.rm() ? '0.01' : '1'); el.style.setProperty('--bl', this.rm() ? '0' : '1');
  }
  componentDidMount() {
    this.applyVars();
    this.clockI = setInterval(() => { const s = this.state; if (s.screen !== 'app' || s.review) return; this.setState({ now:Math.min(1439.9, s.now + (s.speed || 1) / 60) }); }, 1000);
    const loop = ts => { this.frame(ts); this.raf = requestAnimationFrame(loop); }; this.raf = requestAnimationFrame(loop);
  }
  componentDidUpdate() { this.applyVars(); }
  componentWillUnmount() { clearInterval(this.clockI); cancelAnimationFrame(this.raf); cancelAnimationFrame(this.cr); this.clearTimers(); this.stopMic(); clearTimeout(this.noteT); }
  buzz(ms) { try { navigator.vibrate && navigator.vibrate(ms); } catch (e) {} }
  say(text, act) { clearTimeout(this.noteT); this.setState({ note:{ text, act:act || null, k:Date.now() } }); this.noteT = setTimeout(() => this.setState({ note:null }), act ? 5200 : 3600); }
  R() { return this.state.routine; }
  dd() { return this.state.day + this.state.tday; }
  vis(tasks) { const pl = this.state.place; return tasks.filter(t => pl[t.id] !== 'hidden' && pl[t.id] !== 'staged'); }
  upd(id, patch) { this.setState(s => ({ tasks:s.tasks.map(t => t.id === id ? { ...t, ...patch } : t) })); }
  newId() { this.seq = (this.seq || 200) + 1; return 'n' + this.seq; }

  /* ---------- orb ---------- */
  frame(ts) {
    const dt = Math.min(0.05, (ts - (this.lt || ts)) / 1000); this.lt = ts;
    const rm = this.rm(), t = rm ? 1.2 : ts / 1000, p = this.p, s = this.state, v = s.voice;
    const T = { amp:this.hover ? 0.16 : 0.03, idle:1, proc:0, succ:0, deny:0 };
    let lv = null;
    if (this.analyser) { this.analyser.getByteTimeDomainData(this.buf); let q = 0; for (let i = 0; i < this.buf.length; i++) { const x = (this.buf[i] - 128) / 128; q += x * x; } lv = Math.min(1, Math.sqrt(q / this.buf.length) * 7); }
    if (v === 'wake') { T.amp = 0.45; T.idle = 0; }
    if (v === 'listening') { T.idle = 0; T.amp = lv != null ? 0.12 + lv * 0.95 : (this.speaking ? 0.35 + 0.65 * Math.abs(Math.sin(t * 9.3) * Math.sin(t * 2.7 + 1)) : 0.14); }
    if (v === 'processing') { T.idle = 0; T.amp = 0.05; T.proc = 1; }
    if (v === 'result') { T.idle = 0.6; T.amp = 0.06; }
    if (v === 'success') { T.idle = 0; T.amp = 0; T.succ = 1; }
    if (v === 'denied') { T.idle = 0.4; T.amp = 0.02; T.deny = 1; }
    const k = rm ? 1 : 1 - Math.exp(-dt * 10);
    for (const key of ['amp', 'idle', 'proc', 'deny']) p[key] += (T[key] - p[key]) * k;
    p.succ += (T.succ - p.succ) * (rm ? 1 : 1 - Math.exp(-dt * (T.succ ? 5 : 12)));
    if (!rm) { const a = -260 * p.wob - 14 * p.wobV; p.wobV += a * dt; p.wob += p.wobV * dt; p.pulse *= Math.exp(-dt * 7); p.cancel *= Math.exp(-dt * 3.2); } else { p.wob = 0; p.pulse = 0; p.cancel = 0; }
    if (v === 'listening' && !rm && p.amp > 0.62 && t - (this.lastRip || 0) > 0.42) { this.lastRip = t; p.ripples.push({ t0:t, s:p.amp }); }
    p.ripples = p.ripples.filter(r => t - r.t0 < 1.8);
    p.core = this.coreRGB || [236, 233, 226];
    drawOrb(this.orbRef.current, p, t, { light:this.theme() === 'light' });
  }
  async startMic() {
    try { const stream = await navigator.mediaDevices.getUserMedia({ audio:true }); const ac = new (window.AudioContext || window.webkitAudioContext)(); const src = ac.createMediaStreamSource(stream); const an = ac.createAnalyser(); an.fftSize = 512; src.connect(an); this.stream = stream; this.actx = ac; this.analyser = an; this.buf = new Uint8Array(an.fftSize); }
    catch (e) { this.setState({ micErr:true }); }
  }
  stopMic() { if (this.stream) this.stream.getTracks().forEach(t => t.stop()); if (this.actx) this.actx.close(); this.stream = this.actx = this.analyser = null; }

  /* ---------- today timeline ---------- */
  scrollToNow() {
    const el = this.tlRef.current; if (!el) return; const s = this.state;
    if (s.tday !== 0) return;
    const L = buildDay(s.day, this.R(), this.vis(s.tasks)).seq;
    el.scrollTo({ top:Math.max(0, this.nowY(L, s.now) - 150), behavior:'auto' });
  }
  nowY(L, now) {
    const it = L.find(x => x.k !== 'marker' && now >= x.s && now < x.e);
    if (it) return it.y + (now - it.s) / (it.e - it.s) * it.h;
    const nx = L.find(x => x.s >= now); return nx ? nx.y : (L.length ? L[L.length - 1].y : 0);
  }
  setDay(off) {
    const s = this.state; if (off === s.tday) return; const M = this.M();
    this.setState({ dayPhase:off > s.tday ? 'outL' : 'outR', dialSel:null });
    this.at(170 * M, () => {
      this.setState({ tday:off, dayPhase:off > s.tday ? 'preR' : 'preL' });
      this.at(30, () => { this.setState({ dayPhase:'in' }); const el = this.tlRef.current; if (!el) return; if (off === 0) this.scrollToNow(); else el.scrollTo({ top:Math.max(0, this.winTop() - 24) }); });
    });
  }
  winTop() {
    const s = this.state; const B = buildDay(this.dd(), this.R(), s.tasks);
    const ids = s.winIds.length ? s.winIds : null;
    const rows = ids ? B.seq.filter(x => ids.includes(x.tid)) : B.seq.filter(x => x.k === 'open' && x.s >= 1080);
    return rows.length ? Math.min(...rows.map(x => x.y)) : 0;
  }
  swDown(e, id) {
    this.sw = { id, x0:e.clientX, y0:e.clientY, el:e.currentTarget, dx:0, active:false, tap:true };
  }
  swMove(e) {
    const w = this.sw; if (!w) return; const dx = e.clientX - w.x0, dy = e.clientY - w.y0;
    if (Math.hypot(dx, dy) > 6) w.tap = false;
    const t = this.state.tasks.find(x => x.id === w.id);
    const can = t && !t.done && t.day === this.state.day && this.state.tday === 0 && !(t.e <= this.state.now);
    if (!w.active) { if (can && Math.abs(dx) > 8 && Math.abs(dx) > Math.abs(dy)) { w.active = true; try { w.el.setPointerCapture(e.pointerId); } catch (er) {} w.el.style.transition = 'none'; } else return; }
    w.dx = Math.max(0, Math.min(140, dx)); const ez = w.dx < 80 ? w.dx : 80 + (w.dx - 80) * 0.35; w.el.style.transform = `translateX(${ez}px)`;
  }
  swUp() {
    const w = this.sw; this.sw = null; if (!w) return;
    if (w.active) { w.el.style.transition = 'transform calc(var(--m,1) * 560ms) cubic-bezier(.34,1.45,.55,1)'; w.el.style.transform = 'translateX(0)'; if (w.dx > 70) this.toggle(w.id, true); return; }
    if (w.tap) { const t = this.state.tasks.find(x => x.id === w.id); if (!t) return; const missed = t.day === this.state.day && !t.done && t.e <= this.state.now; missed ? this.openMissed(t.id) : this.openDetail(t.id); }
  }
  leave(id) {
    const c = this.lastTop[id]; if (!c) return;
    this.setState(s => ({ leaving:{ ...s.leaving, [id]:{ ...c, ph:'lift' } } }));
    this.at(60, () => this.setState(s => ({ leaving:{ ...s.leaving, [id]:{ ...c, ph:'fly' } } })));
    this.at(1000 * this.M() + 80, () => this.setState(s => { const l = { ...s.leaving }; delete l[id]; return { leaving:l }; }));
  }
  moveTask(id, day, s, e, why) {
    const st = this.state, t = st.tasks.find(x => x.id === id); if (!t) return;
    const onToday = st.tab === 'today' && t.day === this.dd() && day !== t.day;
    if (onToday) this.leave(id);
    this.upd(id, { day, s, e, moved:(t.moved || 0) + 1 });
    this.setState(x => ({ fresh:{ ...x.fresh, [id]:Date.now() }, navBump:day !== this.dd() ? Date.now() : x.navBump }));
    this.at(1400, () => this.setState(x => { const f = { ...x.fresh }; delete f[id]; return { fresh:f }; }));
    const prev = { day:t.day, s:t.s, e:t.e };
    this.say(why || `${t.title} moved to ${when(day, s)}.`, { label:'Undo', fn:() => this.upd(id, prev) });
  }
  runPlacement(ids) {
    const M = this.rm() ? 0.1 : 1;
    this.setState({ scanning:true, winLit:true, winIds:ids });
    this.at(40, () => { const el = this.tlRef.current; if (el) el.scrollTo({ top:Math.max(0, this.winTop() - 24), behavior:this.rm() ? 'auto' : 'smooth' }); });
    const t = 850 * M; this.at(t, () => this.setState({ scanning:false }));
    ids.forEach((id, i) => {
      const t0 = t + i * 620 * M;
      this.at(t0, () => this.setState(s => ({ place:{ ...s.place, [id]:'staged' } })));
      this.at(t0 + 360 * M, () => { this.buzz(5); this.setState(s => ({ place:{ ...s.place, [id]:'placed' } })); });
    });
    this.at(t + ids.length * 620 * M + 500 * M, () => this.setState({ winLit:false }));
  }
  overTaskOf(d) {
    const s = this.state, R = this.R();
    const ts = s.tasks.filter(t => t.day === d && live(t) && !t.done).sort((a, b) => b.s - a.s);
    return ts.find(t => t.e > R.sleep - 30) || ts[0];
  }
  moveOver(d) {
    const t = this.overTaskOf(d); if (!t) return; const R = this.R(), dd0 = t.e - t.s;
    let slot = null, nd = d + 1;
    for (; nd < d + 7 && !slot; nd++) { slot = findSlot(nd, dd0, R, this.state.tasks, { excl:t.id, pref:'evening' }); if (slot) break; }
    if (!slot) return;
    this.moveTask(t.id, nd, slot.s, slot.e, `${t.title} moved to ${when(nd, slot.s)}. Your evening fits again.`);
    this.buzz(8);
  }
  keepOver(d) { this.setState(s => ({ overAck:{ ...s.overAck, [d]:true } })); this.say('Kept. The last block runs into your wind-down.'); }
  openProgress() {
    this.setState({ tab:'progress', heatOn:false, ribOn:false, pk:0, heatSel:null, ribSel:null });
    cancelAnimationFrame(this.cr);
    this.at(60, () => {
      this.setState({ heatOn:true, ribOn:true });
      const t0 = performance.now(), D = this.rm() ? 1 : 1500;
      const step = ts => { const x = Math.min(1, (ts - t0) / D); this.setState({ pk:1 - Math.pow(1 - x, 3) }); if (x < 1) this.cr = requestAnimationFrame(step); };
      this.cr = requestAnimationFrame(step);
    });
  }
  goTab(tab) {
    if (tab === this.state.tab && !this.state.settings) return;
    this.setState({ settings:false });
    if (tab === 'progress') { this.openProgress(); return; }
    this.setState({ tab });
    if (tab === 'today') this.at(40, () => this.scrollToNow());
  }

  /* completion: the state commits at once; `sweeping` only stages the visual */
  toggle(id, fromSwipe, delay) {
    const s = this.state, t = s.tasks.find(x => x.id === id); if (!t) return;
    if (t.done) { if (fromSwipe) return; this.upd(id, { done:false, e:t.pe || t.e, pe:null }); return; }
    const M = this.M(), d0 = (delay || 0) * M; this.buzz(12);
    const isNow = s.day === t.day && s.now >= t.s && s.now < t.e;
    const early = isNow ? Math.max(0, Math.round(t.e - Math.max(t.s + 15, ceil5(s.now)))) : 0;
    const patch = { done:true, doneAt:s.now }; if (early >= 5) { patch.pe = t.e; patch.e = t.e - early; }
    this.setState(st => ({ tasks:st.tasks.map(x => x.id === id ? { ...x, ...patch } : x), sweeping:{ ...st.sweeping, [id]:d0 ? 'pre' : 'a' } }));
    if (d0) this.at(d0, () => this.setState(st => ({ sweeping:{ ...st.sweeping, [id]:'a' } })));
    this.at(d0 + 380 * M, () => this.setState(st => ({ sweeping:{ ...st.sweeping, [id]:'b' } })));
    this.at(d0 + 1000 * M, () => this.setState(st => { const w = { ...st.sweeping }; delete w[id]; return { sweeping:w }; }));
    this.say(early >= 5 ? `${t.title} done early. ${early} min back in your evening.` : `${t.title} done.`, { label:'Undo', fn:() => this.upd(id, { done:false, e:patch.pe || t.e, pe:null }) });
  }
  flash(ids) { const now = Date.now(); this.setState(x => { const f = { ...x.fresh }; ids.forEach(i => { f[i] = now; }); return { fresh:f }; }); this.at(1600, () => this.setState(x => { const f = { ...x.fresh }; ids.forEach(i => delete f[i]); return { fresh:f }; })); }
  hold(ids) { const s = this.state, h = { ...s.hold }; ids.forEach(id => { const t = s.tasks.find(x => x.id === id); if (t) h[id] = { day:t.day, s:t.s, e:t.e }; }); this.setState({ hold:h }); }
  release(ids, fly) { ids.forEach(id => { if (fly) this.leave(id); }); this.setState(x => { const h = { ...x.hold }; ids.forEach(i => delete h[i]); return { hold:h }; }); }

  /* ---------- voice ---------- */
  cmdObj() { return CMDS.find(c => c.k === this.state.cmd) || CMDS[0]; }
  sayHey() {
    const s = this.state;
    if (s.screen !== 'app' || s.tab !== 'today' || s.settings || s.review || s.sheet) { this.say('“Hey Planner” works only while Today is open on screen.'); return; }
    if (!s.wakeOn) { this.say('The wake phrase is off. Turn it on in Settings, Voice.'); return; }
    if (s.voice === 'idle') this.tapOrb();
  }
  tapOrb() {
    const s = this.state;
    if (s.voice !== 'idle') { this.veilTap(); return; }
    if (s.screen !== 'app') return;
    this.clearTimers(); this.p.wobV += 9; this.p.pulse = 1; this.buzz(8);
    const c = this.cmdObj(); this.words = c.say.split(' ');
    if (s.mic && s.micOK && !this.analyser) this.startMic();
    this.setState({ voice:'wake', wordN:0, parsed:false, showRes:false, resN:0, res:null, micErr:false, settings:false, review:false, sheet:null, sheetOpen:false });
    const M = this.rm() ? 0.35 : 1; let t = 900 * M;
    if (!s.micOK) { this.at(t, () => this.setState({ voice:'denied' })); return; }
    this.at(t, () => { this.speaking = true; this.setState({ voice:'listening' }); });
    const n = this.words.length;
    for (let i = 1; i <= n; i++) { const q = i; this.at(t + 150 + i * 215 * M, () => this.setState({ wordN:q })); }
    t += 150 + n * 215 * M + 550 * M;
    this.at(t, () => { this.speaking = false; this.setState({ voice:'processing', parsed:true, res:this.resolve(c.k) }); });
    t += 1100 * M;
    this.at(t, () => {
      this.setState({ showRes:true, voice:'result' }); const r = this.state.res; const nr = (r.rows || []).length;
      for (let i = 1; i <= nr; i++) { const q = i; this.at(120 + q * 170 * M, () => this.setState({ resN:q })); }
      if (!r.wait) this.at(1200 * M + nr * 170 * M, () => this.succeed());
    });
  }
  succeed() {
    const r = this.state.res; if (!r) return; const M = this.rm() ? 0.35 : 1;
    this.p.ripples.push({ t0:this.rm() ? 1.2 : performance.now() / 1000, s:1 }); this.buzz(16);
    const after = r.apply ? r.apply() : null;
    this.setState({ voice:'success' });
    this.at(1200 * M, () => { this.setState({ voice:'idle' }); this.stopMic(); if (after) after(); });
  }
  veilTap() {
    const v = this.state.voice, r = this.state.res;
    if (v === 'wake' || v === 'listening' || v === 'processing') return this.cancelVoice();
    if (v === 'result' && r && r.wait) return r.kind === 'confirm' ? this.resNo() : this.closeVoice();
    if (v === 'result') return this.cancelVoice();
    if (v === 'denied') return this.closeVoice();
  }
  cancelVoice() {
    this.clearTimers(); this.speaking = false; this.stopMic(); this.p.cancel = 1;
    this.setState({ voice:'cancelled' });
    this.at(700 * this.M() + 30, () => { this.setState({ voice:'idle' }); this.say('Cancelled. Nothing was changed.'); });
  }
  closeVoice() { this.clearTimers(); this.speaking = false; this.stopMic(); this.setState({ voice:'idle' }); }
  resYes() { const r = this.state.res; if (!r) return; if (r.kind === 'confirm') this.succeed(); else if (r.onYes) r.onYes(); else this.closeVoice(); }
  resNo() { const r = this.state.res; this.closeVoice(); if (r && r.kind === 'confirm') this.say('Kept. Nothing was changed.'); }
  notFound(what, where) { return { label:'NOT FOUND', rows:[], summary:`There's no ${what} task on your plan${where ? ' ' + where : ''}. Try “Add gym tomorrow for one hour.”`, wait:true, kind:'answer', yes:'Done' }; }
  resolve(k) {
    const s = this.state, R = this.R(), today = s.day, tom = s.day + 1;
    const findGym = () => s.tasks.filter(t => live(t) && !t.done && /gym|exercise/i.test(t.title) && t.day >= today).sort((a, b) => a.day - b.day || a.s - b.s)[0];
    const slotText = (d, sl) => `${d === tom ? 'Tomorrow' : d === today ? 'Today' : dayShort(d)}, ${fmt(sl.s)}`;
    if (k === 'multi' || k === 'add' || k === 'evening') {
      let specs;
      if (k === 'multi') specs = [['Study polity', 'study', 120], ['Exercise', 'body', 45], ['Learn Flutter', 'build', 60]].map(([title, cat, d]) => ({ title, cat, d, day:tom }));
      else if (k === 'add') specs = [{ title:'Gym', cat:'body', d:60, day:tom }];
      else specs = s.tasks.filter(t => t.day == null && !t.deleted).map(t => ({ id:t.id, title:t.title, cat:t.cat, d:t.dur, day:today }));
      let all = s.tasks.slice(); const plan = [], left = [];
      specs.forEach(sp => {
        let day = sp.day, sl = findSlot(day, sp.d, R, all, { after:day === today ? ceil5(s.now) : 0, allowWind:k === 'multi', pref:day % 7 < 5 ? 'evening' : null });
        if (!sl && k === 'add') { for (day = tom + 1; day < tom + 7; day++) { sl = findSlot(day, sp.d, R, all, { pref:'evening' }); if (sl) break; } }
        if (!sl) { left.push(sp); return; }
        const nt = sp.id ? { ...s.tasks.find(t => t.id === sp.id), day, s:sl.s, e:sl.e, src:'voice' } : mk(this.newId(), sp.title, sp.cat, day, sl.s, sp.d, { src:'voice' });
        all = sp.id ? all.map(t => t.id === sp.id ? nt : t) : all.concat([nt]);
        plan.push({ nt, sl, day });
      });
      if (!plan.length) return { label:k === 'evening' ? 'TONIGHT' : 'NO ROOM', rows:[], summary:k === 'evening' ? (left.length ? 'Tonight has no room left. Nothing was moved.' : 'Nothing is waiting to be scheduled.') : 'No free time found in the next week.', wait:true, kind:'answer', yes:'Done' };
      const dayOf = plan[0].day, ids = plan.map(p => p.nt.id);
      const label = k === 'evening' ? 'TONIGHT' : dayOf === tom ? 'TOMORROW EVENING' : 'NEXT FREE TIME';
      const rows = plan.map(p => ({ t1:p.nt.title, t2:`${dur(p.nt.e - p.nt.s)}, ${p.day === dayOf && dayOf <= tom ? fmt(p.sl.s) : slotText(p.day, p.sl)}`, cat:p.nt.cat }));
      let summary = '';
      if (k === 'add' && dayOf !== tom) summary = 'Tomorrow evening is full, so Planner found the next free hour.';
      if (left.length) summary = `${left.map(x => x.title).join(', ')} ${left.length > 1 ? "don't" : "doesn't"} fit tonight. ${left.length > 1 ? 'They stay' : 'It stays'} in Unscheduled.`;
      return { label, rows, summary, doneLabel:k === 'evening' ? 'PLANNED FOR TONIGHT' : dayOf === tom ? 'SCHEDULED FOR TOMORROW' : 'SCHEDULED', core:plan[0].nt.cat,
        apply:() => {
          const place = { ...this.state.place }; ids.forEach(id => { place[id] = 'hidden'; });
          this.setState({ tasks:all, place, winIds:ids, winLit:dayOf <= tom });
          return () => {
            if (dayOf <= tom) { this.setState({ tab:'today', settings:false }); if (this.state.tday !== dayOf - today) this.setDay(dayOf - today); this.at(650 * this.M(), () => this.runPlacement(ids)); }
            else { this.setState(x => { const pl = { ...x.place }; ids.forEach(id => delete pl[id]); return { place:pl, winLit:false, tab:'plan', planSeg:'week', weekSel:dayOf, settings:false }; }); this.flash(ids); this.say(`${plan[0].nt.title} added to ${when(dayOf, plan[0].sl.s)}.`); }
          };
        } };
    }
    if (k === 'move') {
      const g = findGym(); if (!g) return this.notFound('gym');
      const sat = today < 5 ? 5 : 12, sl = findSlot(sat, g.e - g.s, R, s.tasks, { excl:g.id, pref:'morning' });
      if (!sl) return { label:'NO ROOM', rows:[], summary:'Saturday has no free hour left.', wait:true, kind:'answer', yes:'Done' };
      return { label:'MOVE', rows:[{ t1:g.title, t2:`${dayShort(g.day)} ${fmt(g.s)} → Sat ${fmt(sl.s)}`, cat:g.cat }], doneLabel:'MOVED TO SATURDAY', core:g.cat,
        apply:() => {
          const id = g.id; this.setState(x => ({ hold:{ ...x.hold, [id]:{ day:g.day, s:g.s, e:g.e } }, tab:'plan', planSeg:'week', weekSel:g.day, settings:false }));
          this.upd(id, { day:sat, s:sl.s, e:sl.e, moved:(g.moved || 0) + 1 });
          return () => this.at(450 * this.M(), () => { this.setState(x => { const h = { ...x.hold }; delete h[id]; return { hold:h, weekSel:sat < 7 ? sat : x.weekSel, recalc:{ days:[g.day, sat], k:Date.now() } }; }); this.flash([id]); this.at(800, () => this.setState({ recalc:null })); this.say(`${g.title} moved to Sat ${fmt(sl.s)}.`); });
        } };
    }
    if (k === 'complete') {
      const g = s.tasks.filter(t => live(t) && !t.done && /gym|exercise/i.test(t.title) && t.day === today)[0];
      if (!g) return this.notFound('gym', 'today');
      return { label:'COMPLETE', rows:[{ t1:g.title, t2:`${fmt(g.s)} → ${fmt(g.e)}`, cat:g.cat }], doneLabel:'MARKED DONE', core:g.cat,
        apply:() => { this.setState({ tab:'today', settings:false }); if (this.state.tday) this.setDay(0); this.toggle(g.id, false, 1300); return null; } };
    }
    if (k === 'del') {
      const g = findGym(); if (!g) return this.notFound('gym');
      return { label:'DELETE THIS TASK?', rows:[{ t1:g.title, t2:`${dayShort(g.day)} ${fmt(g.s)}`, cat:g.cat }], wait:true, kind:'confirm', yes:`Delete ${g.title}`, no:'Keep it', doneLabel:'DELETED', core:g.cat,
        apply:() => { this.upd(g.id, { deleted:true }); return () => this.say(`${g.title} deleted.`, { label:'Undo', fn:() => this.upd(g.id, { deleted:false }) }); } };
    }
    if (k === 'ask') {
      const ts = s.tasks.filter(t => t.day === tom && live(t)).sort((a, b) => a.s - b.s), c = capOf(tom, R, s.tasks, 0);
      const wkd = tom % 7 < 5 && !R.noWork;
      return { label:`TOMORROW, ${DAYL[tom % 7].toUpperCase()}`, rows:ts.length ? ts.map(t => ({ t1:t.title, t2:`${fmt(t.s)} → ${fmt(t.e)}`, cat:t.cat })) : (wkd ? [{ t1:'Office', t2:`${fmt(R.ws)} → ${fmt(R.we)}`, cat:'work' }] : []),
        summary:ts.length ? `${dur(c.planned)} planned, ${dur(c.real)} realistic.` : `Nothing planned yet. ${dur(c.real)} of realistic time is open.`, wait:true, kind:'answer', yes:'Open tomorrow', no:'Done', core:ts[0] ? ts[0].cat : 'work',
        onYes:() => { this.closeVoice(); this.setState({ tab:'today', settings:false }); this.setDay(1); } };
    }
    if (k === 'resched') {
      const miss = s.tasks.filter(t => live(t) && !t.done && t.day != null && (t.day < today || (t.day === today && t.e <= s.now)));
      if (!miss.length) return { label:'ALL CLEAR', rows:[], summary:'Nothing is unfinished. Every past task is done or decided.', wait:true, kind:'answer', yes:'Done' };
      let all = s.tasks.slice(); const plan = [];
      miss.forEach(m => { let sl = null, d = today; for (; d < today + 7; d++) { sl = findSlot(d, m.e - m.s, R, all, { excl:m.id, after:d === today ? ceil5(s.now) : 0 }); if (sl) break; } if (sl) { all = all.map(t => t.id === m.id ? { ...t, day:d, s:sl.s, e:sl.e, moved:(t.moved || 0) + 1 } : t); plan.push({ m, d, sl }); } });
      const ids = plan.map(p => p.m.id);
      return { label:'RESCHEDULE', rows:plan.map(p => ({ t1:p.m.title, t2:`→ ${slotText(p.d, p.sl)}`, cat:p.m.cat })), doneLabel:'RESCHEDULED', core:plan[0] ? plan[0].m.cat : null,
        apply:() => { this.hold(ids); this.setState({ tasks:all }); return () => { this.setState({ tab:'today', settings:false }); if (this.state.tday) this.setDay(0); this.at(300, () => { this.release(ids, true); this.say(`${plan.length} ${plan.length > 1 ? 'tasks' : 'task'} moved forward.`); }); }; } };
    }
    if (k === 'recur') {
      const from = today < 7 ? 7 : today + 7 - (today % 7);
      return { label:'EVERY MONDAY', rows:[{ t1:'Gym', t2:'1h, 20:00 → 21:00', cat:'body' }], summary:`Starts ${dayLabel(from).replace(/^\w+ /, 'Monday ')}. It repeats until you stop it.`, doneLabel:'REPEATS EVERY MONDAY', core:'body',
        apply:() => { this.setState(x => ({ series:[...x.series.filter(q => q.id !== 'sg'), { id:'sg', title:'Gym', cat:'body', rule:'Every Monday', s:1200, e:1260, from }] })); return () => { this.setState({ tab:'plan', planSeg:'upcoming', settings:false }); this.say('Gym repeats every Monday from 5 October.'); }; } };
    }
    return this.notFound('matching');
  }
  denyType() { this.closeVoice(); this.at(100, () => this.openCreate()); }
  denyAllow() { this.setState({ micOK:true }); this.closeVoice(); this.at(250, () => this.tapOrb()); }

  /* ---------- sheets ---------- */
  openSheet(sheet, sid, extra) { this.setState({ sheet, sid, sheetOpen:false, delArm:false, pickDate:false, ...(extra || {}) }); this.at(20, () => this.setState({ sheetOpen:true })); }
  closeSheet() { this.setState({ sheetOpen:false, delArm:false }); this.at(420 * this.M() + 20, () => { if (!this.state.sheetOpen) this.setState({ sheet:null }); }); }
  openDetail(id) { this.openSheet('detail', id); }
  openMissed(id, mode) { this.openSheet('missed', id, { missMode:mode || 'missed' }); }
  openCreate(pre) { this.openSheet('create', null, { f:{ title:'', cat:null, catSet:false, dur:null, date:null, pref:'any', at:null, prio:'normal', deadline:null, recur:'never', more:false, catPick:false, datePick:false, editId:null, heard:null, ...(pre || {}) } }); }
  setF(patch) { this.setState(s => ({ f:{ ...s.f, ...patch } })); }
  reOptions(t) {
    const s = this.state, R = this.R(), dd0 = t.e - t.s, today = s.day, out = [];
    const mkOpt = (key, label, d, o) => { const sl = d == null ? null : findSlot(d, dd0, R, s.tasks, { excl:t.id, ...(o || {}) }); return { key, label, d, sl, text:sl ? `${d === today ? 'Today' : d === today + 1 ? 'Tomorrow' : DAYN[d % 7]} ${fmt(sl.s)}` : 'No room', ok:!!sl }; };
    out.push(mkOpt('today', 'Later today', today, { after:ceil5(s.now) }));
    out.push(mkOpt('tom', 'Tomorrow', today + 1, { pref:(today + 1) % 7 < 5 ? 'evening' : 'morning' }));
    const wd = today < 5 ? 5 : today === 5 ? 6 : 12; out.push(mkOpt('wknd', 'This weekend', wd, { pref:'morning' }));
    if (out[0].ok === false) out[0].text = 'No room left today';
    return out;
  }
  reschedTo(id, d, sl) {
    const t = this.state.tasks.find(x => x.id === id); if (!t || !sl) return;
    const same = d === t.day, onView = this.state.tab === 'today' && t.day === this.dd();
    if (onView && !same) this.hold([id]);
    this.upd(id, { day:d, s:sl.s, e:sl.e, moved:(t.moved || 0) + 1 });
    this.closeSheet();
    const prev = { day:t.day, s:t.s, e:t.e };
    this.at(260 * this.M(), () => { if (onView && !same) { this.release([id], true); this.setState({ navBump:Date.now() }); } if (this.state.tab === 'plan') this.flash([id]); });
    this.say(`${t.title} moved to ${d === this.state.day ? 'today, ' + fmt(sl.s) : when(d, sl.s)}.`, { label:'Undo', fn:() => this.upd(id, prev) });
  }
  skipTask(id) { const t = this.state.tasks.find(x => x.id === id); this.upd(id, { skipped:true }); this.closeSheet(); this.say(`${t.title} skipped this time.`, { label:'Undo', fn:() => this.upd(id, { skipped:false }) }); }
  delTask(id) {
    if (!this.state.delArm) { this.setState({ delArm:true }); return; }
    const t = this.state.tasks.find(x => x.id === id); this.upd(id, { deleted:true }); this.closeSheet();
    this.say(`${t.title} deleted.`, { label:'Undo', fn:() => this.upd(id, { deleted:false }) });
  }
  completeFromSheet(id) { const t = this.state.tasks.find(x => x.id === id); this.closeSheet(); if (t && t.done) { this.upd(id, { done:false, e:t.pe || t.e, pe:null }); return; } this.toggle(id, false, 300); }
  editTask(id) { const t = this.state.tasks.find(x => x.id === id); this.openCreate({ title:t.title, cat:t.cat, catSet:true, dur:t.e - t.s, date:t.day, pref:'exact', at:t.s, prio:t.prio, deadline:t.deadline, recur:t.recur || 'never', editId:id }); }
  previewSlot(f) {
    const s = this.state, R = this.R(); if (!f || !f.title || !f.dur) return null;
    const o = { excl:f.editId, pref:f.pref === 'exact' ? null : f.pref === 'any' ? null : f.pref, at:f.pref === 'exact' ? f.at : null };
    const days = f.date != null ? [f.date] : [s.day, s.day + 1, s.day + 2, s.day + 3, s.day + 4, s.day + 5, s.day + 6];
    for (const wind of [false, true]) for (const d of days) { const sl = findSlot(d, f.dur, R, s.tasks, { ...o, after:d === s.day ? ceil5(s.now) : 0, allowWind:wind }); if (sl) return { d, ...sl }; }
    return null;
  }
  schedule() {
    const s = this.state, f = s.f; const sl = this.previewSlot(f); if (!sl) return;
    const cat = f.cat || guessCat(f.title);
    if (f.editId) {
      this.upd(f.editId, { title:f.title, cat, day:sl.d, s:sl.s, e:sl.e, prio:f.prio, deadline:f.deadline, recur:f.recur === 'never' ? null : f.recur });
      this.closeSheet(); this.say('Saved.'); return;
    }
    const id = this.newId();
    const t = mk(id, f.title.trim(), cat, sl.d, sl.s, f.dur, { prio:f.prio, deadline:f.deadline, recur:f.recur === 'never' ? null : f.recur, src:f.heard ? 'voice' : 'manual' });
    this.closeSheet();
    const rel = sl.d - s.day;
    if (rel <= 1) {
      this.setState(x => ({ tasks:[...x.tasks, t], place:{ ...x.place, [id]:'hidden' }, winIds:[id], winLit:true, tab:'today', settings:false }));
      if (s.tday !== rel) this.setDay(rel);
      this.at(560 * this.M(), () => this.runPlacement([id]));
    } else {
      this.setState(x => ({ tasks:[...x.tasks, t], tab:'plan', planSeg:'week', weekSel:sl.d < 7 ? sl.d : x.weekSel, settings:false })); this.flash([id]);
      this.say(`${t.title} added to ${when(sl.d, sl.s)}.`);
    }
  }
  fitIn(id) {
    const s = this.state, t = s.tasks.find(x => x.id === id), R = this.R(); if (!t) return;
    for (let d = s.day; d < s.day + 7; d++) { const sl = findSlot(d, t.dur, R, s.tasks, { after:d === s.day ? ceil5(s.now) : 0, pref:d % 7 < 5 ? 'evening' : 'morning' }); if (sl) { this.upd(id, { day:d, s:sl.s, e:sl.e }); this.flash([id]); if (this.state.planSeg !== 'upcoming' && d < 7) this.setState({ weekSel:d }); this.say(`${t.title} fits ${d === s.day ? 'today, ' + fmt(sl.s) : when(d, sl.s)}.`); return; } }
    this.say(`No room for ${t.title} this week.`);
  }

  /* ---------- onboarding ---------- */
  obKey() { return ['wake', 'ws', 'we', 'sleep'][this.state.ob.step]; }
  obRange(k, ob) { if (k === 'wake') return [240, 720]; if (k === 'ws') return [ob.wake + 15, 840]; if (k === 'we') return [ob.ws + 60, 1380]; return [Math.max(ob.we + 60, 1200), 1560]; }
  obSet(v) { const k = this.obKey(); if (!k) return; this.setState(s => { const ob = { ...s.ob }; const [lo, hi] = this.obRange(k, ob); ob[k] = clamp(v, lo, hi); if (k === 'wake' && ob.ws < ob.wake + 15) ob.ws = ob.wake + 15; if (ob.we < ob.ws + 60) ob.we = ob.ws + 60; if (ob.sleep < ob.we + 60) ob.sleep = ob.we + 60; return { ob }; }); }
  rDown(e) { const el = e.currentTarget, r = el.getBoundingClientRect(); this.rul = { x0:e.clientX, v0:this.state.ob[this.obKey()], sc:r.width / 320 }; try { el.setPointerCapture(e.pointerId); } catch (er) {} }
  rMove(e) { if (!this.rul) return; const dx = (e.clientX - this.rul.x0) / this.rul.sc; this.obSet(Math.round((this.rul.v0 - dx / 2) / 5) * 5); }
  rUp() { this.rul = null; }
  obNext() {
    const s = this.state, st = s.ob.step;
    if (st === 1 && s.ob.noWork) { this.setState({ ob:{ ...s.ob, step:3 } }); return; }
    if (st < 4) { this.setState({ ob:{ ...s.ob, step:st + 1 } }); return; }
    if (st === 4) {
      const ob = s.ob, R = { wake:ob.wake, ws:ob.ws, we:ob.we, sleep:ob.sleep, noWork:ob.noWork, commits:ob.commits.map(c => ({ ...c })) };
      this.setState({ routine:R, ob:{ ...ob, step:5 }, obN:0 });
      const M = this.rm() ? 0.1 : 1; for (let i = 1; i <= 9; i++) { const q = i; this.at(300 + i * 240 * M, () => this.setState({ obN:q })); }
    }
  }
  obBack() { const s = this.state, st = s.ob.step; if (st === 0) return; this.setState({ ob:{ ...s.ob, step:st === 3 && s.ob.noWork ? 1 : st - 1 } }); }
  openApp() {
    const M = this.M(); const edit = this.state.obEdit;
    this.setState({ obOut:true });
    this.at(380 * M, () => { this.setState({ screen:'app', appIn:false, obOut:false, obEdit:false, tab:'today', tday:0 }); this.at(40, () => { this.setState({ appIn:true }); this.scrollToNow(); if (edit) this.say('Routine updated. Planner rebuilt your week around it.'); }); });
  }
  editRoutine() { const R = this.R(); this.setState({ screen:'onboarding', obEdit:true, settings:false, ob:{ step:0, wake:R.wake, ws:R.ws, we:R.we, sleep:R.sleep, noWork:R.noWork, commits:R.commits.map(c => ({ ...c })), cu:null }, obN:0, obOut:false }); }
  cuAdd() {
    const s = this.state, cu = s.ob.cu; if (!cu || !cu.title.trim()) return;
    const c = { id:'cu' + Date.now(), title:cu.title.trim(), cat:guessCat(cu.title), s:cu.at, e:cu.at + cu.len, days:cu.days, on:true, label:`${cu.days === 'all' ? 'Every day' : cu.days === 'wk' ? 'Weekdays' : 'Weekends'}, ${fmt(cu.at)} → ${fmt(cu.at + cu.len)}` };
    this.setState({ ob:{ ...s.ob, commits:[...s.ob.commits, c], cu:null } });
  }

  /* ---------- plan board ---------- */
  geo() {
    const s = this.state, mode = s.planSeg === 'week' ? 'week' : 'day';
    const AX = 26, WB = 368 - AX, g = mode === 'week' ? 4 : 3, c = mode === 'week' ? 26 : 12, W = WB - 6 * c - 6 * g;
    const sel = mode === 'week' ? s.weekSel : s.planSeg === 'tomorrow' ? s.day + 1 : s.day;
    const xs = [], ws = []; let x = AX;
    for (let d = 0; d < 7; d++) { const w = d === sel ? W : c; xs.push(x); ws.push(w); x += w + g; }
    return { mode, sel, xs, ws, W, c, AX, HB:44, BH:432, K:432 / 1080 };
  }
  wDown(e, id) {
    const el = this.boardRef.current; if (!el) return; const r = el.getBoundingClientRect();
    this.wd = { id, x0:e.clientX, y0:e.clientY, sc:r.width / 368, left:r.left, top:r.top, el:e.currentTarget, active:false, tap:true };
  }
  wMove(e) {
    const w = this.wd; if (!w) return; const dx = (e.clientX - w.x0) / w.sc, dy = (e.clientY - w.y0) / w.sc;
    const t = this.state.tasks.find(x => x.id === w.id); if (!t) return;
    if (!w.active) { if (Math.hypot(dx, dy) < 6) return; w.tap = false; if (t.done) return; w.active = true; try { w.el.setPointerCapture(e.pointerId); } catch (er) {} this.buzz(6); }
    const G = this.geo(), px = (e.clientX - w.left) / w.sc;
    let hd = t.day; for (let d = 0; d < 7; d++) if (px >= G.xs[d] - 2 && px < G.xs[d] + G.ws[d] + 2) hd = d;
    if (hd < this.state.day) hd = this.state.day;
    const dd0 = t.e - t.s, R = this.R();
    let st = Math.round((t.s + dy / G.K) / 15) * 15; st = clamp(st, R.wake, R.sleep - dd0);
    if (hd === this.state.day) st = Math.max(st, ceil5(this.state.now));
    this.setState({ drag:{ id:w.id, dx, dy, day:hd, s:st } });
  }
  wUp() {
    const w = this.wd; this.wd = null; if (!w) return; const s = this.state;
    if (w.active && s.drag) {
      const d = s.drag, t = s.tasks.find(x => x.id === d.id), from = t.day;
      const nt = ripple(s.tasks, d.id, d.day, d.s, this.R()); const moved = nt.find(x => x.id === d.id);
      const pushed = nt.filter(x => { const o = s.tasks.find(y => y.id === x.id); return x.id !== d.id && o && (o.s !== x.s || o.day !== x.day); }).length;
      this.setState({ tasks:nt, drag:null, recalc:{ days:[from, d.day], k:Date.now() } }); this.buzz(5);
      this.at(900, () => this.setState({ recalc:null }));
      const c = capOf(moved.day, this.R(), nt, moved.day === s.day ? s.now : 0);
      const tail = c.over > 15 ? ` ${DAYL[moved.day % 7]} is now ${dur(c.over)} over what fits.` : ` ${DAYL[moved.day % 7]}: ${dur(c.planned)} planned.`;
      this.say(`${t.title} moved to ${when(moved.day, moved.s)}.${pushed ? ` ${pushed} ${pushed > 1 ? 'blocks' : 'block'} made room.` : ''}${tail}`, { label:'Undo', fn:() => this.setState({ tasks:s.tasks }) });
      return;
    }
    if (s.drag) this.setState({ drag:null });
    if (w.tap) { const t = s.tasks.find(x => x.id === w.id); if (!t) return; const missed = !t.done && (t.day < s.day || (t.day === s.day && t.e <= s.now)); missed ? this.openMissed(t.id) : this.openDetail(t.id); }
  }
  setSeg(seg) {
    const s = this.state;
    if (seg === 'today') this.setState({ planSeg:'today', weekSel:s.day }); else if (seg === 'tomorrow') this.setState({ planSeg:'tomorrow', weekSel:s.day + 1 }); else this.setState({ planSeg:seg });
  }
  selDay(d) {
    const s = this.state;
    if (s.planSeg !== 'week') { if (d === s.day) this.setState({ planSeg:'today', weekSel:d }); else if (d === s.day + 1) this.setState({ planSeg:'tomorrow', weekSel:d }); else this.setState({ planSeg:'week', weekSel:d }); return; }
    this.setState({ weekSel:d });
  }
  moveOverDay(d) { this.moveOverGeneric(d); }
  moveOverGeneric(d) {
    const s = this.state, R = this.R(), c = capOf(d, R, s.tasks, d === s.day ? s.now : 0); if (c.over <= 0) return;
    const ts = s.tasks.filter(t => t.day === d && live(t) && !t.done && (d !== s.day || t.s >= s.now)).sort((a, b) => (b.e - b.s) - (a.e - a.s));
    const t = ts.find(x => x.e - x.s >= c.over) || ts[0]; if (!t) return;
    for (let nd = d + 1; nd < 7; nd++) { const sl = findSlot(nd, t.e - t.s, R, s.tasks, { excl:t.id, pref:nd % 7 < 5 ? 'evening' : 'morning' }); if (sl) { this.moveTask(t.id, nd, sl.s, sl.e, `${t.title} moved to ${when(nd, sl.s)}. ${DAYL[d % 7]} fits again.`); this.setState({ recalc:{ days:[d, nd], k:Date.now() } }); this.at(900, () => this.setState({ recalc:null })); return; } }
    this.say('No lighter day this week. Keeping it.');
  }

  /* ---------- review, settings, drive ---------- */
  openReview() { this.setState({ review:true, rStage:0, rOn:false }); this.at(60, () => this.setState({ rOn:true })); }
  rGo(n) { if (n < 0) return; if (n > 5) { this.closeReview(); return; } this.setState({ rStage:n, rOn:false }); this.at(40, () => this.setState({ rOn:true })); }
  closeReview() { this.setState({ review:false }); }
  planNext() { this.setState({ review:false, tab:'plan', planSeg:'upcoming' }); this.say('Next week starts with 1 carried-forward task and 2 deadlines.'); }
  driveGo(k) {
    const M = this.rm() ? 0.2 : 1;
    if (k === 'connect') { this.setState({ drive:'connecting' }); this.at(1600 * M, () => this.setState({ drive:'synced', lastBackup:'Just now' })); }
    if (k === 'backup') { if (!this.state.online) return; this.setState({ drive:'backing', driveProg:0 }); for (let i = 1; i <= 10; i++) { const q = i; this.at(q * 140 * M, () => this.setState({ driveProg:q * 10 })); } this.at(1500 * M, () => { this.setState({ drive:'synced', lastBackup:'Just now' }); this.say('Backed up to Google Drive.'); }); }
    if (k === 'restore') this.setState({ restoreAsk:true });
    if (k === 'restoreYes') { this.setState({ restoreAsk:false, drive:'restoring', driveProg:0 }); for (let i = 1; i <= 10; i++) { const q = i; this.at(q * 160 * M, () => this.setState({ driveProg:q * 10 })); } this.at(1700 * M, () => { this.setState({ drive:'synced', lastBackup:'Just now' }); this.say('Restored from your Drive backup. The previous plan was saved first.'); }); }
    if (k === 'restoreNo') this.setState({ restoreAsk:false });
    if (k === 'disconnect') { this.setState({ drive:'off', lastBackup:null }); this.say('Disconnected. Everything stays on this phone.'); }
    if (k === 'conflict') this.setState({ drive:'conflict', settings:true, sPage:'drive', tab:this.state.tab });
    if (k === 'keepPhone') { this.setState({ drive:'synced', lastBackup:'Just now' }); this.say('Kept this phone. The Drive copy was saved as a separate backup.'); }
    if (k === 'useDrive') { this.setState({ drive:'synced', lastBackup:'Just now' }); this.say('Using the Drive version. This phone’s copy was saved first.'); }
  }

  openBlock(id) {
    if (this.swJust) { this.swJust = false; return; }
    const s = this.state, t = s.tasks.find(x => x.id === id); if (!t) return;
    const missed = !t.done && (t.day < s.day || (t.day === s.day && t.e <= s.now));
    missed ? this.openMissed(id) : this.openDetail(id);
  }
  openBoard(id) { if (this.wdJust) { this.wdJust = false; return; } this.openBlock(id); }

  renderVals() {
    const s = this.state, N = this.N(), dark = this.theme() === 'dark', R = this.R(), now = s.now, today = s.day;
    const tint = (cat, a) => mixHex(N.bg, (CAT[cat] || CAT.self).c, a == null ? (dark ? 0.2 : 0.16) : a);
    const eff = s.tasks.map(t => s.hold[t.id] ? { ...t, ...s.hold[t.id] } : t);
    const visT = eff.filter(t => s.place[t.id] !== 'hidden' && s.place[t.id] !== 'staged');
    const V = {};
    const tog = (on) => ({ bg:on ? '#161616' : 'transparent', c:on ? '#ffffff' : '#161616' });

    /* ===== director ===== */
    V.steps = [
      ['onboard', 'Install and set up', 'Five questions, then the rhythm assembles itself'],
      ['tue', 'Tue 19:40, the first evening', 'Routine in place, evening still empty'],
      ['voice', 'Say the three-task request', 'Planner finds tomorrow’s window and fills it'],
      ['wed', 'Wed 21:40, mid-study', 'Finish the current block early'],
      ['missed', 'Wed 23:05, a missed task', '“What should we do with this?”'],
      ['week', 'Thu, plan the week', 'Drag blocks, watch the days rebalance'],
      ['sunday', 'Sun 21:00, the weekly review', 'What actually happened'],
      ['settings', 'Settings and Google Drive', 'Backup, restore, conflicts, offline']
    ].map(([k, t, d], i) => ({ n:String(i + 1), t, d, bg:s.active === k ? '#161616' : 'transparent', c:s.active === k ? '#ffffff' : '#161616', c2:s.active === k ? 'rgba(255,255,255,.7)' : '#5b5b56', go:() => this.jump(k) }));
    V.cmds = CMDS.map(c => ({ t:c.say, ...tog(s.cmd === c.k), pick:() => this.setState({ cmd:c.k }) }));
    const sw = (label, a, b, on, fa, fb) => ({ label, a, b, aBg:!on ? '#161616' : 'transparent', aC:!on ? '#fff' : '#161616', bBg:on ? '#161616' : 'transparent', bC:on ? '#fff' : '#161616', fa, fb });
    V.switches = [
      sw('Theme', 'Dark', 'Light', !dark, () => this.setState({ themeLocal:'dark' }), () => this.setState({ themeLocal:'light' })),
      sw('Motion', 'Full', 'Reduced', this.rm(), () => this.setState({ rmLocal:false }), () => this.setState({ rmLocal:true })),
      sw('Microphone', 'Allowed', 'Denied', !s.micOK, () => this.setState({ micOK:true }), () => this.setState({ micOK:false })),
      sw('Voice input', 'Demo', 'Live mic', s.mic, () => { this.setState({ mic:false }); this.stopMic(); }, () => this.setState({ mic:true })),
      sw('Network', 'Online', 'Offline', !s.online, () => this.setState({ online:true, drive:s.drive === 'offline' ? 'synced' : s.drive }), () => this.setState({ online:false })),
      sw('Clock', '1×', '60×', s.speed > 1, () => this.setState({ speed:1 }), () => this.setState({ speed:60 }))
    ];
    V.sayHey = () => this.sayHey(); V.forceConflict = () => { if (s.drive === 'off') this.setState({ drive:'synced', lastBackup:'Yesterday 22:40' }); this.driveGo('conflict'); };
    V.jumpTime = () => this.setState(x => ({ now:Math.min(1439, x.now + 30) }));

    /* ===== frame ===== */
    V.phoneRef = this.phoneRef; V.tlRef = this.tlRef; V.orbRef = this.orbRef; V.boardRef = this.boardRef; V.planRef = this.planRef;
    V.isOb = s.screen === 'onboarding'; V.isApp = s.screen === 'app';
    V.obO = V.isOb && !s.obOut ? '1' : '0'; V.obT = V.isOb && !s.obOut ? 'none' : 'scale(1.03)'; V.obF = V.isOb && !s.obOut ? 'blur(0px)' : 'blur(calc(var(--bl,1) * 8px))'; V.obPE = V.isOb ? 'auto' : 'none';
    V.appO = V.isApp && s.appIn ? '1' : '0'; V.appT = V.isApp && s.appIn ? 'none' : 'scale(.98)'; V.appPE = V.isApp ? 'auto' : 'none';

    /* ===== onboarding ===== */
    const ob = s.ob, qk = ['wake', 'ws', 'we', 'sleep'][ob.step];
    V.obSteps = [0, 1, 2, 3, 4].map(i => ({ w:i <= Math.min(ob.step, 4) ? 'scaleX(1)' : 'scaleX(0)' }));
    V.obQ = ['When do you wake up?', 'When does work begin?', 'When does work end?', 'When do you normally sleep?', 'What recurring commitments do you have?', ''][ob.step];
    V.obSub = ['Your day starts here. Planner never schedules before it.', 'Planner keeps working hours off-limits.', 'Your own time usually starts after this.', 'Planner protects the last 30 minutes as wind-down.', 'Planner builds around these. Pick any that apply.', ''][ob.step];
    V.obIsTime = ob.step <= 3; V.obIsCommit = ob.step === 4; V.obIsBuild = ob.step === 5; V.obIsQ = ob.step <= 4;
    V.obVal = qk ? fmt(ob[qk]) : '';
    V.obValAria = qk ? `${V.obQ} ${fmt(ob[qk])}` : '';
    V.obIsWork = ob.step === 1; V.obNoWork = ob.noWork; V.obNoWorkBg = ob.noWork ? 'var(--tx)' : 'transparent'; V.obNoWorkC = ob.noWork ? 'var(--bg)' : 'var(--t2)';
    V.obToggleNoWork = () => this.setState(x => ({ ob:{ ...x.ob, noWork:!x.ob.noWork } }));
    if (qk) {
      const v = ob[qk], st = Math.ceil((v - 150) / 15) * 15; V.ticks = [];
      for (let m = st; m <= v + 150; m += 15) { const hr = m % 60 === 0; V.ticks.push({ x:(160 + (m - v) * 2 - 0.5) + 'px', h:hr ? '18px' : m % 30 === 0 ? '12px' : '7px', c:hr ? 'var(--tx)' : 'var(--t3)', lab:hr ? fmt(m).slice(0, 2) : '', lx:(160 + (m - v) * 2 - 8) + 'px' }); }
    } else V.ticks = [];
    V.obMinus = () => this.obSet(ob[qk] - 15); V.obPlus = () => this.obSet(ob[qk] + 15);
    V.rDown = e => this.rDown(e); V.rMove = e => this.rMove(e); V.rUp = () => this.rUp();
    const RO = { wake:ob.wake, ws:ob.ws, we:ob.we, sleep:Math.min(ob.sleep, 1440), noWork:ob.noWork, commits:ob.commits };
    const pv = buildDay(1, RO, []).seq.filter(x => x.k !== 'marker');
    const PXD = 360 / 1440;
    V.obBar = [{ l:'0px', w:(ob.wake * PXD) + 'px', bg:'var(--s1)', bd:'none' }].concat(pv.map(x => ({ l:(x.s * PXD) + 'px', w:Math.max(1, (x.e - x.s) * PXD - 1) + 'px',
      bg:x.k === 'fixed' ? (CAT[x.cat] || CAT.work).c : x.k === 'prot' ? 'repeating-linear-gradient(135deg,var(--t3) 0 1px,transparent 1px 4px)' : 'transparent',
      bd:x.k === 'open' ? '1px dashed var(--t2)' : 'none' }))).concat(ob.sleep < 1440 ? [{ l:(ob.sleep * PXD) + 'px', w:((1440 - ob.sleep) * PXD) + 'px', bg:'var(--s1)', bd:'none' }] : []);
    V.obMarkX = qk ? (Math.min(ob[qk], 1440) * PXD - 1) + 'px' : '-10px'; V.obMarkO = qk ? '1' : '0';
    V.obBarLegend = ob.noWork ? 'Your own time: everything outside sleep and meals' : `Office ${fmt(ob.ws)} → ${fmt(ob.we)}`;
    V.obCommits = ob.commits.map(c => ({ title:c.title, label:c.label, sq:(CAT[c.cat] || CAT.self).c, on:c.on, bg:c.on ? 'var(--s1)' : 'transparent', bd:c.on ? 'var(--tx)' : 'var(--ln)', mark:c.on ? '1' : '0', aria:String(!!c.on), flip:() => this.setState(x => ({ ob:{ ...x.ob, commits:x.ob.commits.map(q => q.id === c.id ? { ...q, on:!q.on } : q) } })) }));
    V.cuOpen = !!ob.cu; V.cuShow = () => this.setState(x => ({ ob:{ ...x.ob, cu:{ title:'', at:1080, len:30, days:'all' } } }));
    const cu = ob.cu || { title:'', at:1080, len:30, days:'all' };
    V.cuTitle = cu.title; V.cuOnTitle = e => { const v = e.target.value; this.setState(x => ({ ob:{ ...x.ob, cu:{ ...x.ob.cu, title:v } } })); };
    V.cuAts = [450, 780, 1080, 1260].map(m => ({ t:fmt(m), ...(cu.at === m ? { bg:'var(--tx)', c:'var(--bg)' } : { bg:'var(--s1)', c:'var(--t2)' }), pick:() => this.setState(x => ({ ob:{ ...x.ob, cu:{ ...x.ob.cu, at:m } } })) }));
    V.cuLens = [30, 60].map(m => ({ t:dur(m), ...(cu.len === m ? { bg:'var(--tx)', c:'var(--bg)' } : { bg:'var(--s1)', c:'var(--t2)' }), pick:() => this.setState(x => ({ ob:{ ...x.ob, cu:{ ...x.ob.cu, len:m } } })) }));
    V.cuDays = [['all', 'Every day'], ['wk', 'Weekdays'], ['we', 'Weekends']].map(([k, t]) => ({ t, ...(cu.days === k ? { bg:'var(--tx)', c:'var(--bg)' } : { bg:'var(--s1)', c:'var(--t2)' }), pick:() => this.setState(x => ({ ob:{ ...x.ob, cu:{ ...x.ob.cu, days:k } } })) }));
    V.cuAdd = () => this.cuAdd(); V.cuCancel = () => this.setState(x => ({ ob:{ ...x.ob, cu:null } }));
    V.obNext = () => this.obNext(); V.obBack = () => this.obBack(); V.obCanBack = ob.step > 0 && ob.step < 5;
    V.obNextLabel = ob.step === 4 ? 'Build my rhythm' : 'Continue';
    const asm = buildDay(1, s.routine, []).seq;
    V.asm = asm.map((x, i) => { const on = i < s.obN; const dd = x.e - x.s; const h = x.k === 'marker' ? 22 : x.k === 'fixed' ? (dd > 90 ? 40 : Math.max(24, dd * 0.4)) : Math.max(22, dd * 0.38);
      return { h:h + 'px', o:on ? '1' : '0', t:on ? 'none' : 'translateY(14px) scale(.98)', time:fmt(x.s), title:x.k === 'open' ? 'Your time' : x.title, meta:x.k === 'marker' ? '' : `${fmt(x.s)} → ${fmt(x.e)}`,
        isM:x.k === 'marker', isF:x.k === 'fixed', isP:x.k === 'prot', isO:x.k === 'open', bg:x.k === 'fixed' ? tint(x.cat, dark ? 0.3 : 0.24) : 'transparent', d:`calc(var(--m,1) * ${i * 20}ms)` }; });
    const ready = s.obN >= Math.min(9, asm.length + 1);
    V.obReady = ready; V.obReadyO = ready ? '1' : '0'; V.obReadyT = ready ? 'none' : 'translateY(12px)';
    const cw = capOf(1, s.routine, [], 0), cwe = capOf(5, s.routine, [], 0);
    V.obCap = `${dur(cw.real)} of realistic time every weekday evening. Up to ${dur(cwe.real)} on weekends.`;
    V.obBuildTitle = ready ? 'Your rhythm is ready.' : 'Building your rhythm';
    V.openApp = () => this.openApp();

    /* ===== today ===== */
    const isT = s.tday === 0, dd = today + s.tday;
    const B = buildDay(dd, R, eff), L = B.seq, Lmap = {}; L.forEach(x => { if (x.tid) Lmap[x.tid] = x; });
    const dayT = B.ts.filter(t => s.place[t.id] !== 'hidden' && s.place[t.id] !== 'staged');
    const cur = isT ? dayT.find(t => !t.done && now >= t.s && now < t.e) : null;
    const next = isT ? dayT.find(t => !t.done && t.s >= now && (!cur || t.id !== cur.id)) : null;
    const curFixed = isT && !cur ? L.find(x => x.k === 'fixed' && now >= x.s && now < x.e) : null;
    this.coreRGB = (() => { if (s.voice !== 'idle' && s.res && s.res.core) return rgb(CAT[s.res.core].c); if (cur) return rgb(CAT[cur.cat].c); return null; })();
    V.dateLabel = dayLabel(dd);
    V.dayThumb = isT ? 'translateX(0)' : 'translateX(100%)'; V.dayTodayC = isT ? 'var(--tx)' : 'var(--t3)'; V.dayTomC = isT ? 'var(--t3)' : 'var(--tx)';
    V.goToday = () => this.setDay(0); V.goTomorrow = () => this.setDay(1);
    V.dayTomT = s.navBump && Date.now() - s.navBump < 700 ? 'scale(1.08)' : 'none';
    V.viewThumb = s.view === 'strip' ? 'translateX(0)' : 'translateX(100%)'; V.viewStripC = s.view === 'strip' ? 'var(--tx)' : 'var(--t3)'; V.viewDialC = s.view === 'dial' ? 'var(--tx)' : 'var(--t3)';
    V.viewStrip = () => this.setState({ view:'strip' }); V.viewDial = () => { this.setState({ view:'dial', dialIn:false }); this.at(40, () => this.setState({ dialIn:true })); };
    let nowLabel = '', nowTitle = '', nowMeta = '';
    if (isT) {
      if (cur) { nowLabel = 'Now'; nowTitle = cur.title; nowMeta = `${Math.max(1, Math.ceil(cur.e - now))} min left`; }
      else if (curFixed) { nowLabel = 'Now'; nowTitle = curFixed.title; nowMeta = next ? `then ${next.title} at ${fmt(next.s)}` : `until ${fmt(curFixed.e)}`; }
      else if (next) { nowLabel = 'Next'; nowTitle = next.title; nowMeta = `at ${fmt(next.s)}`; }
      else { nowLabel = 'Evening'; nowTitle = 'is yours'; nowMeta = `sleep at ${fmt(R.sleep)}`; }
    } else { const ev = B.gaps.filter(g => g.s >= 1020).sort((a, b) => (b.e - b.s) - (a.e - a.s))[0]; nowLabel = 'Tomorrow'; nowTitle = dayT.length ? `${dayT.length} ${dayT.length > 1 ? 'tasks' : 'task'} planned` : ev ? `Open ${fmt(ev.s)} → ${fmt(ev.e)}` : 'Nothing planned'; }
    Object.assign(V, { nowLabel, nowTitle, nowMeta });
    const doneN = dayT.filter(t => t.done).length;
    V.odoN = isT ? doneN : dayT.length; V.odoY = `translateY(-${(isT ? doneN : dayT.length) * 1.1}em)`; V.odoDen = isT ? `/ ${dayT.length}` : ''; V.odoLabel = isT ? 'DONE' : 'PLANNED';
    V.odoAria = isT ? `${doneN} of ${dayT.length} done` : `${dayT.length} planned`;
    V.segCount = Math.max(1, dayT.length); V.segs = dayT.length ? dayT.map((t, i) => ({ t:(isT ? t.done : true) ? 'scaleX(1)' : 'scaleX(0)', c:CAT[t.cat].c, d:`${i * 40}ms` })) : [{ t:'scaleX(0)', c:'var(--ln)', d:'0ms' }];
    const cap = capOf(dd, R, visT, isT ? now : 0), cs = Math.max(cap.avail, cap.planned, 1), pc = m => (m / cs * 100).toFixed(2) + '%';
    V.capPlanned = dur(cap.planned); V.capReal = dur(cap.real);
    let acc = 0; V.capSegs = [];
    cap.segs.forEach(g => { const a = acc, b = acc + g.m; acc = b; const c = CAT[g.cat].c;
      if (a < cap.real) V.capSegs.push({ l:pc(a), w:pc(Math.min(b, cap.real) - a), bg:c });
      if (b > cap.real) V.capSegs.push({ l:pc(Math.max(a, cap.real)), w:pc(b - Math.max(a, cap.real)), bg:`repeating-linear-gradient(135deg,${c} 0 2px,transparent 2px 5px)` }); });
    while (V.capSegs.length < 6) V.capSegs.push({ l:pc(Math.min(acc, cs)), w:'0%', bg:'transparent' });
    const z0 = cap.real, z1 = z0 + cap.brk, z2 = z1 + cap.buffer;
    V.capZones = [{ l:pc(z0), w:pc(cap.brk), bg:'var(--s2)' }, { l:pc(z1), w:pc(cap.buffer), bg:'repeating-linear-gradient(90deg,var(--t3) 0 1px,transparent 1px 3px)' }, { l:pc(z2), w:pc(Math.max(0, cap.avail - z2)), bg:'repeating-linear-gradient(135deg,var(--t3) 0 1px,transparent 1px 4px)' }];
    V.capRealX = pc(cap.real);
    V.capLegend = [['AVAILABLE', cap.avail], ['PROTECTED', cap.prot], ['BREAKS', cap.brk], ['BUFFER', cap.buffer]].map(([k, v]) => ({ k, v:dur(v) }));
    V.capAria = `${dur(cap.planned)} planned of ${dur(cap.real)} realistic. ${cap.over > 0 ? dur(cap.over) + ' over.' : ''} Show how this is worked out.`;
    V.capOpen = s.capOpen; V.capToggle = () => this.setState(x => ({ capOpen:!x.capOpen })); V.capChev = s.capOpen ? 'rotate(180deg)' : 'none';
    const protNames = B.base.filter(x => x.k === 'prot' && x.e > (isT ? now : 0)).map(x => x.title).join(', ') || 'None left';
    V.capRows = [
      { k:'Available', v:dur(cap.avail), d:isT ? 'Outside fixed commitments, from now' : 'Outside fixed commitments', sign:'', w:'400' },
      { k:'Protected', v:dur(cap.prot), d:protNames, sign:'−', w:'400' },
      { k:'Breaks', v:dur(cap.brk), d:'15 minutes after any block of 2 hours or more', sign:'−', w:'400' },
      { k:'Buffer', v:dur(cap.buffer), d:'Room for things that run over', sign:'−', w:'400' },
      { k:'Realistic', v:dur(cap.real), d:dd % 7 >= 5 ? 'Capped at 6h on weekends until Planner knows your pace' : 'What Planner will schedule into', sign:'=', w:'600' }];
    const placing = B.ts.some(t => s.place[t.id] === 'hidden' || s.place[t.id] === 'staged');
    V.showOver = cap.over > 15 && !s.overAck[dd] && !placing && !s.winLit;
    const ot = this.overTaskOf(dd);
    V.overText = dd % 7 >= 5 ? `This is ${dur(cap.over)} more than a comfortable weekend day.` : `This is ${dur(cap.over)} more than fits before your wind-down.`;
    V.overBtn = ot ? `Move ${ot.title.split(' ').slice(-1)[0]}` : 'Move one'; V.moveOver = () => this.moveOver(dd); V.keepOver = () => this.keepOver(dd);
    const missedList = isT ? dayT.filter(t => !t.done && t.e <= now && !s.missDismiss[t.id]) : [];
    V.showMissed = missedList.length > 0 && !V.showOver;
    V.missedText = missedList.length > 1 ? `${missedList.length} tasks didn’t happen.` : missedList.length ? `${missedList[0].title} didn’t happen.` : '';
    V.missedGo = () => missedList[0] && this.openMissed(missedList[0].id);
    V.missedLater = () => this.setState(x => { const m = { ...x.missDismiss }; missedList.forEach(t => { m[t.id] = true; }); return { missDismiss:m }; });
    V.offline = !s.online; V.offlineInfo = () => this.say('Offline. Everything is saved on this phone and backs up when you reconnect.');
    V.openCreate = () => this.openCreate({ date:dd });
    V.addLabel = 'Add task';

    /* window highlight during placement */
    const wIds = s.winIds.filter(id => Lmap[id]);
    let winTop = 0, winH = 0, winRange = '';
    if (wIds.length) { const rs = wIds.map(id => Lmap[id]); const br = L.filter(x => x.k === 'break' && wIds.includes(x.parent));
      const all = rs.concat(br); winTop = Math.min(...all.map(x => x.y)) - 4; winH = Math.max(...all.map(x => x.y + x.h)) - winTop + 4;
      const g0 = Math.min(...rs.map(x => x.s)), g1 = Math.max(...rs.map(x => x.e), ...br.map(x => x.e)); winRange = `${fmt(g0)} → ${fmt(g1)}`; }
    V.winShow = s.winLit && wIds.length > 0; V.winTop = winTop + 'px'; V.winH = winH + 'px'; V.winRange = winRange; V.scanning = s.scanning; V.scanY = (winH - 2) + 'px';
    V.winLabelO = wIds.some(id => s.place[id] === 'hidden' || s.place[id] === 'staged') ? '1' : '0';

    const evGap = B.gaps.filter(g => g.e > (isT ? now : 0)).sort((a, b) => (b.e - b.s) - (a.e - a.s))[0];
    V.rows = L.filter(x => x.k !== 'task').map(it => {
      const d0 = it.e - it.s, past = isT && it.e <= now && it.k !== 'marker';
      const parentHidden = it.k === 'break' && (s.place[it.parent] === 'hidden' || s.place[it.parent] === 'staged');
      const r = { title:it.title, top:it.y + 'px', height:it.h + 'px', time:it.k === 'break' ? '' : fmt(it.s), labelPad:it.k === 'marker' ? '8px' : it.h < 50 ? '12px' : '10px',
        isFixed:it.k === 'fixed', isProt:it.k === 'prot', isBreak:it.k === 'break', isOpen:it.k === 'open', isMarker:it.k === 'marker',
        op:parentHidden ? '0' : past ? '0.5' : '1', durL:dur(d0), range:`${fmt(it.s)} → ${fmt(it.e)}`,
        fixedMeta:d0 > 90 ? `${fmt(it.s)} → ${fmt(it.e)}  ${dur(d0)}` : dur(d0), fbg:it.k === 'fixed' ? tint(it.cat, dark ? 0.26 : 0.2) : 'transparent',
        fsq:it.cat ? CAT[it.cat].c : 'transparent', empty:false, openLabel:`Open ${dur(d0)}`, openLabelO:s.winLit ? '0' : '1' };
      if (it.k === 'open') { r.empty = dayT.length === 0 && evGap && evGap.id === it.id && it.h >= 110 && !s.winLit; if (r.empty) r.openLabelO = '0'; if (s.winLit && wIds.length) r.time = ''; }
      if (it.k === 'prot' && it.h < 34) r.labelPad = '9px';
      return r;
    });
    const swp = s.sweeping;
    V.tblocks = eff.map(t => {
      const it = Lmap[t.id], lv = s.leaving[t.id], pl = s.place[t.id], C = CAT[t.cat] || CAT.self;
      if (it && pl !== 'hidden' && pl !== 'staged') this.lastTop[t.id] = { y:it.y, h:it.h };
      const cache = this.lastTop[t.id] || { y:0, h:44 };
      const ph = swp[t.id], vDone = t.done && ph !== 'pre' && ph !== 'a';
      const missed = isT && !t.done && t.e <= now;
      const isCur = cur && cur.id === t.id, isNext = next && next.id === t.id;
      const staged = pl === 'hidden' || pl === 'staged';
      const full = (isCur || isNext) && !vDone && !missed && !staged;
      let top = cache.y, h = cache.h, op = '0', tf = 'none', pe = 'none', inset = '0px', z = '2';
      if (it) { top = it.y; h = it.h; op = '1'; pe = 'auto';
        if (staged) { top = winTop + 12; h = 44; inset = '16%'; op = pl === 'hidden' ? '0' : '1'; tf = pl === 'hidden' ? 'translateY(-10px) scale(.92)' : 'none'; pe = 'none'; z = '3'; } }
      else if (lv) { top = lv.y; h = lv.h; op = lv.ph === 'lift' ? '1' : '0'; tf = lv.ph === 'lift' ? 'scale(1.02)' : 'translate(96px,-40px) scale(.5)'; z = '4'; }
      const tall = h >= 60, fr = s.fresh[t.id];
      const ovMin = Math.max(0, Math.min(t.e, R.sleep) - Math.max(t.s, R.sleep - 30));
      return { top:top + 'px', height:h + 'px', op, tf, pe, z, inset, title:t.title,
        time:fmt(t.s), timeC:full ? 'var(--tx)' : 'var(--t3)', timeO:staged || !it ? '0' : '1', labelPad:h < 50 ? '14px' : '12px',
        bg:vDone ? 'var(--bg)' : missed ? 'transparent' : full ? C.c : tint(t.cat),
        ring:vDone ? 'inset 0 0 0 1px var(--ln)' : staged || fr ? `inset 0 0 0 1.5px ${C.c}` : 'none',
        dashO:missed ? '1' : '0', under:tint(t.cat), underC:C.c,
        titleC:vDone ? 'var(--t3)' : missed ? 'var(--t2)' : full ? C.ink : 'var(--tx)', subC:full ? hexA(C.ink, 0.78) : 'var(--t3)',
        deco:vDone ? 'line-through' : 'none', sq:C.c, sqO:full ? '0' : vDone ? '0.45' : '1', sqW:full ? '0px' : '8px',
        chip:isCur && !vDone ? 'NOW' : isNext && !vDone ? 'NEXT' : missed ? 'MISSED' : t.recur ? 'REPEATS' : '', chipC:full ? C.ink : 'var(--t2)',
        tall, short:!tall, align:tall ? 'flex-start' : 'center', padTop:tall ? '11px' : '0px', range:`${fmt(t.s)} → ${fmt(t.e)}`, durL:dur(t.e - t.s),
        elapsedW:isCur && full ? `${clamp((now - t.s) / (t.e - t.s) * 100, 0, 100)}%` : '0%',
        sweep:ph === 'a' || ph === 'b' ? 'scaleX(1)' : 'scaleX(0)', sweepO:ph === 'a' ? '0.9' : '0', sweepBg:full ? 'rgba(255,255,255,.34)' : C.c,
        checkBg:vDone ? 'var(--t2)' : 'transparent', checkBorder:vDone ? 'var(--t2)' : full ? C.ink : 'var(--t3)', checkDash:vDone ? '0' : '12', checkScale:ph === 'a' ? 'scale(1.18)' : 'scale(1)',
        checkShow:isT && !missed && !staged, checkO:isT && !missed && !staged ? '1' : '0', btnH:tall ? '48px' : '44px',
        ovH:!vDone && ovMin > 0 ? (h * ovMin / (t.e - t.s)) + 'px' : '0px', ovC:full ? 'rgba(255,255,255,.35)' : hexA(C.c, 0.6), ovLab:ovMin >= 20 && !vDone ? 'WIND-DOWN' : '',
        aria:`${t.title}, ${fmt(t.s)} to ${fmt(t.e)}${vDone ? ', done' : missed ? ', missed' : ''}. Open details.`, checkAria:vDone ? `Mark ${t.title} not done` : `Complete ${t.title}`,
        onCheck:e => { e.stopPropagation(); this.toggle(t.id); }, onOpen:() => this.openBlock(t.id),
        onDown:e => { if (e.target.closest && e.target.closest('.chk')) return; this.swDown(e, t.id); }, onMove:e => this.swMove(e), onUp:() => { if (this.sw && this.sw.active) this.swJust = true; this.swUp(); } };
    });
    V.tlH = (B.height + 10) + 'px';
    V.showNow = isT && s.tab === 'today'; V.nowTop = this.nowY(L, now) + 'px'; V.clock = fmt(now); V.pulseO = s.voice !== 'idle' ? '0' : '1';
    const dp = s.dayPhase;
    V.dayO = dp === 'in' ? '1' : '0'; V.dayT = dp === 'outL' || dp === 'preL' ? 'translateX(-22px)' : dp === 'outR' || dp === 'preR' ? 'translateX(22px)' : 'none'; V.dayF = dp === 'in' ? 'blur(0px)' : 'blur(calc(var(--bl,1) * 5px))';
    V.stripO = s.view === 'strip' ? '1' : '0'; V.stripPE = s.view === 'strip' ? 'auto' : 'none'; V.stripT = s.view === 'strip' ? 'none' : 'scale(.97)';
    V.dialO = s.view === 'dial' ? '1' : '0'; V.dialPE = s.view === 'dial' ? 'auto' : 'none'; V.dialT = s.view === 'dial' ? 'none' : 'scale(.9) rotate(-8deg)';

    /* dial */
    const cx = 160, R0 = 128, arcs = [];
    const arcOf = (m0, m1, r) => ({ d:arcD(cx, cx, r, m0, m1), len:r * (m1 - m0) / 1440 * TAU });
    const di = i => `calc(var(--m,1) * ${i * 45}ms)`;
    const slA = arcOf(Math.max(0, R.sleep - 1440), R.wake, R0);
    arcs.push({ d:slA.d, c:'var(--t3)', w:2, da:'2 6', dof:'0', o:'0.8', pe:'none', onClick:null, dl:'0ms', lab:'' });
    if (R.sleep < 1440) { const slB = arcOf(R.sleep, 1440, R0); arcs.push({ d:slB.d, c:'var(--t3)', w:2, da:'2 6', dof:'0', o:'0.8', pe:'none', onClick:null, dl:'0ms', lab:'' }); }
    L.forEach((it, i) => {
      if (it.k === 'marker' || it.k === 'break') return;
      const a = arcOf(it.s + 3, it.e - 3, R0), da = `${a.len.toFixed(1)} 2000`, dof = s.dialIn ? '0' : a.len.toFixed(1);
      if (it.k === 'fixed') arcs.push({ d:a.d, c:tint(it.cat, 0.55), w:8, da, dof, o:'1', pe:'none', onClick:null, dl:di(i), lab:'' });
      else if (it.k === 'prot') arcs.push({ d:a.d, c:'var(--t3)', w:2, da:s.dialIn ? '1 3' : da, dof:'0', o:'0.7', pe:'none', onClick:null, dl:di(i), lab:'' });
      else if (it.k === 'open') arcs.push({ d:a.d, c:'var(--ln)', w:2, da, dof, o:'1', pe:'none', onClick:null, dl:di(i), lab:'' });
      else { const t = it, st = s.place[t.id]; if (st === 'hidden') return; const isN = cur && cur.id === t.id, isX = next && next.id === t.id, missed = isT && !t.done && t.e <= now, sel = s.dialSel === t.id;
        arcs.push({ d:a.d, c:t.done ? 'var(--ln)' : missed ? 'var(--t3)' : isN || isX ? CAT[t.cat].c : tint(t.cat, 0.6), w:sel ? 26 : 20, da:missed ? '3 4' : da, dof:missed ? '0' : dof, o:'1', pe:'stroke', onClick:() => this.setState({ dialSel:t.id }), dl:di(i), lab:t.title }); }
    });
    V.arcs = arcs;
    let ticks = ''; for (let i = 0; i < 24; i++) { const a = i / 24 * TAU - Math.PI / 2, r1 = 146, r2 = i % 6 ? 150 : 154; ticks += `M${(cx + r1 * Math.cos(a)).toFixed(1)} ${(cx + r1 * Math.sin(a)).toFixed(1)}L${(cx + r2 * Math.cos(a)).toFixed(1)} ${(cx + r2 * Math.sin(a)).toFixed(1)}`; }
    V.dialTicks = ticks; V.handRot = `rotate(${now / 1440 * 360}deg)`; V.showHand = isT;
    const selIt = s.dialSel ? dayT.find(x => x.id === s.dialSel) : null;
    const focus = selIt || cur || next || (isT ? null : dayT[0]);
    if (focus) { const miss = isT && !focus.done && focus.e <= now; V.dcLabel = focus.done ? 'DONE' : cur && cur.id === focus.id ? 'NOW' : miss ? 'MISSED' : isT ? 'NEXT' : 'FIRST'; V.dcTitle = focus.title; V.dcMeta = `${fmt(focus.s)} → ${fmt(focus.e)}`; V.dcCanDone = isT && !focus.done && !miss; V.dcCanDecide = miss; V.dcC = CAT[focus.cat].c; }
    else { V.dcLabel = isT ? 'TODAY' : 'TOMORROW'; V.dcTitle = dayT.length ? 'All done' : 'No plans yet'; V.dcMeta = dayT.length ? `${doneN} of ${dayT.length}` : 'Tap the orb'; V.dcCanDone = false; V.dcCanDecide = false; V.dcC = 'var(--tx)'; }
    V.dcDone = () => focus && this.toggle(focus.id); V.dcDecide = () => focus && this.openMissed(focus.id);
    V.upNext = dayT.filter(x => !isT || x.e > now).slice(0, 4).map(x => ({ title:x.title, range:`${fmt(x.s)} → ${fmt(x.e)}`, c:x.done ? 'var(--t3)' : 'var(--tx)', deco:x.done ? 'line-through' : 'none', sq:CAT[x.cat].c, open:() => this.openBlock(x.id) }));
    V.upNextEmpty = V.upNext.length === 0;

    /* ===== plan ===== */
    const G = this.geo(), K = G.K, HB = G.HB, BH = G.BH, yOf = m => HB + (clamp(m, 360, 1440) - 360) * K;
    const dragP = s.drag ? ripple(eff, s.drag.id, s.drag.day, s.drag.s, R) : eff;
    V.segs4 = [['today', 'Today'], ['tomorrow', 'Tomorrow'], ['week', 'Week'], ['upcoming', 'Upcoming']].map(([k, t]) => ({ t, c:s.planSeg === k ? 'var(--tx)' : 'var(--t3)', go:() => this.setSeg(k), pressed:String(s.planSeg === k) }));
    V.seg4X = `translateX(${['today', 'tomorrow', 'week', 'upcoming'].indexOf(s.planSeg) * 100}%)`;
    V.isUp = s.planSeg === 'upcoming'; V.boardO = V.isUp ? '0' : '1'; V.boardPE = V.isUp ? 'none' : 'auto'; V.upO = V.isUp ? '1' : '0'; V.upPE = V.isUp ? 'auto' : 'none';
    V.planTitle = s.planSeg === 'week' ? 'This week' : s.planSeg === 'upcoming' ? 'Upcoming' : dayLabel(G.sel);
    V.planSub = s.planSeg === 'week' ? '28 Sep → 4 Oct' : '';
    V.axis = [360, 540, 720, 900, 1080, 1260, 1440].map(m => ({ y:(yOf(m) - 6) + 'px', t:fmt(m).slice(0, 2) === '00' ? '24' : fmt(m).slice(0, 2) }));
    const hoverD = s.drag ? s.drag.day : -1;
    V.cols = [0, 1, 2, 3, 4, 5, 6].map(d => {
      const exp = d === G.sel, c0 = capOf(d, R, dragP, 0), tot = c0.planned + c0.done, over = tot - c0.real, bw = Math.max(4, G.ws[d] - (exp ? 8 : 6));
      const sc = Math.max(tot, c0.real, 1);
      return { x:G.xs[d] + 'px', w:G.ws[d] + 'px', bg:exp ? 'var(--s1)' : hoverD === d ? 'var(--s1)' : 'transparent', o:d < today ? '0.62' : '1',
        letter:DAY1[d], date:String(dnum(d)), full:`${DAYN[d]} ${dnum(d)}`, exp, expO:exp ? '1' : '0', cmpO:exp ? '0' : G.c < 20 ? '0' : '1', tinyO:!exp && G.c < 20 ? '1' : '0',
        hc:d === today ? 'var(--tx)' : 'var(--t2)', hw:d === today ? '600' : '500', todayLine:d === today ? '1' : '0',
        bw:bw + 'px', bx:(exp ? 4 : (G.ws[d] - bw) / 2) + 'px', fillW:(Math.min(tot, c0.real) / sc * bw) + 'px', overL:(c0.real / sc * bw) + 'px', overW:(Math.max(0, over) / sc * bw) + 'px', markL:(c0.real / sc * bw - 1) + 'px',
        capText:over > 15 ? `+${dur(over)}` : `${dur(tot)} / ${dur(c0.real)}`, capC:over > 15 ? 'var(--tx)' : 'var(--t3)',
        aria:`${DAYL[d]} ${dnum(d)} ${dmon(d)}. ${dur(tot)} planned of ${dur(c0.real)} realistic.${over > 15 ? ' Over by ' + dur(over) + '.' : ''}`, go:() => this.selDay(d) };
    });
    V.bands = [];
    for (let d = 0; d < 7; d++) baseItems(d, R).forEach(x => { if (x.k === 'marker' || x.e <= 360) return; const exp = d === G.sel, y = yOf(x.s), h = Math.max(2, yOf(x.e) - y - 1);
      V.bands.push({ x:(G.xs[d]) + 'px', w:G.ws[d] + 'px', y:y + 'px', h:h + 'px', bg:x.k === 'fixed' ? tint(x.cat, dark ? 0.3 : 0.24) : 'repeating-linear-gradient(135deg,var(--ln) 0 1px,transparent 1px 5px)',
        lab:exp && h >= 16 ? x.title : '', meta:exp && h >= 30 ? `${fmt(x.s)} → ${fmt(x.e)}` : '', labO:exp ? '1' : '0', o:d < today ? '0.62' : '1' }); });
    const sel = G.sel, selB = buildDay(sel, R, dragP);
    V.bgaps = selB.gaps.filter(g => g.e > 360 && g.e - g.s >= 40 && !(sel === today && g.e <= now)).map(g => { const a = sel === today ? Math.max(g.s, ceil5(now)) : g.s, y = yOf(a), h = yOf(g.e) - y - 2; return { x:(G.xs[sel] + 3) + 'px', w:(G.ws[sel] - 6) + 'px', y:y + 'px', h:Math.max(0, h) + 'px', lab:h >= 18 ? `${dur(g.e - a)} free` : '' }; }).filter(g => parseFloat(g.h) > 8);
    V.dls = s.deadlines.filter(x => x.day >= 0 && x.day < 7).map(x => { const exp = x.day === sel; return { x:G.xs[x.day] + 'px', w:G.ws[x.day] + 'px', y:(yOf(x.m) - 1) + 'px', lab:exp ? `Due ${fmt(x.m)}, ${x.title.replace(/ due$/, '')}` : '', labO:exp ? '1' : '0' }; });
    const dragId = s.drag ? s.drag.id : null;
    V.wt = eff.map(t0 => {
      const t = dragP.find(x => x.id === t0.id) || t0, ok = live(t) && t.day >= 0 && t.day < 7, C = CAT[t.cat] || CAT.self;
      if (!ok) return { x:'0px', y:'0px', w:'0px', h:'0px', op:'0', pe:'none', bg:'transparent', r:'2px', z:'1', tf:'none', tr:'none', title:'', time:'', txO:'0', titleC:'var(--tx)', subC:'var(--t3)', rec:'', ring:'none', dashO:'0', aria:'', onDown:null, onMove:null, onUp:null, onOpen:null };
      const exp = t.day === sel, d = t.day;
      const missed = !t.done && (d < today || (d === today && t.e <= now));
      const isN = d === today && !t.done && now >= t.s && now < t.e;
      const nx = d === today && next && next.id === t.id;
      const fullC = t.done || isN || nx;
      let x, w, y = yOf(t.s), h = Math.max(3, yOf(t.e) - y - 1), r = exp ? '3px' : '2px';
      if (exp) { x = G.xs[d] + 3; w = G.ws[d] - 6; } else { const lw = G.mode === 'week' ? 4 : 3; x = G.xs[d] + G.ws[d] / 2 - lw / 2; w = lw; }
      let tf = 'none', tr = 'left calc(var(--m,1) * 560ms) cubic-bezier(.34,1.3,.55,1), top calc(var(--m,1) * 560ms) cubic-bezier(.34,1.3,.55,1), width calc(var(--m,1) * 520ms) cubic-bezier(.2,.8,.2,1), height calc(var(--m,1) * 560ms) cubic-bezier(.34,1.3,.55,1), background calc(var(--m,1) * 300ms) ease', z = exp ? '3' : '2';
      if (dragId === t.id) { const o = eff.find(q => q.id === t.id); const oy = yOf(o.s); x = G.xs[o.day] + 3 + s.drag.dx; w = G.ws[o.day] - 6; y = oy + s.drag.dy; h = Math.max(3, yOf(o.e) - oy - 1); tf = 'scale(1.03)'; tr = 'transform 160ms cubic-bezier(.3,0,.2,1)'; z = '20'; r = '3px'; }
      const bg = missed ? 'transparent' : fullC ? C.c : exp ? tint(t.cat, dark ? 0.28 : 0.22) : mixHex(N.bg, C.c, 0.55);
      const txt = exp || dragId === t.id;
      return { x:x + 'px', y:y + 'px', w:w + 'px', h:h + 'px', op:'1', pe:exp ? 'auto' : 'none', bg, r, z, tf, tr,
        title:t.title, time:h >= 30 ? `${fmt(t.s)} → ${fmt(t.e)}` : '', txO:txt && h >= 13 ? '1' : '0', titleC:fullC && !missed ? C.ink : missed ? 'var(--t2)' : 'var(--tx)', subC:fullC && !missed ? hexA(C.ink, 0.75) : 'var(--t3)',
        ring:dragId === t.id ? 'inset 0 0 0 1.5px var(--tx)' : s.fresh[t.id] ? `0 0 0 2px ${C.c}` : 'none', dashO:missed ? '1' : '0', rec:t.recur ? ' ↻' : '',
        aria:`${t.title}, ${DAYL[d % 7]} ${fmt(t.s)} to ${fmt(t.e)}${t.done ? ', done' : missed ? ', missed' : ''}. Drag to move, or open.`,
        onDown:e => this.wDown(e, t.id), onMove:e => this.wMove(e), onUp:() => { if (this.wd && this.wd.active) this.wdJust = true; this.wUp(); }, onOpen:() => this.openBoard(t.id) };
    });
    if (s.drag) { const p = dragP.find(x => x.id === s.drag.id), C = CAT[p.cat]; const gy = yOf(p.s);
      V.ghost = { x:(G.xs[p.day] + 3) + 'px', w:(G.ws[p.day] - 6) + 'px', y:gy + 'px', h:Math.max(4, yOf(p.e) - gy - 1) + 'px', c:C.c, lab:`${dayShort(p.day)} ${fmt(p.s)} → ${fmt(p.e)}`, ly:Math.max(0, gy - 22) + 'px', lx:Math.min(G.xs[p.day], 368 - 130) + 'px' }; }
    else V.ghost = { x:'0px', w:'0px', y:'0px', h:'0px', c:'transparent', lab:'', ly:'0px', lx:'0px' };
    V.showGhost = !!s.drag;
    V.nowLineShow = today >= 0 && today < 7 && now >= 360; V.nowLineX = G.xs[today] + 'px'; V.nowLineW = G.ws[today] + 'px'; V.nowLineY = yOf(now) + 'px';
    V.scans = s.recalc ? [...new Set(s.recalc.days)].filter(d => d >= 0 && d < 7).map(d => ({ x:G.xs[d] + 'px', w:G.ws[d] + 'px' })) : [];
    V.scanH = (BH - 2) + 'px'; V.boardH = (HB + BH + 8) + 'px';
    const weekTasks = eff.filter(t => live(t) && t.day >= 0 && t.day < 7);
    V.weekEmpty = weekTasks.length === 0 && !V.isUp;
    const sc0 = capOf(sel, R, dragP, 0), stot = sc0.planned + sc0.done;
    V.selTitle = dayLabel(sel); V.selMeta = `${dur(stot)} planned of ${dur(sc0.real)} realistic`;
    V.selOver = sc0.over > 15 && !s.overAck['w' + sel] && sel >= today; V.selOverText = `${DAYL[sel % 7]} runs ${dur(sc0.over)} past what fits. Move one block to a lighter day?`;
    V.selMove = () => this.moveOverGeneric(sel); V.selKeep = () => this.setState(x => ({ overAck:{ ...x.overAck, ['w' + sel]:true } }));
    V.selAdd = () => this.openCreate({ date:sel });
    V.isDayMode = G.mode === 'day';
    V.inbox = s.tasks.filter(t => t.day == null && !t.deleted).map(t => ({ title:t.title, meta:dur(t.dur), sq:CAT[t.cat].c, fit:() => this.fitIn(t.id), aria:`Fit ${t.title} into the next free slot` }));
    V.inboxEmpty = V.inbox.length === 0;
    const upDl = s.deadlines.concat(s.upcoming).filter(x => x.day >= today).sort((a, b) => a.day - b.day).map(x => ({ title:x.title.replace(/ due$/, ''), when:`${DAYN[x.day % 7]} ${dnum(x.day)} ${dmons(x.day)}`, sub:x.note || (x.m ? `Due ${fmt(x.m)}` : ''), sq:CAT[x.cat].c, inD:x.day - today === 0 ? 'Today' : x.day - today === 1 ? 'Tomorrow' : `In ${x.day - today} days` }));
    V.upDeadlines = upDl; V.upHasDl = upDl.length > 0;
    V.upRecur = R.commits.filter(c => c.on).map(c => ({ title:c.title, rule:c.label, sq:CAT[c.cat].c, fresh:'0' })).concat(s.series.map(q => ({ title:q.title, rule:`${q.rule}, ${fmt(q.s)} → ${fmt(q.e)}`, sq:CAT[q.cat].c, fresh:'1' })));
    V.upHasRecur = V.upRecur.length > 0;
    V.upEmpty = !V.upHasDl && !V.upHasRecur && V.inboxEmpty;

    /* ===== progress ===== */
    const wc = s.weekComplete, pk = s.pk;
    const incl = s.ribAll ? CATS : CATS.filter(c => c !== 'work');
    let data = {}, env = [];
    if (wc) { data = WMOCK; env = WENV.slice(); }
    else {
      CATS.forEach(c => { data[c] = [0, 0, 0, 0, 0, 0, 0]; });
      s.tasks.forEach(t => { if (t.done && t.day >= 0 && t.day < 7 && !t.deleted) data[t.cat][t.day] += (t.e - t.s) / 60; });
      for (let d = 1; d < 7; d++) { const past = d < today || d === today; if (!past) continue; baseItems(d, R).forEach(x => { if (x.k !== 'fixed') return; const m = d < today ? x.e - x.s : Math.max(0, Math.min(x.e, now) - x.s); data[x.cat][d] += m / 60; }); }
      env = [0, 1, 2, 3, 4, 5, 6].map(d => { if (d === 0) return 0; const tp = s.tasks.filter(t => t.day === d && live(t)).reduce((a, t) => a + (t.e - t.s) / 60, 0); const rest = baseItems(d, R).filter(x => x.k === 'fixed' && x.cat !== 'work').reduce((a, x) => a + (x.e - x.s) / 60, 0); return d <= today ? tp + rest : 0; });
    }
    const envI = env.map((e, d) => e + (s.ribAll ? data.work[d] : 0));
    const tot = [0, 1, 2, 3, 4, 5, 6].map(d => incl.reduce((a, c) => a + data[c][d], 0));
    const maxE = Math.max(1, ...envI, ...tot), RW = 360, RH = 196, mid = 98, rs = 170 / maxE, xs = d => 14 + d * (332 / 6);
    const cursor = tot.map(v => mid - v * rs / 2);
    V.ribbon = incl.map(c => { const top = [], bot = []; for (let d = 0; d < 7; d++) { const y0 = cursor[d], y1 = y0 + data[c][d] * rs; top.push([xs(d), y0]); bot.push([xs(d), y1]); cursor[d] = y1; }
      const br = bot.slice().reverse(); const d = smoothPath(top) + ' L' + br[0][0].toFixed(1) + ' ' + br[0][1].toFixed(1) + smoothPath(br).replace(/^M[^C]*/, '') + ' Z';
      const hl = s.ribSel == null || data[c][s.ribSel] > 0;
      return { d, c:CAT[c].c, o:hl ? '0.94' : '0.35' }; });
    V.envTop = smoothPath(envI.map((e, d) => [xs(d), mid - e * rs / 2])); V.envBot = smoothPath(envI.map((e, d) => [xs(d), mid + e * rs / 2]));
    V.ribClip = s.ribOn ? 'inset(0 0% 0 0)' : 'inset(0 100% 0 0)';
    V.ribDays = [0, 1, 2, 3, 4, 5, 6].map(d => { const on = s.ribSel === d; const pct = env[d] > 0 ? Math.round(Math.min(1, tot[d] / (envI[d] || 1)) * 100) : null;
      return { x:(xs(d) - 22) + 'px', l:DAY1[d], n:String(dnum(d)), c:on ? 'var(--tx)' : 'var(--t3)', w:on ? '600' : '500', pick:() => this.setState(x => ({ ribSel:x.ribSel === d ? null : d })), aria:`${DAYL[d]}: ${hrs(tot[d])} tracked` }; });
    V.ribSelX = s.ribSel != null ? (xs(s.ribSel) - 0.5) + 'px' : '-10px'; V.ribSelO = s.ribSel != null ? '1' : '0';
    V.ribAll = s.ribAll; V.ribToggle = () => this.setState(x => ({ ribAll:!x.ribAll })); V.ribAllLabel = s.ribAll ? 'Everything' : 'Your time';
    V.ribAllThumb = s.ribAll ? 'translateX(100%)' : 'translateX(0)'; V.ribMineC = s.ribAll ? 'var(--t3)' : 'var(--tx)'; V.ribEvC = s.ribAll ? 'var(--tx)' : 'var(--t3)';
    V.ribMine = () => this.setState({ ribAll:false }); V.ribEv = () => this.setState({ ribAll:true });
    const catTot = incl.map(c => ({ c, h:data[c].reduce((a, v) => a + v, 0) })).filter(x => x.h > 0).sort((a, b) => b.h - a.h);
    const focusH = ['study', 'build', 'self'].reduce((a, c) => a + data[c].reduce((q, v) => q + v, 0), 0);
    if (s.ribSel == null) { V.ribHead = wc ? 'Where your week went' : 'Where your week is going'; V.ribLegend = catTot.map(x => ({ n:CAT[x.c].n, v:hrs(x.h), sq:CAT[x.c].c })); }
    else { const d = s.ribSel; V.ribHead = d === 0 && !wc ? 'Monday, before Planner' : `${DAYL[d]}, ${hrs(tot[d])}`; V.ribLegend = incl.filter(c => data[c][d] > 0).sort((a, b) => data[b][d] - data[a][d]).map(c => ({ n:CAT[c].n, v:hrs(data[c][d]), sq:CAT[c].c })); }
    V.ribLegendEmpty = V.ribLegend.length === 0;
    const allT = s.tasks.filter(t => t.day != null && t.day >= 0 && t.day < 7 && !t.deleted && t.day <= today);
    const st = wc ? { planned:24, done:19, resched:4, skipped:2, carried:1, days:6 } : { planned:allT.filter(t => !t.skipped).length, done:allT.filter(t => t.done).length, resched:allT.filter(t => t.moved).length, skipped:allT.filter(t => t.skipped).length, carried:0, days:Math.max(1, today) };
    V.pDone = String(Math.round(st.done * pk)); V.pPlanned = String(st.planned); V.pHas = st.planned > 0;
    V.pPct = st.planned ? `${Math.round(st.done / st.planned * 100 * pk)}%` : '0%'; V.pFocus = dur(focusH * 60 * pk); V.pDays = String(Math.round(st.days * pk));
    V.pMoved = [['Rescheduled', st.resched], ['Skipped', st.skipped], ['Carried forward', st.carried]].map(([k, v]) => ({ k, v:String(Math.round(v * pk)) }));
    V.pHero = st.planned ? 'planned tasks done' : 'Your first week has started.';
    V.pSubline = wc ? 'Most of the unfinished time was Saturday. Everything else landed.' : st.planned ? 'The ribbon fills in as the week happens.' : 'Tell Planner what you want to accomplish. The ribbon fills in as you do it.';
    V.heat = DAYN.map((dn, r) => ({ d:DAY1[r], cells:Array.from({ length:36 }, (_, c) => { const lv = wc && r > 0 ? HEATF(r, c) : 0; const on = s.heatSel && s.heatSel.r === r && s.heatSel.c === c;
      return { bg:lv ? 'var(--tx)' : 'var(--s1)', o:s.heatOn ? String(lv ? [0, 0.18, 0.36, 0.62, 1][lv] : 1) : '0', t:s.heatOn ? 'scale(1)' : 'scale(.3)', d:`calc(var(--m,1) * ${(r + c) * 11}ms)`, sh:on ? '0 0 0 1.5px var(--tx)' : 'none', pick:() => this.setState({ heatSel:{ r, c } }) }; }) }));
    V.heatInfo = !wc ? 'Your rhythm appears here after a few days of use.' : s.heatSel ? (() => { const lv = s.heatSel.r > 0 ? HEATF(s.heatSel.r, s.heatSel.c) : 0, m = 360 + s.heatSel.c * 30; return `${DAYN[s.heatSel.r]} ${fmt(m)} → ${fmt(m + 30)}: ${[0, 8, 15, 22, 30][lv]}m focused`; })() : 'Most productive 20:30 → 22:30, five days out of six';
    V.heatBracketO = wc && s.heatOn ? '1' : '0';
    V.canReview = wc; V.openReview = () => this.openReview();
    V.progRange = '28 Sep → 4 Oct';

    /* ===== tabs, nav ===== */
    const tab = s.tab, inSet = s.settings;
    const pane = k => { const on = tab === k && !inSet; const idx = ['today', 'plan', 'progress'].indexOf(k), ci = ['today', 'plan', 'progress'].indexOf(tab);
      return { x:on ? 'none' : `translateX(${idx < ci ? '-24%' : '24%'})`, o:on ? '1' : '0', f:on ? 'blur(0px)' : 'blur(calc(var(--bl,1) * 8px))', pe:on ? 'auto' : 'none' }; };
    V.pToday = pane('today'); V.pPlan = pane('plan'); V.pProg = pane('progress');
    V.nav = [['today', 'Today'], ['plan', 'Plan']].map(([k, t]) => ({ t, c:tab === k && !inSet ? 'var(--tx)' : 'var(--t3)', bar:tab === k && !inSet ? 'scaleX(1)' : 'scaleX(0)', go:() => this.goTab(k), cur:tab === k && !inSet ? 'page' : 'false', bump:k === 'plan' && s.navBump && Date.now() - s.navBump < 700 ? 'scale(1.12)' : 'none' }));
    V.navProgC = tab === 'progress' && !inSet ? 'var(--tx)' : 'var(--t3)'; V.navProgBar = tab === 'progress' && !inSet ? 'scaleX(1)' : 'scaleX(0)'; V.goProgress = () => this.goTab('progress');
    V.navSetC = inSet ? 'var(--tx)' : 'var(--t3)'; V.openSettings = () => this.setState({ settings:!inSet, sPage:'root' });
    V.heyO = tab === 'today' && !inSet && s.wakeOn && s.voice === 'idle' && V.isApp ? '1' : '0';

    /* ===== voice ===== */
    const v = s.voice, open = v !== 'idle';
    V.vO = open ? '1' : '0'; V.vPE = open ? 'auto' : 'none'; V.veilTap = () => this.veilTap();
    const res = s.res;
    V.vLabel = { wake:'HEY PLANNER', listening:'LISTENING', processing:'UNDERSTANDING', result:res ? res.label : '', success:res ? (res.doneLabel || 'DONE') : '', cancelled:'CANCELLED', denied:'MICROPHONE IS OFF' }[v] || '';
    const words = this.words || this.cmdObj().say.split(' '), keys = new Set(this.cmdObj().key);
    V.words = (open && v !== 'denied' ? words : []).map((w, i) => { const sh = i < s.wordN, key = keys.has(w.toLowerCase().replace(/[.,?]/g, ''));
      return { w, c:s.parsed ? (key ? 'var(--tx)' : 'var(--t3)') : 'var(--tx)', fw:s.parsed && key ? '500' : '400', o:sh && !s.showRes && v !== 'cancelled' ? '1' : '0', t:!sh ? 'translateY(10px)' : s.showRes ? 'translateY(-18px)' : 'none', f:sh && !s.showRes ? 'blur(0px)' : 'blur(calc(var(--bl,1) * 6px))', d:s.parsed ? `${i * 22}ms` : '0ms', d2:s.showRes ? `${i * 12}ms` : '0ms' }; });
    V.resRows = s.showRes && res ? (res.rows || []).map((r, i) => ({ t1:r.t1, t2:r.t2, sq:CAT[r.cat] ? CAT[r.cat].c : 'var(--t3)', o:i < s.resN ? '1' : '0', t:i < s.resN ? 'none' : 'translateY(14px)' })) : [];
    V.resHeadO = s.showRes && v !== 'cancelled' ? '1' : '0'; V.resHead = res ? res.label : '';
    V.resSummary = s.showRes && res ? res.summary || '' : ''; V.resSumO = s.showRes && res && res.summary && s.resN >= (res.rows || []).length ? '1' : '0';
    V.resWait = v === 'result' && res && res.wait && s.resN >= (res.rows || []).length; V.resYesL = res ? res.yes || 'Done' : ''; V.resNoL = res && res.no ? res.no : ''; V.resHasNo = !!(res && res.no);
    V.resYes = e => { e.stopPropagation(); this.resYes(); }; V.resNo = e => { e.stopPropagation(); this.resNo(); };
    V.resYesBg = res && res.kind === 'confirm' ? CAT.body.c : 'var(--tx)'; V.resYesC = res && res.kind === 'confirm' ? '#ffffff' : 'var(--bg)';
    V.isDenied = v === 'denied'; V.denyType = e => { e.stopPropagation(); this.denyType(); }; V.denyAllow = e => { e.stopPropagation(); this.denyAllow(); };
    V.vHint = v === 'listening' || v === 'wake' ? (s.micErr ? 'Microphone unavailable. Using the demo voice.' : this.analyser ? 'Your voice shapes the orb. Tap anywhere to cancel.' : 'Tap anywhere to cancel') : v === 'processing' ? 'Tap anywhere to cancel' : V.resWait && res.kind === 'answer' ? 'Tap anywhere to close' : '';
    V.vHintO = V.vHint ? '1' : '0';
    V.orbT = open ? 'translate(0px,-486px) scale(1.1)' : 'translate(0px,0px) scale(0.42)'; V.orbBtnD = open ? 'none' : 'block';
    V.tapOrb = () => this.tapOrb(); V.orbEnter = () => { this.hover = true; }; V.orbLeave = () => { this.hover = false; };
    V.orbAria = s.voice === 'idle' ? 'Talk to Planner' : 'Cancel';

    /* ===== sheets ===== */
    V.sheetOn = !!s.sheet; V.sheetT = s.sheetOpen ? 'translateY(0)' : 'translateY(104%)'; V.scrimO = s.sheetOpen ? '1' : '0'; V.scrimPE = s.sheet ? 'auto' : 'none'; V.closeSheet = () => this.closeSheet();
    V.isDetail = s.sheet === 'detail'; V.isMissed = s.sheet === 'missed'; V.isCreate = s.sheet === 'create';
    const tk = s.sid ? s.tasks.find(x => x.id === s.sid) : null;
    if (tk && tk.day != null) {
      const C = CAT[tk.cat], miss = !tk.done && (tk.day < today || (tk.day === today && tk.e <= now));
      V.dT = tk.title; V.dCat = C.n; V.dSq = C.c; V.dWhen = `${DAYN[tk.day % 7]} ${dnum(tk.day)} ${dmons(tk.day)}`; V.dRange = `${fmt(tk.s)} → ${fmt(tk.e)}`; V.dDur = dur(tk.e - tk.s);
      V.dStatus = tk.done ? `Done at ${fmt(tk.doneAt || tk.e)}` : tk.skipped ? 'Skipped' : miss ? 'Missed' : tk.day === today && now >= tk.s ? 'In progress' : 'Planned';
      V.dRows = [['Deadline', tk.deadline != null ? dayShort(tk.deadline) : 'None'], ['Priority', tk.prio === 'high' ? 'High' : tk.prio === 'low' ? 'Low' : 'Normal'], ['Repeats', tk.recur ? tk.recur : 'Never'], ['Added by', tk.src === 'voice' ? 'Voice' : 'You'], ['Status', V.dStatus]].map(([k, val]) => ({ k, v:val }));
      const same = s.tasks.filter(x => x.title === tk.title && x.day != null && !x.deleted).sort((a, b) => a.day - b.day);
      V.dHist = same.map(x => ({ bg:x.done ? C.c : 'transparent', bd:x.done ? C.c : x.skipped ? 'var(--t3)' : 'var(--ln)', lab:DAY1[x.day % 7], cur:x.id === tk.id ? '1.5px' : '0px' }));
      V.dHistText = same.length > 1 ? `Done ${same.filter(x => x.done).length} of the last ${same.length} times` : 'New on your plan. History builds as it repeats.';
      const dB = buildDay(tk.day, R, eff).seq.filter(x => x.k !== 'marker');
      V.dStrip = dB.map(x => ({ l:((x.s - R.wake) / (R.sleep - R.wake) * 100).toFixed(2) + '%', w:Math.max(0.4, (x.e - x.s) / (R.sleep - R.wake) * 100 - 0.4).toFixed(2) + '%', bg:x.tid === tk.id ? C.c : x.k === 'task' ? tint(x.cat, 0.5) : x.k === 'fixed' ? tint(x.cat, 0.3) : x.k === 'prot' ? 'repeating-linear-gradient(135deg,var(--t3) 0 1px,transparent 1px 4px)' : 'transparent', bd:x.k === 'open' ? '1px dashed var(--ln)' : 'none', h:x.tid === tk.id ? '14px' : '8px' }));
      V.dStripA = fmt(R.wake); V.dStripB = fmt(R.sleep);
      V.dCompleteL = tk.done ? 'Mark not done' : 'Complete'; V.dComplete = () => this.completeFromSheet(tk.id);
      V.dResched = () => this.openMissed(tk.id, 'resched'); V.dSkip = () => this.skipTask(tk.id); V.dEdit = () => this.editTask(tk.id); V.dDel = () => this.delTask(tk.id);
      V.dDelL = s.delArm ? 'Tap again to delete' : 'Delete'; V.dDelC = s.delArm ? CAT.body.c : 'var(--t2)';
      V.dIsMissed = miss; V.dMissed = () => this.openMissed(tk.id);
      const opts = this.reOptions(tk);
      V.mTitle = s.missMode === 'resched' ? 'When should this happen?' : 'What should we do with this?';
      V.mSub = `${tk.title} was planned for ${DAYN[tk.day % 7]} ${fmt(tk.s)} → ${fmt(tk.e)}.`;
      V.mOpts = opts.map(o => ({ label:o.label, text:o.text, c:o.ok ? 'var(--tx)' : 'var(--t3)', c2:o.ok ? 'var(--t2)' : 'var(--t3)', dis:!o.ok, go:() => o.ok && this.reschedTo(tk.id, o.d, o.sl) }));
      V.mPick = s.pickDate; V.mPickToggle = () => this.setState(x => ({ pickDate:!x.pickDate })); V.mPickChev = s.pickDate ? 'rotate(90deg)' : 'none';
      V.mDays = [0, 1, 2, 3, 4, 5, 6].map(i => today + i).map(d => { const sl2 = findSlot(d, tk.e - tk.s, R, s.tasks, { excl:tk.id, after:d === today ? ceil5(now) : 0 }); return { l:DAYN[d % 7], n:String(dnum(d)), t:sl2 ? fmt(sl2.s) : 'Full', c:sl2 ? 'var(--tx)' : 'var(--t3)', dis:!sl2, go:() => sl2 && this.reschedTo(tk.id, d, sl2) }; });
      V.mSkip = () => this.skipTask(tk.id); V.mDel = () => this.delTask(tk.id); V.mDelL = s.delArm ? 'Tap again to delete' : 'Delete'; V.mDelC = s.delArm ? CAT.body.c : 'var(--t2)';
      V.mSkipL = tk.recur ? 'Skip this occurrence' : 'Skip this time';
    } else { Object.assign(V, { dT:'', dCat:'', dSq:'transparent', dWhen:'', dRange:'', dDur:'', dStatus:'', dRows:[], dHist:[], dHistText:'', dStrip:[], dStripA:'', dStripB:'', dCompleteL:'', dComplete:null, dResched:null, dSkip:null, dEdit:null, dDel:null, dDelL:'', dDelC:'var(--t2)', dIsMissed:false, dMissed:null, mTitle:'', mSub:'', mOpts:[], mPick:false, mPickToggle:null, mPickChev:'none', mDays:[], mSkip:null, mDel:null, mDelL:'', mDelC:'var(--t2)', mSkipL:'' }); }
    const f = s.f || { title:'', dur:null, pref:'any', prio:'normal', recur:'never', date:null };
    V.fTitle = f.title; V.fOnTitle = e => { const val = e.target.value; this.setF({ title:val, cat:this.state.f.catSet ? this.state.f.cat : (val.trim() ? guessCat(val) : null) }); };
    V.fHeader = f.editId ? 'Edit task' : 'New task'; V.fHeard = f.heard || ''; V.fHasHeard = !!f.heard;
    V.fStage1 = !!f.title.trim(); V.fStage2 = !!f.title.trim() && !!f.dur;
    V.fSugs = f.title.trim() ? [] : [['Study polity', 'study', 120], ['Exercise', 'body', 45], ['Learn Flutter', 'build', 60], ['Read', 'self', 30], ['Call family', 'people', 30]].map(([t, c, d]) => ({ t, sq:CAT[c].c, pick:() => this.setF({ title:t, cat:c, dur:f.dur || d }) }));
    const fc = f.cat || (f.title ? guessCat(f.title) : 'self');
    V.fCat = CAT[fc].n; V.fCatSq = CAT[fc].c; V.fCatPick = !!f.catPick; V.fCatToggle = () => this.setF({ catPick:!f.catPick });
    V.fCats = CATS.map(c => ({ n:CAT[c].n, sq:CAT[c].c, bg:c === fc ? 'var(--s2)' : 'transparent', bd:c === fc ? 'var(--tx)' : 'var(--ln)', pick:() => this.setF({ cat:c, catSet:true, catPick:false }) }));
    const chip = (on) => on ? { bg:'var(--tx)', c:'var(--bg)', bd:'var(--tx)' } : { bg:'transparent', c:'var(--t2)', bd:'var(--ln)' };
    V.fDurs = [15, 30, 45, 60, 90, 120].map(m => ({ t:dur(m), ...chip(f.dur === m), pick:() => this.setF({ dur:m }) }));
    V.fDurCustom = f.dur && ![15, 30, 45, 60, 90, 120].includes(f.dur) ? dur(f.dur) : ''; V.fDurMinus = () => this.setF({ dur:Math.max(15, (f.dur || 60) - 15) }); V.fDurPlus = () => this.setF({ dur:Math.min(360, (f.dur || 60) + 15) });
    V.fDates = [[null, 'Planner picks'], [today, 'Today'], [today + 1, 'Tomorrow'], [today < 5 ? 5 : today + 1 === 6 ? 6 : 12, today < 5 ? 'Saturday' : 'Weekend']].map(([d, t]) => ({ t, ...chip(f.date === d), pick:() => this.setF({ date:d }) }));
    V.fPrefs = [['any', 'Any time'], ['morning', 'Morning'], ['afternoon', 'Afternoon'], ['evening', 'Evening']].map(([k, t]) => ({ t, ...chip(f.pref === k), pick:() => this.setF({ pref:k }) }));
    V.fExact = f.pref === 'exact'; V.fExactT = f.at != null ? fmt(f.at) : '';
    V.fMore = !!f.more; V.fMoreToggle = () => this.setF({ more:!f.more }); V.fMoreChev = f.more ? 'rotate(90deg)' : 'none';
    V.fMoreSum = [f.prio !== 'normal' ? (f.prio === 'high' ? 'High priority' : 'Low priority') : '', f.deadline != null ? `Due ${dayShort(f.deadline)}` : '', f.recur !== 'never' ? f.recur : ''].filter(Boolean).join(', ') || 'Priority, deadline, repeat';
    V.fPrios = [['low', 'Low'], ['normal', 'Normal'], ['high', 'High']].map(([k, t]) => ({ t, ...chip(f.prio === k), pick:() => this.setF({ prio:k }) }));
    V.fDeads = [[null, 'None'], [today + 2, dayShort(today + 2)], [today < 5 ? 4 : today + 3, dayShort(today < 5 ? 4 : today + 3)], [today + 7, `${DAYN[(today + 7) % 7]} ${dnum(today + 7)}`]].map(([d, t]) => ({ t, ...chip(f.deadline === d), pick:() => this.setF({ deadline:d }) }));
    V.fRecurs = ['never', 'Every day', 'Weekdays', `Every ${DAYL[((f.date != null ? f.date : today + 1)) % 7]}`].map(r => ({ t:r === 'never' ? 'Never' : r, ...chip(f.recur === r), pick:() => this.setF({ recur:r }) }));
    const pvs = s.sheet === 'create' ? this.previewSlot(f) : null;
    V.fCan = !!pvs; V.fBtn = f.editId ? 'Save' : 'Schedule'; V.fBtnO = pvs ? '1' : '0.4';
    if (pvs) { const pc2 = capOf(pvs.d, R, s.tasks.filter(t => t.id !== f.editId).concat([{ ...mk('pv', f.title, fc, pvs.d, pvs.s, f.dur) }]), pvs.d === today ? now : 0);
      V.fPreview = `${pvs.d === today ? 'Today' : pvs.d === today + 1 ? 'Tomorrow' : DAYL[pvs.d % 7]} ${fmt(pvs.s)} → ${fmt(pvs.e)}`;
      V.fPreviewSub = pvs.over || pc2.over > 15 ? `This goes ${dur(Math.max(pc2.over, 15))} past what fits. Planner will ask before keeping it.` : `${dur(Math.max(0, pc2.real - pc2.planned))} of realistic time left after this.`; }
    else { V.fPreview = f.title && f.dur ? 'No room in the next 7 days' : f.title ? 'Pick a duration' : 'Planner will find the time'; V.fPreviewSub = ''; }
    V.fSchedule = () => this.schedule(); V.fVoice = () => { this.closeSheet(); this.at(200, () => this.tapOrb()); };

    /* ===== review ===== */
    V.rvOn = s.review; V.rvO = s.review ? '1' : '0'; V.rvPE = s.review ? 'auto' : 'none'; V.rvT = s.review ? 'none' : 'translateY(3%)';
    const rs0 = s.rStage, ron = s.rOn;
    V.rvBars = [0, 1, 2, 3, 4, 5].map(i => ({ t:i < rs0 ? 'scaleX(1)' : i === rs0 ? (ron ? 'scaleX(1)' : 'scaleX(0)') : 'scaleX(0)', tr:i === rs0 && ron ? 'transform calc(var(--m,1) * 900ms) cubic-bezier(.2,.8,.2,1)' : 'none' }));
    ['r0', 'r1', 'r2', 'r3', 'r4', 'r5'].forEach((k, i) => { V[k] = rs0 === i; });
    V.rIn = ron ? '1' : '0'; V.rInT = ron ? 'none' : 'translateY(16px)';
    V.rNext = () => this.rGo(rs0 + 1); V.rPrev = () => this.rGo(rs0 - 1); V.rClose = () => this.closeReview(); V.rPlan = () => this.planNext();
    V.rSq = Array.from({ length:24 }, (_, i) => { const cats = ['study', 'study', 'build', 'study', 'self', 'people', 'study', 'build', 'body', 'study', 'self', 'build', 'study', 'people', 'build', 'study', 'self', 'body', 'study'];
      const on = i < 19; return { bg:on && ron ? CAT[cats[i]].c : 'transparent', bd:on ? CAT[cats[i] || 'study'].c : 'var(--t3)', d:`calc(var(--m,1) * ${300 + i * 45}ms)`, o:ron ? '1' : '0' }; });
    V.rCats = [['study', 8.67], ['build', 5.5], ['self', 2]].map(([c, h], i) => ({ n:CAT[c].n, v:hrs(h), sq:CAT[c].c, w:ron ? (h / 8.67 * 100) + '%' : '0%', d:`calc(var(--m,1) * ${200 + i * 160}ms)` }));
    V.rMoves = [['Rescheduled', '4', 'Exercise, Flutter and 2 more found new times'], ['Skipped', '2', 'Flutter state management, Read fiction'], ['Carried forward', '1', 'Journal moves into next week']].map(([k, n, d], i) => ({ k, n, d, o:ron ? '1' : '0', t:ron ? 'none' : 'translateX(-14px)', dl:`calc(var(--m,1) * ${250 + i * 180}ms)` }));
    V.rHeat = [1, 2, 3, 4, 5, 6].map(r => ({ cells:Array.from({ length:36 }, (_, c) => { const lv = HEATF(r, c); return { o:ron ? String(lv ? [0, 0.18, 0.36, 0.62, 1][lv] : 1) : '0', bg:lv ? 'var(--tx)' : 'var(--s1)', d:`calc(var(--m,1) * ${(r + c) * 9}ms)` }; }) }));
    V.rAhead = s.deadlines.concat(s.upcoming).filter(x => x.day > today).map(x => ({ title:x.title.replace(/ due$/, ''), when:`${DAYN[x.day % 7]} ${dnum(x.day)} ${dmons(x.day)}`, sq:CAT[x.cat].c }));
    V.rRibbon = V.ribbon; V.rEnvTop = V.envTop; V.rEnvBot = V.envBot; V.rClip = ron ? 'inset(0 0% 0 0)' : 'inset(0 100% 0 0)';

    /* ===== settings ===== */
    V.setOn = inSet; V.setT = inSet ? 'none' : 'translateX(100%)'; V.setPE = inSet ? 'auto' : 'none';
    V.sRoot = s.sPage === 'root'; V.sDrive = s.sPage === 'drive'; V.sBack = () => this.setState({ sPage:'root' }); V.sClose = () => this.setState({ settings:false });
    V.sDriveT = s.sPage === 'drive' ? 'none' : 'translateX(100%)'; V.sRootT = s.sPage === 'drive' ? 'translateX(-24%)' : 'none'; V.sRootO = s.sPage === 'drive' ? '0' : '1';
    const onoff = (on) => ({ tb:on ? 'var(--tx)' : 'var(--s2)', th:on ? 'translateX(16px)' : 'translateX(0)', thc:on ? 'var(--bg)' : 'var(--t2)', aria:String(!!on) });
    V.sRoutine = [['Wake', fmt(R.wake)], ['Work', R.noWork ? 'No fixed hours' : `${fmt(R.ws)} → ${fmt(R.we)}`], ['Sleep', fmt(R.sleep)], ['Commitments', `${R.commits.filter(c => c.on).length} recurring`]].map(([k, val]) => ({ k, v:val }));
    V.editRoutine = () => this.editRoutine();
    V.sNotif = [['next', 'Next task', '5 minutes before it starts'], ['missed', 'Missed tasks', 'One gentle check-in, never a pile-up'], ['review', 'Weekly review', 'Sunday at 21:00']].map(([k, t, d]) => ({ t, d, ...onoff(s.notif[k]), flip:() => this.setState(x => ({ notif:{ ...x.notif, [k]:!x.notif[k] } })) }));
    V.sWake = { ...onoff(s.wakeOn), flip:() => this.setState(x => ({ wakeOn:!x.wakeOn })) };
    V.sMicState = s.micOK ? 'Allowed' : 'Not allowed'; V.sMicFix = () => this.setState({ micOK:true });
    const seg3 = (opts, cur, set) => opts.map(([k, t]) => ({ t, c:cur === k ? 'var(--tx)' : 'var(--t3)', bg:cur === k ? 'var(--s2)' : 'transparent', go:() => set(k), pressed:String(cur === k) }));
    V.sTheme = seg3([[null, 'System'], ['dark', 'Dark'], ['light', 'Light']], s.themeLocal, k => this.setState({ themeLocal:k }));
    V.sMotion = seg3([[null, 'System'], [true, 'Reduced'], [false, 'Full']], s.rmLocal, k => this.setState({ rmLocal:k }));
    V.sDialDef = seg3([[false, 'Strip'], [true, 'Dial']], s.dialDefault, k => this.setState({ dialDefault:k, view:k ? 'dial' : 'strip' }));
    V.sStatSkip = { ...onoff(s.statSkip), flip:() => this.setState(x => ({ statSkip:!x.statSkip })) };
    const ds = !s.online && s.drive !== 'off' && s.drive !== 'conflict' ? 'offline' : s.drive;
    V.sDriveStatus = { off:'Not connected', connecting:'Connecting…', synced:`Backed up ${s.lastBackup ? s.lastBackup.toLowerCase() : ''}`.trim(), backing:'Backing up…', restoring:'Restoring…', offline:'Offline, waiting to back up', conflict:'Needs a decision' }[ds];
    V.openDrive = () => this.setState({ sPage:'drive' });
    V.dvOff = ds === 'off'; V.dvConnecting = ds === 'connecting'; V.dvSynced = ds === 'synced'; V.dvBusy = ds === 'backing' || ds === 'restoring'; V.dvOffline = ds === 'offline'; V.dvConflict = ds === 'conflict'; V.dvConnected = ds === 'synced' || ds === 'offline' || ds === 'backing' || ds === 'restoring';
    V.dvBusyL = ds === 'restoring' ? 'Restoring from Drive' : 'Backing up to Drive'; V.dvProg = s.driveProg + '%'; V.dvProgT = `${s.driveProg}%`;
    V.dvLast = s.lastBackup || 'Never'; V.dvAuto = { ...onoff(s.autoBackup), flip:() => this.setState(x => ({ autoBackup:!x.autoBackup })) };
    V.dvGo = k => () => this.driveGo(k);
    V.dvConnect = () => this.driveGo('connect'); V.dvBackup = () => this.driveGo('backup'); V.dvRestore = () => this.driveGo('restore'); V.dvDisconnect = () => this.driveGo('disconnect');
    V.dvKeepPhone = () => this.driveGo('keepPhone'); V.dvUseDrive = () => this.driveGo('useDrive');
    V.dvBackupO = s.online ? '1' : '0.4'; V.dvBackupDis = !s.online;
    V.restoreAsk = s.restoreAsk; V.restoreYes = () => this.driveGo('restoreYes'); V.restoreNo = () => this.driveGo('restoreNo');
    V.syncGlyph = ds === 'offline' ? ICON.cloudoff : ICON.cloud;

    /* ===== note ===== */
    const nt = s.note;
    V.noteO = nt ? '1' : '0'; V.noteT = nt ? 'none' : 'translateY(12px)'; V.notePE = nt ? 'auto' : 'none'; V.noteText = nt ? nt.text : '';
    V.noteHasAct = !!(nt && nt.act); V.noteAct = nt && nt.act ? nt.act.label : ''; V.noteGo = () => { if (nt && nt.act) nt.act.fn(); this.setState({ note:null }); };
    V.noteBottom = s.settings || s.review ? '24px' : '96px';
    V.I = ICON; V.yes = true;
    V.dCompleteD = V.dIsMissed ? 'none' : 'block'; V.fDis = !V.fCan; V.fHasSugs = (V.fSugs || []).length > 0; V.noReview = !wc;
    V.dataExport = () => this.say('Exported planner-2026-09-29.json to Downloads.');
    V.dataDelL = this.dataArm ? 'Tap again to erase everything on this phone' : 'Delete all data'; V.dataDelC = this.dataArm ? CAT.body.c : 'var(--t2)';
    V.dataDel = () => { if (this.dataArm) { this.dataArm = false; this.jump('onboard'); return; } this.dataArm = true; this.forceUpdate(); clearTimeout(this.dataT); this.dataT = setTimeout(() => { this.dataArm = false; this.forceUpdate(); }, 4000); };
    return V;
  }
}
