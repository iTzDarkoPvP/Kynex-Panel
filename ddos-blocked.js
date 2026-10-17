'use strict';
/* Cuenta los paquetes que la proteccion anti-DDoS existente (cadena KYNEX_DDOS) descarta.
   No agrega reglas ni bloquea nada: solo lee los contadores de iptables. */
const fs = require('fs'), path = require('path');
module.exports = function (D) {
  const { DATA_DIR, IS_ROOT, iptOut, ddosAvail, readJSON, requireAuth, requireSystemPerm } = D;
  const FILE = path.join(DATA_DIR, 'ddos-blocked.json');
  let S = readJSON(FILE, null) || {};
  S.pkts = S.pkts || 0; S.bytes = S.bytes || 0; S.since = S.since || Date.now(); S.byKey = S.byKey || {};
  const prev = new Map(), samples = [];
  let baselined = false, lastAt = 0, busy = null, saveT = null;
  const save = () => {
    if (saveT) return;
    saveT = setTimeout(() => { saveT = null; try { const tmp = FILE + '.tmp'; fs.writeFileSync(tmp, JSON.stringify(S)); fs.renameSync(tmp, FILE); } catch (e) {} }, 2000);
    if (saveT.unref) saveT.unref();
  };
  function parse(txt) {
    const out = []; if (!txt) return out;
    for (const ln of txt.split('\n')) {
      const m = ln.match(/^\s*(\d+)\s+(\d+)\s+DROP\s+(\S+)\s+--\s+\S+\s+\S+\s+\S+\s+\S+\s*(.*)$/); if (!m) continue;
      const d = (m[4].match(/dpt:(\d+)/) || [])[1];
      out.push({ pkts: +m[1], bytes: +m[2], prot: m[3], dpt: d || '*' });
    }
    return out;
  }
  function sample() {
    if (busy) return busy;
    busy = (async () => {
      try {
        if (!IS_ROOT || !(await ddosAvail())) return;
        const txt = await iptOut(['-L', 'KYNEX_DDOS', '-v', '-n', '-x']);
        const cur = new Map();
        for (const r of parse(txt)) { const k = r.prot + '|' + r.dpt, x = cur.get(k) || { p: 0, b: 0 }; x.p += r.pkts; x.b += r.bytes; cur.set(k, x); }
        const now = Date.now(); let dP = 0, dB = 0;
        for (const [k, v] of cur) {
          const pv = prev.get(k); let dp = 0, db = 0;
          if (pv) { dp = v.p - pv.p; db = v.b - pv.b; if (dp < 0 || db < 0) { dp = v.p; db = v.b; } }
          else if (baselined) { dp = v.p; db = v.b; }
          if (dp > 0 || db > 0) {
            const t = S.byKey[k] || (S.byKey[k] = { p: 0, b: 0, last: 0 });
            t.p += dp; t.b += db; t.last = now; dP += dp; dB += db;
          }
        }
        S.pkts += dP; S.bytes += dB;
        prev.clear(); for (const [k, v] of cur) prev.set(k, v);
        const el = (now - lastAt) / 1000;
        if (baselined && el >= 0.5) { samples.push({ t: now, pps: Math.round(dP / el), bps: Math.round(dB * 8 / el) }); if (samples.length > 240) samples.shift(); }
        lastAt = now; baselined = true; save();
      } catch (e) {} finally { busy = null; }
    })();
    return busy;
  }
  function quick() {
    const l = samples.slice(-3);
    return { pps: l.length ? Math.round(l.reduce((s, x) => s + x.pps, 0) / l.length) : 0, total: S.pkts };
  }
  function routes(app) {
    const auth = [requireAuth, requireSystemPerm];
    app.get('/api/ddos/blocked', ...auth, (req, res) => {
      const l = samples.slice(-3), bps = l.length ? Math.round(l.reduce((s, x) => s + x.bps, 0) / l.length) : 0;
      const ports = Object.entries(S.byKey).map(([k, v]) => { const q = k.split('|'); return { prot: q[0], port: q[1], pkts: v.p, bytes: v.b, last: v.last }; }).sort((a, b) => b.pkts - a.pkts).slice(0, 30);
      res.json({ success: true, root: IS_ROOT, pps: quick().pps, bps, totals: { pkts: S.pkts, bytes: S.bytes, since: S.since }, ports, samples: samples.slice(-120) });
    });
    app.post('/api/ddos/blocked/reset', ...auth, (req, res) => { S = { pkts: 0, bytes: 0, since: Date.now(), byKey: {} }; samples.length = 0; save(); res.json({ success: true }); });
  }
  let started = false;
  function start() { if (started) return; started = true; const t = setInterval(() => { sample().catch(() => {}); }, 5000); if (t.unref) t.unref(); }
  return { sample, quick, routes, start };
};
