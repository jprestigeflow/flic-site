// POST /api/license  {key, reason}   -> {ok, message, download?}
// GET  /api/license?key=...          -> {ok, message}
//
// Checks a FLIC license key against Whop (membership looked up by license key) and,
// when valid, returns the private download link for the installer to fetch.
// Secrets live in the Pages project settings, never in this repo:
//   WHOP_API_KEY    Whop API key with the member:basic:read scope
//   DOWNLOAD_PATH   e.g. /dl/<long random token>/flic.zip  (the zip's unguessable path)
// Optional: FLIC_PRODUCT_ID (default prod_qv0QRq4EufGNY) to refuse keys from other products.

const PRODUCT = 'prod_qv0QRq4EufGNY';
const GOOD = new Set(['active', 'trialing', 'completed', 'past_due']);
const KEY_RE = /^[A-Za-z0-9-]{8,80}$/;

const json = (obj, status = 200) =>
  new Response(JSON.stringify(obj), { status, headers: { 'content-type': 'application/json', 'cache-control': 'no-store' } });

async function check(env, key) {
  if (!env.WHOP_API_KEY) return { ok: false, message: 'License server is not configured yet. Try again later.' };
  if (!KEY_RE.test(key || '')) return { ok: false, message: 'That does not look like a FLIC license key.' };
  const r = await fetch(`https://api.whop.com/api/v1/memberships/${encodeURIComponent(key)}`, {
    headers: { Authorization: `Bearer ${env.WHOP_API_KEY}`, 'Api-Version-Date': '2026-10-15' },
  });
  if (r.status === 404) return { ok: false, message: 'License key not found. Copy it from your Whop purchase page.' };
  if (!r.ok) return { ok: false, message: `License check failed (${r.status}). Try again in a minute.` };
  const m = await r.json();
  const prodId = (m.product && m.product.id) || m.product_id || '';
  const want = env.FLIC_PRODUCT_ID || PRODUCT;
  if (prodId && prodId !== want) return { ok: false, message: 'This key belongs to a different product.' };
  if (!GOOD.has(m.status)) return { ok: false, message: `This license is ${m.status || 'not active'}.` };
  return { ok: true, message: 'License OK' };
}

export async function onRequestPost({ request, env }) {
  let body = {};
  try { body = await request.json(); } catch {}
  const res = await check(env, String(body.key || '').trim());
  if (res.ok && env.DOWNLOAD_PATH) res.download = new URL(env.DOWNLOAD_PATH, request.url).toString();
  return json(res, res.ok ? 200 : 403);
}

export async function onRequestGet({ request, env }) {
  const key = new URL(request.url).searchParams.get('key') || '';
  const res = await check(env, key.trim());
  return json(res, res.ok ? 200 : 403);
}
