#!/usr/bin/env node
/**
 * Cloudflare for SaaS — Custom Hostname API wrapper.
 *
 * Usage:
 *   node 07_cf_custom_hostname.js list
 *   node 07_cf_custom_hostname.js add <hostname>            # e.g. kedaixyz.com
 *   node 07_cf_custom_hostname.js remove <hostname>
 *   node 07_cf_custom_hostname.js sync-tenants              # for each tenants.domain → register
 *
 * Token requirements (Profixkl@gmail.com Cloudflare account):
 *   - Zone:SSL and Certificates:Edit
 *   - Zone:Custom Hostnames:Edit (rmspro.net zone)
 *   - Account:Cloudflare Pages:Edit
 *   - Zone:DNS:Edit (kalau nak auto-CNAME tenant zone — biasanya tidak)
 *
 * Env vars (api supabase/.env):
 *   CLOUDFLARE_API_TOKEN
 *   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (untuk sync-tenants)
 */
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });

const TOKEN = process.env.CLOUDFLARE_API_TOKEN;
const ZONE = '2dbf35fb5bd6b3330abe31754f6fd5e8'; // rmspro.net
const FALLBACK_ORIGIN = 'rmspro-web.pages.dev';

if (!TOKEN) {
  console.error('CLOUDFLARE_API_TOKEN tidak set dalam api supabase/.env');
  process.exit(1);
}

async function cf(method, path, body) {
  const r = await fetch(`https://api.cloudflare.com/client/v4${path}`, {
    method,
    headers: {
      'Authorization': `Bearer ${TOKEN}`,
      'Content-Type': 'application/json',
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const json = await r.json();
  if (!json.success) throw new Error(`CF ${method} ${path}: ${JSON.stringify(json.errors)}`);
  return json.result;
}

async function listHostnames() {
  const list = await cf('GET', `/zones/${ZONE}/custom_hostnames?per_page=50`);
  console.log(`${list.length} custom hostname(s):`);
  list.forEach((h) => {
    console.log(`  ${h.hostname.padEnd(35)} ssl=${h.ssl?.status || '—'} status=${h.status}`);
  });
}

async function addHostname(hostname) {
  console.log(`+ ${hostname}`);
  const r = await cf('POST', `/zones/${ZONE}/custom_hostnames`, {
    hostname,
    ssl: {
      method: 'http',
      type: 'dv',
      settings: { http2: 'on', min_tls_version: '1.2' },
    },
  });
  console.log(`  ✓ id=${r.id} ssl=${r.ssl?.status}`);
  console.log(`  → Tenant kena set DNS CNAME: ${hostname} → ${FALLBACK_ORIGIN}`);
  return r;
}

async function removeHostname(hostname) {
  const list = await cf('GET', `/zones/${ZONE}/custom_hostnames?hostname=${hostname}`);
  if (!list.length) { console.log(`- ${hostname} (not found)`); return; }
  await cf('DELETE', `/zones/${ZONE}/custom_hostnames/${list[0].id}`);
  console.log(`- ${hostname} removed`);
}

async function syncFromTenants() {
  const { createClient } = require('@supabase/supabase-js');
  const sb = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);
  const { data: tenants, error } = await sb.from('tenants').select('id, domain, shop_name').not('domain', 'is', null);
  if (error) throw error;
  console.log(`${tenants.length} tenant(s) ada domain.`);
  const existing = await cf('GET', `/zones/${ZONE}/custom_hostnames?per_page=100`);
  const haveSet = new Set(existing.map((h) => h.hostname));
  for (const t of tenants) {
    if (haveSet.has(t.domain)) { console.log(`  = ${t.domain} (${t.shop_name}) — already registered`); continue; }
    try {
      await addHostname(t.domain);
      await sb.from('tenants').update({ domain_status: 'PENDING_DNS' }).eq('id', t.id);
    } catch (e) {
      console.error(`  ✗ ${t.domain}: ${e.message}`);
    }
  }
}

const [, , cmd, arg] = process.argv;
(async () => {
  switch (cmd) {
    case 'list': return listHostnames();
    case 'add': if (!arg) throw new Error('hostname required'); return addHostname(arg);
    case 'remove': if (!arg) throw new Error('hostname required'); return removeHostname(arg);
    case 'sync-tenants': return syncFromTenants();
    default:
      console.log('Usage: node 07_cf_custom_hostname.js <list|add|remove|sync-tenants> [hostname]');
      process.exit(1);
  }
})().catch((e) => { console.error('ERROR:', e.message); process.exit(1); });
