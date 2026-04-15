// Supabase Edge Function: Cloudflare Custom Hostname proxy.
// Replaces Firebase Cloud Functions: addCustomDomain / checkDomainStatus / removeCustomDomain.
//
// Deploy:
//   cd "api supabase" && supabase functions deploy cf-custom-hostname --no-verify-jwt
//   supabase secrets set CLOUDFLARE_API_TOKEN=cfut_... CLOUDFLARE_ZONE_ID=2dbf35fb5bd6b3330abe31754f6fd5e8
//
// Usage (from rmsproapp Flutter):
//   POST { action: 'add', hostname, ownerID }
//   POST { action: 'check', hostname }
//   POST { action: 'remove', hostname }
//   POST { action: 'list' }

// deno-lint-ignore-file no-explicit-any
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const TOKEN = Deno.env.get('CLOUDFLARE_API_TOKEN')!;
const ZONE = Deno.env.get('CLOUDFLARE_ZONE_ID') || '2dbf35fb5bd6b3330abe31754f6fd5e8';
const FALLBACK_ORIGIN = Deno.env.get('CF_FALLBACK_ORIGIN') || 'rmspro-web.pages.dev';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

async function cf(method: string, path: string, body?: unknown) {
  const r = await fetch(`https://api.cloudflare.com/client/v4${path}`, {
    method,
    headers: { 'Authorization': `Bearer ${TOKEN}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  const json = await r.json();
  if (!json.success) throw new Error(JSON.stringify(json.errors));
  return json.result;
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405, headers: cors });

  try {
    const { action, hostname, ownerID } = await req.json();
    const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

    if (action === 'list') {
      const list = await cf('GET', `/zones/${ZONE}/custom_hostnames?per_page=100`);
      return Response.json({ ok: true, hostnames: list }, { headers: cors });
    }

    if (action === 'add') {
      const r = await cf('POST', `/zones/${ZONE}/custom_hostnames`, {
        hostname,
        ssl: { method: 'http', type: 'dv', settings: { http2: 'on', min_tls_version: '1.2' } },
      });
      if (ownerID) {
        await sb.from('tenants')
          .update({ domain: hostname, domain_status: 'PENDING_DNS' })
          .eq('owner_id', ownerID);
      }
      return Response.json({
        ok: true,
        domain: hostname,
        status: 'PENDING_DNS',
        message: `Tenant kena set DNS CNAME: ${hostname} → ${FALLBACK_ORIGIN}`,
        dnsRecords: [{ type: 'CNAME', name: hostname, value: FALLBACK_ORIGIN, proxy: true }],
      }, { headers: cors });
    }

    if (action === 'check') {
      const list = await cf('GET', `/zones/${ZONE}/custom_hostnames?hostname=${hostname}`);
      const h = list[0];
      if (!h) return Response.json({ ok: false, error: 'not found' }, { status: 404, headers: cors });
      const status = h.ssl?.status === 'active' && h.status === 'active' ? 'ACTIVE' : 'PENDING_DNS';
      await sb.from('tenants').update({ domain_status: status }).eq('domain', hostname);
      return Response.json({ ok: true, hostname, status, ssl: h.ssl?.status, verification: h.verification_data }, { headers: cors });
    }

    if (action === 'remove') {
      const list = await cf('GET', `/zones/${ZONE}/custom_hostnames?hostname=${hostname}`);
      if (list[0]) await cf('DELETE', `/zones/${ZONE}/custom_hostnames/${list[0].id}`);
      await sb.from('tenants').update({ domain: null, domain_status: 'PENDING_DNS' }).eq('domain', hostname);
      return Response.json({ ok: true }, { headers: cors });
    }

    return new Response(JSON.stringify({ ok: false, error: 'unknown action' }), { status: 400, headers: cors });
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, error: (e as Error).message }), { status: 500, headers: cors });
  }
});
